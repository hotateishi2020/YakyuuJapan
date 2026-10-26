import 'dart:convert';
import 'package:html/dom.dart';
import 'package:postgres/postgres.dart';

List<Map<String,dynamic>> parseGameBench(Document doc, int home, int away) {
  final root = doc.querySelector('#benc_mem');
  if (root == null) return [];
  final players = <String,Map<String,dynamic>>{};
  for (final group in root.querySelectorAll('.bb-modCommon03')) {
    final position = group.querySelector('h3')?.text.trim() ?? '';
    final sides = group.querySelectorAll('.bb-splits__item');
    if (sides.length != 2) continue;
    for (var side = 0; side < 2; side++) {
      final team = side == 0 ? home : away;
      for (final row in sides[side].querySelectorAll('tbody tr')) {
        final link = row.querySelector('a[href*="/player/"]');
        final name = link?.text.trim() ?? '';
        if (name.isEmpty || team <= 0) continue;
        final cells = row.querySelectorAll('td');
        players['$team:${name.replaceAll(RegExp(r'[\s　]'), '')}'] = {
          'id_team':team, 'name':name, 'position':position,
          'pitcher':position == '投手',
          'hands':cells.length > 1 ? cells[1].text.trim() : '',
          'source_player_url':link!.attributes['href'],
        };
      }
    }
  }
  return players.values.toList();
}

class GameBench {
  static bool _ready = false;
  static Future<void> ensure(Connection conn) async {
    if (_ready) return;
    await conn.execute('''CREATE TABLE IF NOT EXISTS t_game_bench (
      id_game INTEGER PRIMARY KEY, players JSONB NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW())''');
    _ready = true;
  }
  static Future<void> save(Connection conn, Document doc, int game, int home, int away) async {
    if (doc.querySelector('#benc_mem') == null) return;
    final players = parseGameBench(doc, home, away);
    if (players.isEmpty) return; // A partial page must not erase a previously verified roster.
    await ensure(conn);
    await conn.execute(r'''INSERT INTO t_game_bench(id_game,players) VALUES($1,$2::jsonb)
      ON CONFLICT(id_game) DO UPDATE SET players=EXCLUDED.players,updated_at=NOW()''',
      parameters:[game,jsonEncode(players)]);
  }
  static Future<void> attach(Connection conn, List<Map<String,dynamic>> games) async {
    if (games.isEmpty) return;
    await ensure(conn);
    final ids = games.map((g)=>int.tryParse('${g['id_game']}')).whereType<int>().toSet().toList();
    if (ids.isEmpty) return;
    final rows = await conn.execute(r'SELECT id_game,players FROM t_game_bench WHERE id_game=ANY($1::int[])',parameters:[ids]);
    final byId = {for (final row in rows) '${row[0]}': row[1] is String ? jsonDecode(row[1] as String) : row[1]};
    for (final game in games) {
      game['bench_players'] = byId['${game['id_game']}'] ?? [];
    }
  }
}
