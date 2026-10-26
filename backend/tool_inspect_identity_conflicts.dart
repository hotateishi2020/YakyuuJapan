import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((c) async {
    final rows = await c.execute('''SELECT p.id,p.name_full,p.source_key,p.external_id,p.url,c.int_year,c.id_team,c.int_appearance,c.int_batting,c.int_homerun,c.int_pitching,c.double_inning
 FROM m_player p LEFT JOIN m_player_career c ON c.id_player=p.id AND c.int_year=2026 AND NOT coalesce(c.flg_delete,false)
 WHERE p.id IN(5619,5129,5969,26961) ORDER BY p.id,c.id''');
    for (final r in rows) {
      print(jsonEncode(r.toColumnMap()));
    }
    final stats = await c.execute('''SELECT t.id_player,s.title,s.flg_pitcher,t.stats,t.cnt_play FROM t_stats_player_latest t JOIN m_stats s ON s.id=t.id_stats WHERE t.id_player IN(5619,5129,5969,26961) ORDER BY t.id_player,t.id_stats''');
    for (final r in stats) {
      print(jsonEncode(r.toColumnMap()));
    }
    final games = await c.execute('SELECT id_player,count(*) games,count(*) FILTER(WHERE coalesce(int_batting,0)>0) batting_games,count(*) FILTER(WHERE coalesce(int_pitch,0)>0 OR coalesce(double_inning_pitch,0)>0) pitching_games FROM t_game_summary WHERE id_player IN(5619,5969) GROUP BY id_player');
    for (final r in games) {
      print(jsonEncode(r.toColumnMap()));
    }
    final historical = await c.execute('SELECT t.id_player,s.flg_pitcher,count(*) FROM t_stats_player t JOIN m_stats s ON s.id=t.id_stats WHERE t.id_player IN(5619,5969) GROUP BY 1,2');
    for (final r in historical) {
      print(jsonEncode(r.toColumnMap()));
    }
  });
  exit(0);
}
