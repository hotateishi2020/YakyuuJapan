import 'tools/Postgres.dart';

Future<void> main() async {
  print('start');
  await Postgres.withConnection((conn) async {
    print('connected');
    final teams = await conn.execute('''
      SELECT id, id_league, name_short, name_shortest
      FROM m_team WHERE id_league IN (3,4) ORDER BY id
    ''').timeout(const Duration(seconds: 15));
    for (final r in teams) {
      print(r.toColumnMap());
    }
    final c = await conn.execute('''
      SELECT COUNT(*) n FROM m_player_career c
      JOIN m_team t ON t.id=c.id_team AND t.id_league IN (3,4)
      WHERE COALESCE(c.flg_delete,FALSE)=FALSE
    ''').timeout(const Duration(seconds: 15));
    print('career ${c.first.toColumnMap()}');
    final p = await conn.execute('''
      SELECT COUNT(DISTINCT p.id) players_url,
             COUNT(DISTINCT p.id) FILTER (WHERE EXISTS (
               SELECT 1 FROM m_player_career c JOIN m_team t ON t.id=c.id_team AND t.id_league IN (3,4)
               WHERE c.id_player=p.id AND c.int_year < EXTRACT(YEAR FROM CURRENT_DATE)::int
             )) with_prior
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id=tsp.id_player
      WHERE tsp.id_league IN (3,4) AND COALESCE(p.url,'')<>''
    ''').timeout(const Duration(seconds: 30));
    print('stats players ${p.first.toColumnMap()}');
  });
  print('done');
}
