import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'PlayerDetail.dart';
import 'StrengthUsage.dart';

const mlbPositionNames = {'P': '投手', 'C': '捕手', '1B': '一塁手', '2B': '二塁手', '3B': '三塁手', 'SS': '遊撃手', 'LF': '左翼手', 'CF': '中堅手', 'RF': '右翼手', 'OF': '外野手', 'DH': '指名打者'};
Map<String, Map<String, dynamic>> seasonPositionLeaders(List<Map<String, dynamic>> splits) {
  final grouped = <String, Map<String, Map<String, dynamic>>>{};
  for (final row in splits) {
    final id = '${usageMap(row['player'])['id'] ?? ''}', position = '${usageMap(row['position'])['abbreviation'] ?? ''}';
    final games = usageInt(usageMap(row['stat'])['games']);
    final appearances = games > 0 ? games : usageInt(usageMap(row['stat'])['gamesPlayed']);
    if (id.isEmpty || !mlbPositionNames.containsKey(position) || appearances <= 0) {
      continue;
    }
    final byPosition = grouped.putIfAbsent(id, () => {});
    final old = byPosition[position];
    if (old == null || appearances > usageInt(old['games'])) {
      byPosition[position] = {'position': position, 'games': appearances};
    }
  }
  return {for (final entry in grouped.entries) entry.key: (entry.value.values.toList()..sort((a, b) => usageInt(b['games']).compareTo(usageInt(a['games'])))).first};
}

Future<Map<String, dynamic>> refreshMlbSeasonPositions(Connection conn, int year) async {
  print('MLB守備記録を取得');
  final url = 'https://statsapi.mlb.com/api/v1/stats?stats=season&group=fielding&season=$year&sportIds=1&playerPool=ALL&limit=10000';
  final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    throw StateError('MLB守備記録 HTTP ${response.statusCode}');
  }
  final data = usageMap(jsonDecode(response.body));
  final positions = seasonPositionLeaders([for (final block in usageMaps(data['stats'])) ...usageMaps(block['splits'])]);
  print('MLB守備記録 ${positions.length} 人、DB照合');
  final people = (await conn.execute('SELECT p.id,p.id_team,p.name_full,p.url,p.date_birth::text,p.txt_position FROM m_player p JOIN m_team t ON t.id=p.id_team WHERE t.id_league IN (3,4) AND NOT COALESCE(p.flg_delete,false)')).map((r) => r.toColumnMap()).toList();
  await attachOfficialIdentity(conn, year, people);
  final updates = <Map<String, dynamic>>[];
  for (final p in people) {
    if ('${p['txt_position'] ?? ''}'.trim().isNotEmpty && p['txt_position'] != '不明') {
      continue;
    }
    final position = positions[officialPlayerId(p)];
    if (position == null) continue;
    updates.add({'id': p['id'], 'position': mlbPositionNames[position['position']]});
  }
  await conn.execute("UPDATE m_player p SET txt_position=u.position FROM jsonb_to_recordset(\$1::jsonb) AS u(id int,position text) WHERE p.id=u.id AND (COALESCE(p.txt_position,'')='' OR p.txt_position='不明')", parameters: [jsonEncode(updates)]);

  return {'year': year, 'updated': updates.length, 'official_players': positions.length, 'source': url};
}
