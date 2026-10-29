import 'dart:convert';
import 'dart:io';
import 'app/PlayerDetailSnapshot.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  await Postgres.withConnection((c) async {
    final people = await c.execute(args.contains('--missing') ? '''
      SELECT DISTINCT ON(t.id_league) p.id,t.id_league FROM m_player p JOIN m_team t ON t.id=p.id_team
      LEFT JOIN t_player_detail_snapshot d ON d.id_player=p.id AND d.int_year=2026
      WHERE t.id_league IN(1,2,3,4) AND d.id_player IS NULL AND NOT COALESCE(p.flg_delete,false)
      ORDER BY t.id_league,p.id DESC
    ''' : 'SELECT DISTINCT ON(id_league) id_player,id_league FROM t_player_detail_snapshot WHERE int_year=2026 ORDER BY id_league,updated_at DESC');
    for (final p in people) {
      final stopwatch = Stopwatch()..start();
      final data = await PlayerDetailSnapshot.read(c, year: 2026,
          leagues: (p[1] as int) <= 2 ? [1,2] : [3,4], identity: {'id_player': p[0]},
          withCurrentStats: !args.contains('--profile-first'));
      print(jsonEncode({'id': p[0], 'league': p[1], 'ms': stopwatch.elapsedMilliseconds,
        'found': data['found'], 'pending': data['pending'],
        'season_stats': (data['season_stats'] as List? ?? []).length}));
    }
  });
  exit(0);
}
