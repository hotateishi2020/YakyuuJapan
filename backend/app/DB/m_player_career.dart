import '../../tools/DBModel.dart';

class m_player_career extends DBModel {
  @override
  String get tableName => 'm_player_career';

  int id_player = 0;
  int int_year = 0;
  int id_team = 0;
  int int_games = 0;
  int int_appearance = 0;
  int int_batting = 0;
  int int_runs = 0;
  int int_rbi = 0;
  int int_hit1 = 0;
  int int_hit2 = 0;
  int int_hit3 = 0;
  int int_homerun = 0;
  int int_total_bases = 0;
  int int_steal_base = 0;
  int int_steal_caught = 0;
  int int_sacrifice = 0;
  int int_four_batting = 0;
  int int_dead_batting = 0;
  int int_strike_out_batting = 0;
  int int_double_play = 0;
  double double_average_batting = 0;
  double double_average_slugging = 0;
  double double_average_onbase = 0;
  int int_pitching = 0;
  int int_win = 0;
  int int_lose = 0;
  int int_save = 0;
  int int_hold = 0;
  int int_hold_point = 0;
  int int_complete_game = 0;
  int int_shutout = 0;
  int int_without_walks = 0;
  double double_average_win = 0;
  int int_batter = 0;
  double double_inning = 0;
  int int_hit_pitcher = 0;
  int int_homerun_pitcher = 0;
  int int_four_pitcher = 0;
  int int_dead_pitcher = 0;
  int int_strike_out_pitcher = 0;
  int int_wild_pitch = 0;
  int int_balk = 0;
  int int_runs_allowed = 0;
  int int_earned_runds = 0;
  double double_average_earned_runs = 0;

  @override
  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "id_player": id_player,
        "int_year": int_year,
        "id_team": id_team,
        "int_games": int_games,
        "int_appearance": int_appearance,
        "int_batting": int_batting,
        "int_runs": int_runs,
        "int_rbi": int_rbi,
        "int_hit1": int_hit1,
        "int_hit2": int_hit2,
        "int_hit3": int_hit3,
        "int_homerun": int_homerun,
        "int_total_bases": int_total_bases,
        "int_steal_base": int_steal_base,
        "int_steal_caught": int_steal_caught,
        "int_sacrifice": int_sacrifice,
        "int_four_batting": int_four_batting,
        "int_dead_batting": int_dead_batting,
        "int_strike_out_batting": int_strike_out_batting,
        "int_double_play": int_double_play,
        "double_average_batting": double_average_batting,
        "double_average_slugging": double_average_slugging,
        "double_average_onbase": double_average_onbase,
        "int_pitching": int_pitching,
        "int_win": int_win,
        "int_lose": int_lose,
        "int_save": int_save,
        "int_hold": int_hold,
        "int_hold_point": int_hold_point,
        "int_complete_game": int_complete_game,
        "int_shutout": int_shutout,
        "int_without_walks": int_without_walks,
        "double_average_win": double_average_win,
        "int_batter": int_batter,
        "double_inning": double_inning,
        "int_hit_pitcher": int_hit_pitcher,
        "int_homerun_pitcher": int_homerun_pitcher,
        "int_four_pitcher": int_four_pitcher,
        "int_dead_pitcher": int_dead_pitcher,
        "int_strike_out_pitcher": int_strike_out_pitcher,
        "int_wild_pitch": int_wild_pitch,
        "int_balk": int_balk,
        "int_runs_allowed": int_runs_allowed,
        "int_earned_runds": int_earned_runds,
        "double_average_earned_runs": double_average_earned_runs,
      });
  }
}
