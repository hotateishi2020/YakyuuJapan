import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'YahooHtml.dart';
import 'package:postgres/postgres.dart';
import 'PlayerIdentityName.dart';
import 'PlayerName.dart';

/// All incoming source names are retained, Japanese display names are never
/// overwritten by an English refresh. Ambiguity is an explicit review result.
class PlayerIdentity {
  static Map<String, Map<String, String>>? _crosswalk;
  static Map<String, String> _linkedSource(String? source, String? id) {
    if (source == null || id == null) return const {};
    if (_crosswalk == null) {
      _crosswalk = {};
      final paths = ['data/npb_mlb_player_ids.json', 'backend/data/npb_mlb_player_ids.json'];
      final file = paths.map(File.new).where((f) => f.existsSync()).firstOrNull;
      if (file != null) {
        final rows = (jsonDecode(file.readAsStringSync()) as Map)['players'] as List;
        final ambiguous = <String>{};
        for (final row in rows) {
          for (final pair in [('npb', 'mlb'), ('mlb', 'npb')]) {
            final key = '${pair.$1}:${row['${pair.$1}_id']}';
            final value = {pair.$2: '${row['${pair.$2}_id']}'};
            if (_crosswalk!.containsKey(key) && _crosswalk![key]![pair.$2] != value[pair.$2]) ambiguous.add(key);
            _crosswalk![key] = value;
          }
        }
        for (final key in ambiguous) {
          _crosswalk!.remove(key);
        }
      }
    }
    return _crosswalk!['$source:$id'] ?? const {};
  }

  static Future<int?> find(Connection conn, {required String name, required int teamId, String? source, String? externalId, String? url, DateTime? birthDate, bool allowUniqueAbbreviation = false}) async {
    final yahooId = RegExp(r'/mlb/player/(\d+)').firstMatch(url ?? '')?[1];
    final ids = <String, String>{
      ..._linkedSource(source, externalId),
      if (source != null && externalId != null && externalId.isNotEmpty) source: externalId,
      if (yahooId != null) 'yahoo_mlb': yahooId,
    };
    if (ids.isNotEmpty) {
      final found = await conn.execute(r'''
        SELECT id,name_full,name_last,name_first_initial,name_patterns FROM m_player WHERE NOT coalesce(flg_delete,false)
        AND (EXISTS(SELECT 1 FROM jsonb_each_text($1::jsonb) linked WHERE identity_sources->>linked.key=linked.value)
          OR (source_key=$2 AND external_id=$3)
          OR ($4::text IS NOT NULL AND substring(url from '/mlb/player/([0-9]+)')=$4))
      ''', parameters: [jsonEncode(ids), source, externalId, yahooId]);
      if (found.length == 1) {
        final p = found.single.toColumnMap();
        final full = '${p['name_full']}';
        if (hasJapanesePlayerName(name) && hasJapanesePlayerName(full) && !matchesPlayerPatterns(name, [full, ...List<String>.from(p['name_patterns'] as List? ?? [])]) && !playerNameMatches(query: name, nameFull: full, nameLast: '${p['name_last'] ?? ''}', storedInitial: '${p['name_first_initial'] ?? ''}')) {
          await review(conn, name, teamId, [p['id']], 'source ID and Japanese player name conflict');
          throw StateError('Source ID/name conflict: $name / $full');
        }
        return p['id'] as int;
      }
      if (found.length > 1) {
        await review(conn, name, teamId, found.map((r) => r[0]).toList(), 'source ID collision');
        return null;
      }
    }
    final rows = await conn.execute(r'''
      SELECT id,name_full,name_last,name_first_initial,name_patterns,date_birth,
             source_key,external_id,identity_sources
      FROM m_player WHERE NOT coalesce(flg_delete,false)
        AND (id_team=$1 OR ($2::timestamp IS NOT NULL AND date_birth=$2)
          OR ($3::bool AND identity_sources ? 'npb' AND player_identity_key($4)=ANY(name_pattern_keys)))
        AND ($2::timestamp IS NULL OR date_birth IS NULL OR date_birth=$2)
    ''', parameters: [teamId, birthDate, source == 'npb' && (externalId ?? '').startsWith('name:'), name]);
    final candidates = rows.map((r) => r.toColumnMap()).where((p) {
      final sources = p['identity_sources'] is Map ? p['identity_sources'] as Map : const {};
      for (final entry in ids.entries) {
        if (sources[entry.key] != null && !'${sources[entry.key]}'.startsWith('name:') && !entry.value.startsWith('name:') && '${sources[entry.key]}' != entry.value) {
          return false;
        }
      }
      return true;
    }).toList();
    final exact = candidates.where((p) => matchesPlayerPatterns(name, ['${p['name_full'] ?? ''}', ...List<String>.from(p['name_patterns'] as List? ?? [])])).toList();
    if (exact.length == 1) return exact.single['id'] as int;
    if (exact.length > 1) {
      await review(conn, name, teamId, exact.map((p) => p['id']).toList(), 'ambiguous registered pattern');
      return null;
    }
    if (allowUniqueAbbreviation) {
      final weak = candidates.where((p) => playerNameMatches(query: name, nameFull: '${p['name_full'] ?? ''}', nameLast: '${p['name_last'] ?? ''}', storedInitial: '${p['name_first_initial'] ?? ''}')).toList();
      if (weak.length == 1) return weak.single['id'] as int;
      if (weak.length > 1) {
        await review(conn, name, teamId, weak.map((p) => p['id']).toList(), 'ambiguous surname/initial');
      }
    }
    return null;
  }

  static Future<void> remember(Connection conn, int id, String name, {String? source, String? externalId, String? url}) async {
    final yahoo = RegExp(r'/mlb/player/(\d+)').firstMatch(url ?? '')?[1];
    await conn.execute(r'''
      UPDATE m_player SET name_patterns=array_append(name_patterns,$2),
        name_ja=CASE WHEN coalesce(name_ja,'')='' AND $2 ~ '[ぁ-んァ-ヶ一-龯]' THEN $2 ELSE name_ja END,
        identity_sources=identity_sources || $3::jsonb,
        url=coalesce(nullif(url,''),nullif($4,'')),
        source_key=coalesce(nullif(source_key,''),$5),
        external_id=CASE WHEN coalesce(source_key,$5)=$5 THEN CASE WHEN external_id LIKE 'name:%' AND $6 NOT LIKE 'name:%' THEN $6 ELSE coalesce(nullif(external_id,''),$6) END ELSE external_id END,updat=now()
      WHERE id=$1 AND NOT coalesce(flg_delete,false)
    ''', parameters: [
      id,
      name,
      jsonEncode({if (source != null && externalId != null) source: externalId, if (yahoo != null) 'yahoo_mlb': yahoo}),
      url,
      source,
      externalId
    ]);
  }

  /// Serialized registration; a suspected existing person is queued, not
  /// registered again and not silently assigned to a different player.
  static Future<int> ensure(Connection conn, {required String name, required int teamId, String? source, String? externalId, String? url, DateTime? birthDate}) async {
    {
      final id = await find(conn, name: name, teamId: teamId, source: source, externalId: externalId, url: url, birthDate: birthDate, allowUniqueAbbreviation: source == null);
      if (id != null) {
        if (birthDate != null) await conn.execute('UPDATE m_player SET date_birth=coalesce(date_birth,\$2::timestamp) WHERE id=\$1', parameters: [id, birthDate]);
        await remember(conn, id, name, source: source, externalId: externalId, url: url);
        return id;
      }
      var registrationName = name;
      if ((url ?? '').contains('baseball.yahoo.co.jp/mlb/player/')) {
        final doc = await YahooHtml.fetchDocument(Uri.parse(url!));
        final value = doc.querySelector('.bb-profile__list')?.text ?? '';
        final date = RegExp(r'(\d{4})年(\d+)月(\d+)日').firstMatch(value);
        if (date == null) {
          throw StateError('Player profile has no verifiable birth date: $url');
        }
        birthDate ??= DateTime.utc(int.parse(date[1]!), int.parse(date[2]!), int.parse(date[3]!));
        final display = doc.querySelector('.bb-profile__ruby')?.text.trim() ?? '';
        if (display.isNotEmpty) registrationName = display;
      }
      final bilingual = await _resolveBilingual(conn, name: name, teamId: teamId, source: source, externalId: externalId, url: url, birthDate: birthDate);
      if (bilingual != null) {
        await remember(conn, bilingual, name, source: source, externalId: externalId, url: url);
        return bilingual;
      }
      if (source == null && (url == null || url.isEmpty)) {
        if (birthDate == null) {
          await review(conn, name, teamId, [], 'unidentified name without profile or birth date');
          return 0;
        }
        final mlb = await conn.execute('SELECT id FROM m_team WHERE id=\$1 AND id_league IN(3,4)', parameters: [teamId]);
        if (mlb.isNotEmpty) {
          await review(conn, name, teamId, [], 'unidentified live name; needs source profile');
          return 0;
        }
      }

      final possible = await conn.execute(r'''
        SELECT id,name_full,name_last,name_first_initial,name_patterns,date_birth,identity_sources
        FROM m_player WHERE NOT coalesce(flg_delete,false) AND id_team=$1
      ''', parameters: [teamId]);
      final suspects = possible
          .where((r) {
            final p = r.toColumnMap();
            final identities = p['identity_sources'] is Map ? p['identity_sources'] as Map : const {};
            // Different official IDs are evidence of different players.
            if (source != null && externalId != null && identities[source] != null && !'${identities[source]}'.startsWith('name:') && !externalId.startsWith('name:') && '${identities[source]}' != externalId) {
              return false;
            }
            if (birthDate != null && p['date_birth'] != null && ((p['date_birth'] as DateTime).year != birthDate.year || (p['date_birth'] as DateTime).month != birthDate.month || (p['date_birth'] as DateTime).day != birthDate.day)) {
              return false;
            }
            return (birthDate != null && p['date_birth'] != null) || matchesPlayerPatterns(name, List<String>.from(p['name_patterns'] as List? ?? [])) || playerNameMatches(query: name, nameFull: '${p['name_full']}', nameLast: '${p['name_last'] ?? ''}', storedInitial: '${p['name_first_initial'] ?? ''}');
          })
          .map((r) => r.toColumnMap()['id'])
          .toList();
      if (suspects.isNotEmpty) {
        await review(conn, name, teamId, suspects, 'registration held: identity needs evidence');
        return 0;
      }
      final inserted = await conn.execute(r'''
        SELECT register_player_identity($1::text,$2::int,$3::timestamp,$4::text,$5::text,$6::text)
      ''', parameters: [registrationName, teamId, birthDate, source, externalId, url]);
      final created = inserted.single[0] as int;
      await remember(conn, created, name, source: source, externalId: externalId, url: url);
      return created;
    }
  }

  static Future<int?> _resolveBilingual(Connection conn, {required String name, required int teamId, String? source, String? externalId, String? url, DateTime? birthDate}) async {
    final isYahoo = (url ?? '').contains('baseball.yahoo.co.jp/mlb/player/');
    if (!isYahoo && !(source == 'mlb' && externalId != null && birthDate != null)) {
      return null;
    }
    Future<Map<String, dynamic>> profile(String address) async {
      final doc = await YahooHtml.fetchDocument(Uri.parse(address));
      final display = doc.querySelector('.bb-profile__ruby')?.text.trim() ?? '';
      final fields = <String, String>{};
      for (final item in doc.querySelectorAll('.bb-profile__item')) {
        fields[item.querySelector('dt')?.text.trim() ?? ''] = item.querySelector('dd')?.text.trim() ?? '';
      }
      final date = RegExp(r'(\d{4})年(\d+)月(\d+)日').firstMatch(fields['生年月日（満年齢）'] ?? '');
      return {'name': display, 'birth': date == null ? null : DateTime.utc(int.parse(date[1]!), int.parse(date[2]!), int.parse(date[3]!)), 'height': num.tryParse((fields['身長'] ?? '').replaceAll('cm', '')), 'hands': fields['投打']};
    }

    bool same(Map<String, dynamic> ja, Map<String, dynamic> en) {
      final born = DateTime.tryParse('${en['birthDate']}');
      final date = ja['birth'] as DateTime?;
      final height = RegExp(r"(\d+)'\s*(\d+)").firstMatch('${en['height']}');
      if (date == null || born == null || date.year != born.year || date.month != born.month || date.day != born.day || height == null || ja['height'] == null) {
        return false;
      }
      final cm = (int.parse(height[1]!) * 12 + int.parse(height[2]!)) * 2.54;
      const hand = {'R': '右', 'L': '左', 'S': '両'};
      final hands = '${hand[(en['pitchHand'] as Map?)?['code']]}投${hand[(en['batSide'] as Map?)?['code']]}打';
      return (cm - (ja['height'] as num)).abs() <= 1.1 && hands == ja['hands'];
    }

    try {
      final japanese = isYahoo ? await profile(url!) : null;
      if (japanese != null && hasJapanesePlayerName(name) && !matchesPlayerPatterns(name, ['${japanese['name']}']) && !playerNameMatches(query: name, nameFull: '${japanese['name']}')) {
        throw StateError('Yahoo profile name conflicts with incoming name: $name');
      }

      final birth = japanese?['birth'] ?? birthDate;
      if (birth == null) return null;
      final rows = await conn.execute(r'''SELECT id,url,identity_sources FROM m_player
        WHERE NOT coalesce(flg_delete,false) AND id_team=$1 AND date_birth=$2::timestamp''', parameters: [teamId, birth]);
      final candidates = rows.map((r) => r.toColumnMap()).where((p) => isYahoo ? ((p['identity_sources'] as Map?)?['mlb'] != null) : '${p['url']}'.contains('/mlb/player/')).toList();
      if (candidates.isEmpty) return null;
      final officialIds = isYahoo ? candidates.map((p) => '${(p['identity_sources'] as Map)['mlb']}').toSet().join(',') : externalId!;
      final response = await http.get(Uri.https('statsapi.mlb.com', '/api/v1/people', {'personIds': officialIds})).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('MLB profile HTTP ${response.statusCode}');
      }
      final people = List<Map<String, dynamic>>.from((jsonDecode(response.body) as Map)['people'] as List);
      final hits = <({int id, Map<String, dynamic> ja, Map<String, dynamic> en})>[];
      for (final p in candidates) {
        final ja = japanese ?? await profile('${p['url']}');
        final wanted = isYahoo ? '${(p['identity_sources'] as Map)['mlb']}' : externalId;
        final en = people.where((person) => '${person['id']}' == wanted).firstOrNull;
        if (en != null && same(ja, en)) {
          hits.add((id: p['id'] as int, ja: ja, en: en));
        }
      }
      if (hits.length != 1) {
        await review(conn, name, teamId, candidates.map((p) => p['id']).toList(), 'unresolved bilingual profiles');
        throw StateError('Bilingual player identity requires review: $name');
      }
      final hit = hits.single;
      final patterns = [
        name,
        '${hit.ja['name']}',
        for (final key in ['fullName', 'fullFMLName', 'firstLastName', 'lastFirstName', 'nameFirstLast'])
          if (hit.en[key] != null) '${hit.en[key]}'
      ];
      await conn.execute(r'''UPDATE m_player SET name_ja=$2,name_en=$3,
        name_patterns=name_patterns || $4::text[] WHERE id=$1''', parameters: [hit.id, hit.ja['name'], hit.en['fullName'], patterns]);
      return hit.id;
    } catch (error) {
      await review(conn, name, teamId, [], 'source profile verification failed: $error');
      // Do not turn a transient profile failure into a duplicate registration.
      rethrow;
    }
  }

  static Future<void> review(Connection conn, String name, int teamId, List<dynamic> ids, String reason) async {
    await conn.execute(r'''
      INSERT INTO t_player_identity_review(review_key,evidence)
      VALUES($1,$2::jsonb) ON CONFLICT(review_key) DO UPDATE
      SET evidence=excluded.evidence,updated_at=now()
    ''', parameters: [
      '$teamId:${playerIdentityKey(name)}',
      jsonEncode({'name': name, 'team_id': teamId, 'candidate_ids': ids, 'reason': reason})
    ]);
  }

  static Future<dynamic> localize(Connection conn, dynamic payload) async {
    final rows = await conn.execute("SELECT external_id,identity_sources,name_ja,name_patterns FROM m_player WHERE NOT coalesce(flg_delete,false) AND coalesce(name_ja,'')<>''");
    final ids = <String, String>{};
    final aliases = <String, String>{};
    final ambiguous = <String>{};
    for (final row in rows) {
      final p = row.toColumnMap();
      final name = '${p['name_ja']}';
      final sources = p['identity_sources'] as Map? ?? {};
      if (sources['mlb'] != null) ids['${sources['mlb']}'] = name;
      for (final alias in p['name_patterns'] as List? ?? []) {
        final key = playerIdentityKey('$alias');
        if (aliases.containsKey(key) && aliases[key] != name) {
          ambiguous.add(key);
        }
        aliases[key] = name;
      }
    }
    aliases.removeWhere((key, _) => ambiguous.contains(key));
    return localizePlayerPayload(payload, ids, aliases);
  }
}
