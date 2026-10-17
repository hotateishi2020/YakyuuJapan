import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import '../tools/Postgres.dart';
import 'StrengthUsage.dart';

Map<String, Map<String, dynamic>> parseLevelMetrics(String source, {required bool pitching}) {
  final result = <String, Map<String, dynamic>>{};
  for (final table in html.parse(source).querySelectorAll('table')) {
    List<String>? headers;
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.children.toList();
      final values = cells.map((c) => c.text.replaceAll(RegExp(r'\s+'), '')).toList();
      if (values.contains('選手') && values.contains(pitching ? '投球回' : '打席')) {
        headers = values;
        continue;
      }
      if (headers == null || cells.isEmpty || cells.first.localName != 'td' || values.length != headers.length) {
        continue;
      }
      final name = usageName(values.first.replaceFirst(RegExp(r'^[*＊+]'), ''));
      result[name] = {pitching ? 'outs' : 'pa': pitching ? inningsToOuts(values[headers.indexOf('投球回')]) : usageInt(values[headers.indexOf('打席')])};
    }
  }
  return result;
}

Map<String, Set<String>> parseFieldingRoles(String source) {
  final result = <String, Set<String>>{};
  for (final section in html.parse(source).querySelectorAll('.bis_table')) {
    final label = section.querySelector('h5')?.text.trim() ?? '';
    final role = label.contains('捕')
        ? '捕手'
        : label.contains('外')
            ? '外野手'
            : label.contains('投')
                ? '投手'
                : ['一塁手', '二塁手', '三塁手', '遊撃手'].contains(label)
                    ? '内野手'
                    : null;
    if (role == null) continue;
    for (final tr in section.querySelectorAll('tbody tr')) {
      final cells = tr.querySelectorAll('td');
      if (cells.length < 2 || usageInt(cells[1].text.trim()) <= 0) continue;
      final name = usageName(cells[0].text.replaceFirst(RegExp(r'^[*＊+]'), ''));
      result.putIfAbsent(name, () => {}).add(role);
    }
  }
  return result;
}

String? slotRole(String slot) => switch (slot) { 'P' => '投手', 'C' => '捕手', '1B' || '2B' || '3B' || 'SS' => '内野手', 'LF' || 'CF' || 'RF' || 'OF' => '外野手', 'DH' => '指名打者', _ => null };

Future<void> enrichSeasonEvidence(http.Client client, int year, String org, List<Map<String, dynamic>> teams, Map<String, String> codes) async {
  await StrengthUsage.ensure();
  for (final team in teams) {
    final metrics = <String, Map<String, Map<String, dynamic>>>{};
    final roles = <String, Set<String>>{};
    if (org == 'npb') {
      final code = codes['${team['name_team']}'];
      if (code == null) continue;
      for (final level in [1, 2]) {
        for (final pitching in [false, true]) {
          final url = 'https://npb.jp/bis/$year/stats/id${pitching ? 'p' : 'b'}${level}_$code.html';
          for (final e in parseLevelMetrics(await StrengthUsage.get(client, url), pitching: pitching).entries) {
            metrics.putIfAbsent(e.key, () => {}).putIfAbsent('$level', () => {}).addAll({...e.value, 'source': url});
          }
        }
        final url = 'https://npb.jp/bis/$year/stats/idf${level}_$code.html';
        for (final e in parseFieldingRoles(await StrengthUsage.get(client, url)).entries) {
          roles.putIfAbsent(e.key, () => {}).addAll(e.value);
        }
      }
    } else {
      final url = 'https://statsapi.mlb.com/api/v1/stats?stats=season&group=fielding&season=$year&teamId=${team['source_team_id']}&sportIds=1&playerPool=ALL&limit=5000';
      for (final group in usageMaps(usageMap(jsonDecode(await StrengthUsage.get(client, url)))['stats'])) {
        for (final p in usageMaps(group['splits'])) {
          if (usageInt(usageMap(p['stat'])['gamesPlayed'] ?? usageMap(p['stat'])['games']) == 0 && usageInt(usageMap(p['stat'])['gamesStarted']) == 0) {
            continue;
          }
          final role = slotRole('${usageMap(p['position'])['abbreviation']}');
          if (role != null) {
            roles.putIfAbsent('mlb:${usageMap(p['player'])['id']}', () => {}).add(role);
          }
        }
      }
    }
    for (final g in usageMaps(team['positions'])) {
      final role = slotRole('${g['slot']}');
      if (role == null) continue;
      for (final p in usageMaps(g['players'])) {
        if (usageInt(p['count']) > 0) {
          roles.putIfAbsent('${p['player_key']}', () => {}).add(role);
        }
      }
    }
    final updates = <Map<String, dynamic>>[];
    for (final p in usageMaps(team['roster'])) {
      final name = usageName('${p['name']}'), key = '${p['player_key']}';
      final actual = {...?roles[name], ...?roles[key]};
      final lower = usageMap(p['lower_level_usage']);
      for (final rec in lower.values) {
        for (final e in usageMap(usageMap(rec)['positions']).entries) {
          final role = slotRole(e.key);
          if (role != null && usageInt(e.value) > 0) actual.add(role);
        }
      }
      final payload = {'season_position_groups': actual.toList(), 'level_usage_metrics': metrics[name] ?? p['level_usage_metrics'] ?? {}};
      p.addAll(payload);
      updates.add({'player_key': key, 'payload': payload});
    }
    await Postgres.withConnection((c) => c.execute('''INSERT INTO t_strength_player_status(code_org,int_year,id_team,player_key,payload)
   SELECT \$1,\$2,\$3,p->>'player_key',p->'payload' FROM jsonb_array_elements(\$4::jsonb) p
   ON CONFLICT(code_org,int_year,id_team,player_key) DO UPDATE SET payload=t_strength_player_status.payload||EXCLUDED.payload,updated_at=NOW()''', parameters: [org, year, team['id_team'], jsonEncode(updates)]));
    await saveSeasonRoleMappings(year, org, team, updates);
    print('${team['name_team']} 出場位置・投球回・打席数を登録');
  }
}

/// Match NPB full names or unambiguous MLB team/birth dates to local player IDs.
Future<void> saveSeasonRoleMappings(int year, String org, Map<String, dynamic> team, List<Map<String, dynamic>> updates) async {
  await Postgres.withConnection((c) async {
    await c.execute('CREATE TABLE IF NOT EXISTS t_player_season_usage(int_year integer,id_player integer,groups jsonb NOT NULL,PRIMARY KEY(int_year,id_player))');
    final local = await c.execute("SELECT id,name_full,date_birth::date::text FROM m_player WHERE id_team=\$1 AND COALESCE(flg_delete,FALSE)=FALSE", parameters: [team['id_team']]);
    final roster = usageMaps(team['roster']), mapped = <Map<String, dynamic>>[];
    final byKey = {for (final u in updates) '${u['player_key']}': usageMap(u['payload'])};
    for (final p in roster) {
      final matches = local.where((m) => org == 'npb' ? usageName('${m[1]}') == usageName('${p['name']}') : p['date_birth'] != null && '${m[2]}' == '${p['date_birth']}').toList();
      if (matches.length != 1 || (org == 'mlb' && roster.where((r) => r['date_birth'] == p['date_birth']).length != 1)) {
        continue;
      }
      final groups = byKey['${p['player_key']}']?['season_position_groups'];
      if (groups == null) continue;
      mapped.add({'id': matches.single[0], 'groups': groups});
    }
    await c.execute('''INSERT INTO t_player_season_usage(int_year,id_player,groups)
   SELECT \$1,(p->>'id')::integer,p->'groups' FROM jsonb_array_elements(\$2::jsonb) p
   ON CONFLICT(int_year,id_player) DO UPDATE SET groups=EXCLUDED.groups''', parameters: [year, jsonEncode(mapped)]);
  });
}
