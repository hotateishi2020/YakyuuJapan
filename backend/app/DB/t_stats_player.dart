import '../../tools/DBModel.dart';

class t_stats_player extends DBModel {
  String tableName = 't_stats_player';
  int id_league = 0;
  int id_stats = 0;
  int id_player = 0;
  int id_team = 0;
  int int_rank = 0;
  double stats = 0;
  String code_category = '';

  String playerName = '';
  String teamName = '';

  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "id_league": id_league,
        "id_stats": id_stats,
        "id_player": id_player,
        "id_team": id_team,
        "int_rank": int_rank,
        "stats": stats,
      });
  }
}
