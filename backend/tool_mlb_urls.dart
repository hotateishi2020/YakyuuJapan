import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final a = await conn.execute('''
      SELECT
        COUNT(DISTINCT p.id) AS players,
        COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(p.url,'')<>'') AS with_url,
        COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(p.url,'')='') AS no_url
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id=tsp.id_player
      WHERE tsp.id_league IN (3,4)
    ''').timeout(const Duration(seconds: 20));
    print(a.first.toColumnMap());
    final b = await conn.execute('''
      SELECT p.id, p.name_full, p.url, t.name_short,
        (SELECT string_agg(c.int_year::text || ':' || mt.name_short, ', ' ORDER BY c.int_year)
         FROM m_player_career c JOIN m_team mt ON mt.id=c.id_team
         WHERE c.id_player=p.id AND COALESCE(c.flg_delete,FALSE)=FALSE) AS careers
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id=tsp.id_player
      JOIN m_team t ON t.id=p.id_team
      WHERE tsp.id_league IN (3,4) AND COALESCE(p.url,'')<>''
      GROUP BY p.id, p.name_full, p.url, t.name_short
      ORDER BY p.id LIMIT 20
    ''').timeout(const Duration(seconds: 20));
    for (final r in b) print(r.toColumnMap());
    final c = await conn.execute('''
      SELECT c.int_year, t.name_short, COUNT(*) n
      FROM m_player_career c
      JOIN m_team t ON t.id=c.id_team AND t.id_league IN (3,4)
      WHERE COALESCE(c.flg_delete,FALSE)=FALSE
      GROUP BY c.int_year, t.name_short
      ORDER BY c.int_year DESC, n DESC LIMIT 30
    ''').timeout(const Duration(seconds: 20));
    print('career by year:');
    for (final r in c) print(r.toColumnMap());
  });
}
