import 'DBModel.dart';

class t_game extends DBModel {
  String tableName = 't_game';
  int id_pitcher_home = 0;
  int id_pitcher_away = 0;
  int id_team_home = 0;
  int id_team_away = 0;
  int id_pitcher_win = 0;
  int id_pitcher_lose = 0;
  int id_stadium = 0;
  int score_home = 0;
  int score_away = 0;
  DateTime? datetime_start = null;

  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "id_pitcher_home": id_pitcher_home,
        "id_pitcher_away": id_pitcher_away,
        "id_team_home": id_team_home,
        "id_team_away": id_team_away,
        "id_pitcher_win": id_pitcher_win,
        "id_pitcher_lose": id_pitcher_lose,
        "id_stadium": id_stadium,
        "score_home": score_home,
        "score_away": score_away,
        "datetime_start": datetime_start,
      });
  }
}
