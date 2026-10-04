import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''
      SELECT code_game, COUNT(*) AS n
      FROM t_game
      WHERE EXTRACT(YEAR FROM datetime_start) = EXTRACT(YEAR FROM CURRENT_DATE)
        AND COALESCE(flg_delete,FALSE)=FALSE
        AND (
          COALESCE(code_game,'') IN ('WC','DS','LCS','WS','ALWC36','ALWC45','NLWC36','NLWC45','ALDS1','ALDS2','NLDS1','NLDS2','ALCS','NLCS','CS1','CSF','JS')
          OR id_team_home IN (SELECT id FROM m_team WHERE id_league IN (3,4))
        )
      GROUP BY code_game
      ORDER BY n DESC
    ''').timeout(const Duration(seconds: 20));
    for (final r in rows) print(r.toColumnMap());

    final sample = await conn.execute('''
      SELECT g.id, g.code_game, g.state, g.score_home, g.score_away,
             th.name_short AS home, ta.name_short AS away, g.datetime_start::date AS d
      FROM t_game g
      JOIN m_team th ON th.id=g.id_team_home
      JOIN m_team ta ON ta.id=g.id_team_away
      WHERE th.id_league IN (3,4) AND ta.id_league IN (3,4)
        AND g.datetime_start >= DATE '2026-09-28'
        AND COALESCE(g.flg_delete,FALSE)=FALSE
      ORDER BY g.datetime_start
      LIMIT 40
    ''').timeout(const Duration(seconds: 20));
    print('--- recent MLB ---');
    for (final r in sample) print(r.toColumnMap());
  });
}
