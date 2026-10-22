import 'package:postgres/postgres.dart';
import 'ClubData.dart';
import 'PlayerDetail.dart' show attachOfficialIdentity, officialPlayerId;
import 'StrengthUsage.dart';

String countryFlag(String code) => RegExp(r'^[A-Za-z]{2}$').hasMatch(code) ? String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => c + 127397)) : '';

/// Preserve birthplace; the most recent *different* represented country wins.
Map<String, dynamic> playerCountryDisplay(String birthEmoji, Iterable<Map<String, dynamic>> appearances, {required int year}) {
  final eligible = appearances.where((r) => const ['WBC', 'Premier12'].contains(r['tournament']) && usageInt(r['year']) <= year && countryFlag('${r['country_code']}').isNotEmpty && countryFlag('${r['country_code']}') != birthEmoji).toList()..sort((a, b) => usageInt(b['year']).compareTo(usageInt(a['year'])));
  final representative = eligible.firstOrNull;
  return {
    'flg_wbc': appearances.any((r) => r['tournament'] == 'WBC' && usageInt(r['year']) <= year),
    'emoji_country': birthEmoji,
    'emoji_display_country': representative == null ? birthEmoji : countryFlag('${representative['country_code']}'),
    if (representative != null) ...{
      'country_flag_basis': '${representative['tournament']} ${representative['year']}',
      'country_flag_source': representative['source'],
    } else
      'country_flag_basis': '出身国',
  };
}

Future<void> attachPlayerCountries(Connection conn, int year, List<Map<String, dynamic>> rows) async {
  if (rows.isEmpty) return;
  final ids = rows.map((r) => usageInt(r['id_player'] ?? r['id'])).where((id) => id > 0).toSet().toList();
  if (ids.isEmpty) return;
  final people = (await conn.execute('''SELECT p.id,p.id_team,p.name_full,p.url,
    p.date_birth::date::text,COALESCE(c.emoji,'') AS emoji_country,
    EXISTS(SELECT 1 FROM m_player_career career JOIN m_team club ON club.id=career.id_team
      WHERE career.id_player=p.id AND club.id_league IN (1,2)
        AND NOT COALESCE(career.flg_delete,false)) AS flg_npb_experience
    FROM m_player p JOIN m_team t ON t.id=p.id_team
    LEFT JOIN m_country c ON c.id=p.id_country
    WHERE t.id_league IN (3,4) AND p.id=ANY(\$1::int[])''', parameters: [ids])).map((r) => r.toColumnMap()).toList();
  if (people.isEmpty) return;
  await attachOfficialIdentity(conn, year, people);
  // Duplicate Yahoo records may share a birthday. Resolve against a unique
  // official roster identity within the club, rather than a unique DB row.
  final roster = (await conn.execute("SELECT t.id_team,p->>'source_player_id' AS source_id,p->>'date_birth' AS birth FROM t_team_strength t CROSS JOIN LATERAL jsonb_array_elements(COALESCE(t.payload->'roster','[]'::jsonb)) p WHERE t.int_year=\$1 AND t.code_org='mlb'", parameters: [year])).map((r) => r.toColumnMap()).toList();
  final officialPeople = usageMaps(readClubFile('mlb_country_profiles.json')['players']);
  final profiles = {for (final p in officialPeople) '${p['source_player_id']}': p};
  final aliases = usageMaps(readClubFile('mlb_country_aliases.json')['players']);
  for (final p in people) {
    final birth = '${p['date_birth'] ?? ''}'.split(' ').first;
    if (officialPlayerId(p) == null && birth.isNotEmpty) {
      final matches = roster.where((r) => r['id_team'] == p['id_team'] && r['birth'] == birth).map((r) => '${r['source_id']}').where((id) => id != 'null').toSet();
      if (matches.length == 1) p['official_source_player_id'] = matches.single;
    }
    if (officialPlayerId(p) == null) {
      final candidates = aliases.where((a) => (a['names'] as List).contains(p['name_full']) && roster.any((r) => r['id_team'] == p['id_team'] && r['source_id'] == a['source_player_id'])).toList();
      if (candidates.length == 1) {
        p['official_source_player_id'] = candidates.single['source_player_id'];
      }
    }
    if ('${p['emoji_country'] ?? ''}'.isEmpty) {
      p['emoji_country'] = profiles[officialPlayerId(p)]?['emoji_country'] ?? '';
    }
  }
  final bySource = <String, List<Map<String, dynamic>>>{};
  for (final file in ['wbc_appearances.json', 'premier12_appearances.json']) {
    for (final r in usageMaps(readClubFile(file)['appearances'])) {
      bySource.putIfAbsent('${r['source_player_id']}', () => []).add(r);
    }
  }
  final npbIds = usageMaps(readClubFile('npb_mlb_player_ids.json')['players']).where((p) => '${p['npb_id'] ?? ''}'.isNotEmpty).map((p) => '${p['mlb_id']}').toSet();
  final byId = {
    for (final p in people)
      '${p['id']}': <String, dynamic>{
        'flg_npb_experience': p['flg_npb_experience'] == true || npbIds.contains(officialPlayerId(p)),
        ...playerCountryDisplay('${p['emoji_country']}', bySource[officialPlayerId(p)] ?? [], year: year),
      }
  };
  for (final row in rows) {
    final country = byId['${row['id_player'] ?? row['id']}'];
    if (country != null) row.addAll(country);
  }
}
