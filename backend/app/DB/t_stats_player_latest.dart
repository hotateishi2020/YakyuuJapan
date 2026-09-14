import '../../tools/DBModel.dart';

class t_stats_player_latest extends DBModel {
  @override
  String get tableName => 't_stats_player_latest';

  int id_league = 0;
  int id_stats = 0;
  int id_player = 0;
  int id_team = 0;
  int int_rank = 0;
  double stats = 0;
  int cnt_play = 0;

  @override
  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "id_league": id_league,
        "id_stats": id_stats,
        "id_player": id_player,
        "id_team": id_team,
        "int_rank": int_rank,
        "cnt_play": cnt_play,
        "stats": stats,
      });
  }
}
