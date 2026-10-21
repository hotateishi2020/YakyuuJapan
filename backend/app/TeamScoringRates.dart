import 'package:postgres/postgres.dart';

/// Offensive outs come from the opponents' pitching lines, including partial
/// innings and walk-offs. Never substitute RBI or assume every game lasts 9 innings.
Future<Map<String, String>> readTeamScoringRates(Connection conn, int year, {Map<String, int> expectedGames = const {}}) async {
  final result = await conn.execute('''
    WITH games AS (
      SELECT * FROM t_game WHERE datetime_start >= make_date(\$1,1,1)
        AND datetime_start < make_date(\$1+1,1,1)
        AND (code_game IN ('NM','EX') OR code_game IS NULL)
        AND (state LIKE '%終了%' OR state LIKE '%コールド%')
        AND NOT COALESCE(flg_delete,false)
    ), pitching AS (
      SELECT g.id, COALESCE(side.team,p.id_team) AS team,
        SUM(FLOOR(s.double_inning_pitch)*3 + ROUND((s.double_inning_pitch-FLOOR(s.double_inning_pitch))*10)) AS outs
      FROM games g JOIN t_game_summary s ON s.id_game=g.id
      JOIN m_player p ON p.id=s.id_player
      LEFT JOIN LATERAL (
        SELECT CASE WHEN d.flg_bottom THEN g.id_team_away ELSE g.id_team_home END AS team
        FROM t_game_details d WHERE d.id_game=g.id AND d.id_pitcher=s.id_player
          AND NOT COALESCE(d.flg_delete,false) LIMIT 1
      ) side ON true
      WHERE s.double_inning_pitch>0 AND NOT COALESCE(s.flg_delete,false)
      GROUP BY g.id,COALESCE(side.team,p.id_team)
    ), batting AS (
      SELECT g.id,g.id_team_home AS team,g.score_home AS runs,p.outs
      FROM games g LEFT JOIN pitching p ON p.id=g.id AND p.team=g.id_team_away
      UNION ALL
      SELECT g.id,g.id_team_away,g.score_away,p.outs
      FROM games g LEFT JOIN pitching p ON p.id=g.id AND p.team=g.id_team_home
    )
    SELECT team,SUM(runs)*27.0/NULLIF(SUM(outs),0) AS rate,COUNT(*) AS games
    FROM batting GROUP BY team HAVING COUNT(outs)=COUNT(*) AND MIN(outs)>0
  ''', parameters: [year]);
  return {for (final r in result) if (!expectedGames.containsKey('${r[0]}') || expectedGames['${r[0]}'] == int.parse('${r[2]}')) '${r[0]}': (num.parse('${r[1]}')).toStringAsFixed(2)};
}
