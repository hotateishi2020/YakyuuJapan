import '../../tools/DBModel.dart';

class m_stadium extends DBModel {
  @override
  String tableName = 'm_stadium';
  String name_short = '';
  String name_full = '';
  int id_team = 0;
  int id_city = 0;
  String path_image_inside = '';
  String path_image_outside = '';

  @override
  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "name_short": name_short,
        "name_full": name_full,
        "id_team": id_team,
        "id_city": id_city,
        "path_image_inside": path_image_inside,
        "path_image_outside": path_image_outside,
      });
  }
}
