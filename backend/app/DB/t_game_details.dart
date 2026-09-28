import '../../tools/DBModel.dart';

class t_game_details extends DBModel {
  String tableName = 't_game_batting';
  int id_game = 0;
  int int_inning = 0;
  bool flg_bottom = false;
  int int_score_home = 0;
  int int_score_away = 0;
  int id_pitcher = 0;
  int id_batter = 0;
  int int_batting_order = 0;
  int cnt_out = 0;
  bool flg_runner_first = false;
  bool flg_runner_second = false;
  bool flg_runner_third = false;
  String code_category = '';
  String code_result = '';
  double double_contribution = 0;
  int int_runs = 0;
  int cnt_homerun = 0;
  int id_player_enter = 0;
  int id_player_exit = 0;
  String code_position_from = '';
  String code_position_to = '';

  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "id_game": id_game,
        "int_inning": int_inning,
        "flg_bottom": flg_bottom,
        "int_score_home": int_score_home,
        "int_score_away": int_score_away,
        "id_pitcher": id_pitcher,
        "id_batter": id_batter,
        "int_batting_order": int_batting_order,
        "cnt_out": cnt_out,
        "flg_runner_first": flg_runner_first,
        "flg_runner_second": flg_runner_second,
        "flg_runner_third": flg_runner_third,
        "code_category": code_category,
        "code_result": code_result,
        "double_contribution": double_contribution,
        "int_runs": int_runs,
        "cnt_homerun": cnt_homerun,
        "id_player_enter": id_player_enter,
        "id_player_exit": id_player_exit,
        "code_position_from": code_position_from,
        "code_position_to": code_position_to,
      });
  }
}
