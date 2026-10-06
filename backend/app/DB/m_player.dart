import '../../tools/DBModel.dart';

class m_player extends DBModel {
  String name_last = '';
  String name_first = '';
  String name_full = '';
  String name_middle = '';
  /// MLB 略称（J.チョウリオ）照合用のファーストネーム頭文字（A–Z, 最大3文字）
  String name_first_initial = '';
  DateTime? date_birth = null;
  int id_team = 0;
  int id_position = 0;
  int height = 0;
  int weight = 0;
  int pitching = 0;
  int batting = 0;
  bool flg_injury = false;
  String path_img_face = '';
  String uniform_number = '';
  bool flg_rookie = false;
  bool flg_ace = false;
  int? id_country;
  int? id_place_birth;
  int? year_retire;

  @override
  String get tableName => 'm_player';

  @override
  Map<String, dynamic> toMap() {
    return {
      "name_last": name_last,
      "name_first": name_first,
      "name_full": name_full.isNotEmpty ? name_full : '$name_last$name_first',
      "name_middle": name_middle,
      "name_first_initial": name_first_initial.isEmpty ? null : name_first_initial,
      "date_birth": date_birth,
      "id_team": id_team,
      "id_position": id_position,
      "height": height,
      "weight": weight,
      "pitching": pitching,
      "batting": batting,
      "flg_injury": flg_injury,
      "path_img_face": path_img_face,
      "uniform_number": uniform_number,
      "flg_rookie": flg_rookie,
      "flg_ace": flg_ace,
      "id_country": id_country,
      "id_place_birth": id_place_birth,
      "year_retire": year_retire,
    };
  }
}
