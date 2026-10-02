import '../../tools/DBModel.dart';

class t_game_summary extends DBModel {
  String tableName = 't_game_summary';
  int id_game = 0;
  int id_player = 0;
  int int_batting = 0;
  int int_homerun = 0;
  String txt_homerun_total = '';
  int int_hit3 = 0;
  int int_hit2 = 0;
  int int_hit1 = 0;
  int int_fourball = 0;
  int int_dead_batting = 0;
  int int_sacrifice = 0;
  int int_rbi = 0;
  int int_steal_base = 0;
  int int_error = 0;
  double double_inning_pitch = 0.0;
  int int_pitch = 0;
  int int_hit = 0;
  int int_strike_out = 0;
  int int_four = 0;
  int int_dead_pitching = 0;
  int int_balk = 0;
  int int_runs = 0;
  int int_runs_earned = 0;
  String code_result_pitcher = '';
  String txt_scores_home = '';
  String txt_scores_away = '';
  int int_runs_home = 0;
  int int_runs_away = 0;
  int int_error_home = 0;
  int int_error_away = 0;
  int int_hit_home = 0;
  int int_hit_away = 0;

  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "id_game": id_game,
        "id_player": id_player,
        "int_batting": int_batting,
        "int_homerun": int_homerun,
        "txt_homerun_total": txt_homerun_total,
        "int_hit3": int_hit3,
        "int_hit2": int_hit2,
        "int_hit1": int_hit1,
        "int_fourball": int_fourball,
        "int_dead_batting": int_dead_batting,
        "int_sacrifice": int_sacrifice,
        "int_rbi": int_rbi,
        "int_steal_base": int_steal_base,
        "int_error": int_error,
        "double_inning_pitch": double_inning_pitch,
        "int_pitch": int_pitch,
        "int_hit": int_hit,
        "int_strike_out": int_strike_out,
        "int_four": int_four,
        "int_dead_pitching": int_dead_pitching,
        "int_balk": int_balk,
        "int_runs": int_runs,
        "int_runs_earned": int_runs_earned,
        "code_result_pitcher": code_result_pitcher,
        "txt_scores_home": txt_scores_home,
        "txt_scores_away": txt_scores_away,
        "int_runs_home": int_runs_home,
        "int_runs_away": int_runs_away,
        "int_error_home": int_error_home,
        "int_error_away": int_error_away,
        "int_hit_home": int_hit_home,
        "int_hit_away": int_hit_away,
      });
  }
}
