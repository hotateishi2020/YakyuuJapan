import 'package:postgres/postgres.dart';
import 'PlayLabel.dart';

Future<List<Map<String, dynamic>>> readGameReplay(
    Connection conn, int gameId) async {
  final result = await conn.execute(r'''
    SELECT d.id,d.int_inning,d.flg_bottom,d.int_batting_order,d.cnt_out,
      d.flg_runner_first,d.flg_runner_second,d.flg_runner_third,
      d.int_score_home,d.int_score_away,d.code_result,d.int_runs,d.cnt_homerun,
      d.code_direction_batting,d.code_state_score,d.flg_goodbye,
      d.code_position_from,d.code_position_to,
      b.name_full,p.name_full AS name_pitcher,
      en.name_full AS name_enter,ex.name_full AS name_exit,
      en.name_last AS name_enter_last,ex.name_last AS name_exit_last,
      en.name_full AS name_runner
    FROM t_game_details d
    LEFT JOIN m_player b ON b.id=d.id_batter
    LEFT JOIN m_player p ON p.id=d.id_pitcher
    LEFT JOIN m_player en ON en.id=d.id_player_enter
    LEFT JOIN m_player ex ON ex.id=d.id_player_exit
    WHERE d.id_game=$1 AND NOT COALESCE(d.flg_delete,false)
    ORDER BY d.int_inning,d.flg_bottom,d.id
  ''', parameters: [gameId]);
  return [
    for (final r in result)
      (() {
        final row = r.toColumnMap();
        return {...row, 'label': replayEventLabel(row)};
      })()
  ];
}
