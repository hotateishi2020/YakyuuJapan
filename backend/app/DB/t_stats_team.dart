import '../../tools/DBModel.dart';

class t_stats_team extends DBModel {
  String tableName = 't_stats_team';
  int year = 0;
  int id_team = 0;
  int int_rank = 0;
  int int_game = 0;
  int int_win = 0;
  int int_lose = 0;
  int int_draw = 0;
  String game_behind = '';
  double num_avg_batting = 0;
  int int_homerun = 0;
  int int_rbi = 0;
  int int_sh = 0;
  double num_era_total = 0;
  double num_era_starter = 0;
  double num_era_relief = 0;
  double num_avg_fielding = 0;

  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "year": year,
        "id_team": id_team,
        "int_rank": int_rank,
        "int_game": int_game,
        "int_win": int_win,
        "int_lose": int_lose,
        "int_draw": int_draw,
        "game_behind": game_behind,
        "num_avg_batting": num_avg_batting,
        "int_homerun": int_homerun,
        "int_rbi": int_rbi,
        "int_sh": int_sh,
        "num_era_total": num_era_total,
        "num_era_starter": num_era_starter,
        "num_era_relief": num_era_relief,
        "num_avg_fielding": num_avg_fielding,
      });
  }
}
