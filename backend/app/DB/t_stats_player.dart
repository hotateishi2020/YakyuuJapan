import '../../tools/DBModel.dart';

class t_stats_player extends DBModel {
  String tableName = 't_stats_player';
  int id_league = 0;
  int id_stats = 0;
  int id_player = 0;
  int id_team = 0;
  int int_year = 0;
  int int_rank = 0;
  double stats = 0;
  String code_category = '';
  int cnt_play = 0;

  String playerName = '';
  String teamName = '';
  String playerUrl = '';

  /// スクレイプ時の補助。DB カラムには載せない。
  int seasonAppearances = 0;
  int seasonStarts = 0;
  double seasonInnings = 0;
  int seasonWins = 0;
  int seasonStrikeouts = 0;
  double seasonEra = 0;

  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "id_league": id_league,
        "id_stats": id_stats,
        "id_player": id_player,
        "id_team": id_team,
        "int_year": int_year == 0 ? DateTime.now().year : int_year,
        "int_rank": int_rank,
        "cnt_play": cnt_play,
        "stats": stats,
      });
  }
}
