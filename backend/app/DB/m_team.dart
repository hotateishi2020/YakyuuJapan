import '../../tools/DBModel.dart';

class m_team extends DBModel {
  String tableName = 'm_team';
  String name_shortest = '';
  String name_short = '';
  String name_full = '';
  int id_league = 0;
  String color_font = '';
  String color_back = '';
  String path_img_logo = '';
  String url_npb_players = '';

  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "name_shortest": name_shortest,
        "name_short": name_short,
        "name_full": name_full,
        "id_league": id_league,
        "color_font": color_font,
        "color_back": color_back,
        "path_img_logo": path_img_logo,
        "url_npb_players": url_npb_players,
      });
  }
}
