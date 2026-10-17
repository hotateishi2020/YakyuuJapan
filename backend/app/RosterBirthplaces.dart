import 'dart:convert';
import '../tools/Postgres.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'StrengthUsage.dart';
import 'BirthPlaceRegistry.dart';
import 'package:html/parser.dart' as html;

Future<void> attachRosterBirthplaces(
    Connection conn, List<Map<String, dynamic>> teams) async {
  // 出身地は不変情報。再集計でも取得済みプロフィールを引き継ぐ。
  final saved = (await conn.execute(
      "SELECT jsonb_build_object('roster',payload->'roster') FROM t_team_strength ORDER BY int_year"));
  inheritRosterBirthplaces(teams, [
    for (final row in saved)
      row[0] is String
          ? usageMap(jsonDecode(row[0] as String))
          : usageMap(row[0])
  ]);
  final ids = teams.map((t) => t['id_team']).whereType<int>().toList();
  final people = (await conn.execute(
          'SELECT p.name_full,p.id_team,c.name AS birth_country,b.name AS birth_place FROM m_player p LEFT JOIN m_country c ON c.id=p.id_country LEFT JOIN m_place_birth b ON b.id=p.id_place_birth WHERE p.id_team=ANY(\$1::int[]) AND NOT COALESCE(p.flg_delete,false)',
          parameters: [ids]))
      .map((r) => r.toColumnMap())
      .toList();
  final index = <String, List<Map<String, dynamic>>>{};
  for (final p in people)
    index
        .putIfAbsent('${p['id_team']}:${usageName(p['name_full'])}', () => [])
        .add(p);
  for (final team in teams) {
    final roster = usageMaps(team['roster']);
    for (final p in roster) {
      final found = index['${team['id_team']}:${usageName(p['name'])}'] ?? [];
      if (found.length != 1) continue;
      for (final key in ['birth_country', 'birth_place'])
        if ('${p[key] ?? ''}'.trim().isEmpty) p[key] = found.single[key];
    }
    team['roster'] = roster;
  }
}

Future<int> refreshRosterBirthplaces(int year) async {
  final teams = (await Postgres.withConnection((conn) => conn.execute(
          'SELECT payload FROM t_team_strength WHERE int_year=\$1',
          parameters: [year])))
      .map((r) => r[0] is String
          ? Map<String, dynamic>.from(jsonDecode(r[0] as String))
          : usageMap(r[0]))
      .toList();
  await Postgres.withConnection((conn) => attachRosterBirthplaces(conn, teams));
  await fillNpbBirthplaces(teams);
  final mlb = [
    for (final t in teams)
      if (usageInt(t['id_league']) >= 3)
        ...(t['roster'] as List<Map<String, dynamic>>)
  ];
  final ids = mlb
      .map((p) => '${p['source_player_id']}')
      .where((s) => RegExp(r'^\d+$').hasMatch(s))
      .toSet()
      .toList();
  for (var i = 0; i < ids.length; i += 100) {
    final response = await http
        .get(Uri.parse(
            'https://statsapi.mlb.com/api/v1/people?personIds=${ids.skip(i).take(100).join(',')}'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200)
      throw StateError('MLB出身地 HTTP ${response.statusCode}');
    final byId = {
      for (final p in usageMaps(jsonDecode(response.body)['people']))
        '${p['id']}': p
    };
    for (final p in mlb) {
      final official = byId['${p['source_player_id']}'];
      if (official == null) continue;
      p['birth_source_url'] =
          'https://statsapi.mlb.com/api/v1/people/${p['source_player_id']}';
      p['birth_country'] = official['birthCountry'];
      p['birth_state'] = official['birthStateProvince'];
      p['birth_place'] =
          official['birthStateProvince'] ?? official['birthCity'];
    }
  }
  // Only the roster field is replaced in DB.
  for (final team in teams)
    await Postgres.withConnection((conn) => conn.execute(
        "UPDATE t_team_strength SET payload=jsonb_set(payload,'{roster}',\$1::jsonb),updated_at=now() WHERE int_year=\$2 AND id_team=\$3",
        parameters: [jsonEncode(team['roster']), year, team['id_team']]));
  return teams.length;
}

/// 管理CLIで未取得分だけ補完。画面表示時には外部取得しない。
Future<void> fillNpbBirthplaces(List<Map<String, dynamic>> teams) async {
  final targets = <String, List<Map<String, dynamic>>>{};
  for (final team in teams.where((t) => usageInt(t['id_league']) <= 2)) {
    final roster = usageMaps(team['roster']);
    team['roster'] = roster;
    for (final p in roster) {
      targets.putIfAbsent(usageName(p['name']), () => []).add(p);
    }
  }
  final rows = await Postgres.withConnection((conn) => conn.execute(
          "SELECT id,name_full,date_birth::text FROM m_player WHERE NOT COALESCE(flg_delete,false) AND id_team=ANY(\$1::int[])",
          parameters: [
            teams
                .where((t) => usageInt(t['id_league']) <= 2)
                .map((t) => t['id_team'])
                .toList()
          ]));
  final links = <String, String>{};
  final client = http.Client();
  Future<http.Response?> fetch(String url) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) return response;
        if (response.statusCode < 500 && response.statusCode != 429)
          return response;
      } catch (_) {
        if (attempt == 2) return null;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  try {
    for (final id in [1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 376]) {
      final response =
          await fetch('https://baseball.yahoo.co.jp/npb/teams/$id/players');
      if (response == null || response.statusCode != 200) {
        print('NPB出身地: 選手一覧 $id の取得失敗。登録済み情報を維持');
        continue;
      }
      for (final a in html
          .parse(utf8.decode(response.bodyBytes))
          .querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        final name =
            usageName(a.querySelector('.bb-playerList__name')?.text ?? '');
        if (!href.startsWith('/npb/player/') || !targets.containsKey(name))
          continue;
        if (targets[name]!.every((p) =>
            '${p['birth_place'] ?? ''}'.isNotEmpty ||
            ('${p['birth_country'] ?? ''}'.isNotEmpty &&
                '${p['birth_source_url'] ?? ''}'.isNotEmpty))) continue;
        links['https://baseball.yahoo.co.jp$href'] = name;
      }
    }
    final entries = links.entries.toList();
    var count = 0;
    final registrations = <int, String>{};
    final skipped = <String, int>{};
    for (var i = 0; i < entries.length; i += 2) {
      final batch = await Future.wait(entries.skip(i).take(2).map((e) async {
        final response = await fetch(e.key);
        if (response == null || response.statusCode != 200) {
          final reason = 'HTTP ${response?.statusCode ?? "取得失敗"}';
          skipped.update(reason, (n) => n + 1, ifAbsent: () => 1);
          return null;
        }
        final doc = html.parse(utf8.decode(response.bodyBytes));
        final raw = BirthPlaceRegistry.extractFromProfile(doc);
        if (raw == null) {
          skipped.update('出身地の記載なし', (n) => n + 1, ifAbsent: () => 1);
          return null;
        }
        return (
          name: e.value,
          raw: raw,
          source: e.key,
          birth: BirthPlaceRegistry.extractBirthDate(doc)
        );
      }));
      for (final result in batch.nonNulls) {
        final parsed = BirthPlaceRegistry.parse(result.raw);
        for (final p in targets[result.name]!) {
          final birth = DateTime.tryParse('${p['date_birth']}');
          if (birth != null && result.birth != null && birth != result.birth)
            continue;
          p['birth_country'] = parsed.countryName;
          p['birth_place'] = parsed.placeName;
          p['birth_source_url'] = result.source;
          count++;
        }
        final matched = rows
            .where((r) =>
                usageName('${r[1]}') == result.name &&
                (result.birth == null ||
                    r[2] == null ||
                    DateTime.tryParse('${r[2]}') == result.birth))
            .toList();
        if (matched.length == 1)
          registrations[matched.single[0] as int] = result.raw;
      }
      if (i % 80 == 0) print('NPB出身地: $count 人補完 / ${entries.length} プロフィール');
    }
    // 国・県を一度ずつ解決し、一括更新する（選手ごとの往復を避ける）。
    final countries = <String, int>{};
    final places = <String, int>{};
    final updates = <Map<String, dynamic>>[];
    for (final entry in registrations.entries) {
      final value = BirthPlaceRegistry.parse(entry.value);
      if (value.countryName == null) continue;
      final country = countries[value.countryName!] ??=
          await Postgres.withConnection((conn) =>
              BirthPlaceRegistry.ensureCountry(conn, value.countryName!));
      int? place;
      if (value.placeName != null) {
        final key = '$country:${value.placeName}';
        place = places[key] ??= await Postgres.withConnection((conn) =>
            BirthPlaceRegistry.ensurePlace(conn, value.placeName!, country));
      }
      updates.add({'id': entry.key, 'country': country, 'place': place});
    }
    await Postgres.withConnection((conn) => conn.execute(
        "UPDATE m_player p SET id_country=COALESCE(NULLIF(p.id_country,0),v.country), id_place_birth=COALESCE(NULLIF(p.id_place_birth,0),v.place),updat=now() FROM jsonb_to_recordset(\$1::jsonb) AS v(id int,country int,place int) WHERE p.id=v.id",
        parameters: [jsonEncode(updates)]));
    print('NPB出身地: $count 人補完、未取得: $skipped');
  } finally {
    client.close();
  }
}

void inheritRosterBirthplaces(
    List<Map<String, dynamic>> teams, List<Map<String, dynamic>> savedTeams) {
  final previous = <String, Map<String, dynamic>>{};
  for (final team in savedTeams) {
    for (final p in usageMaps(team['roster'])) {
      if (('${p['birth_place'] ?? ''}'.isNotEmpty ||
              '${p['birth_country'] ?? ''}'.isNotEmpty) &&
          '${p['player_key'] ?? ''}'.isNotEmpty)
        previous['${p['player_key']}'] = p;
    }
  }
  for (final team in teams) {
    final roster = usageMaps(team['roster']);
    for (final p in roster) {
      final old = previous['${p['player_key']}'];
      if (old == null) continue;
      for (final key in [
        'birth_country',
        'birth_place',
        'birth_state',
        'birth_source_url'
      ]) {
        if ('${p[key] ?? ''}'.trim().isEmpty && old[key] != null)
          p[key] = old[key];
      }
    }
    team['roster'] = roster;
  }
}
