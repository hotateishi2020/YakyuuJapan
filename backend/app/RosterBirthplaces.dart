import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'StrengthUsage.dart';

Future<void> attachRosterBirthplaces(
    Connection conn, List<Map<String, dynamic>> teams) async {
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

Future<int> refreshRosterBirthplaces(Connection conn, int year) async {
  final teams = (await conn.execute(
          'SELECT payload FROM t_team_strength WHERE int_year=\$1',
          parameters: [year]))
      .map((r) => r[0] is String
          ? Map<String, dynamic>.from(jsonDecode(r[0] as String))
          : usageMap(r[0]))
      .toList();
  await attachRosterBirthplaces(conn, teams);
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
      p['birth_country'] = official['birthCountry'];
      p['birth_state'] = official['birthStateProvince'];
      p['birth_place'] =
          official['birthStateProvince'] ?? official['birthCity'];
    }
  }
  // Only the roster field is replaced in DB.
  for (final team in teams)
    await conn.execute(
        "UPDATE t_team_strength SET payload=jsonb_set(payload,'{roster}',\$1::jsonb),updated_at=now() WHERE int_year=\$2 AND id_team=\$3",
        parameters: [jsonEncode(team['roster']), year, team['id_team']]);
  return teams.length;
}
