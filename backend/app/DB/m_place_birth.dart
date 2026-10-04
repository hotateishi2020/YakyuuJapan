import '../../tools/DBModel.dart';

class m_place_birth extends DBModel {
  String name = '';
  int id_country = 0;

  @override
  String get tableName => 'm_place_birth';

  @override
  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        'name': name,
        'id_country': id_country,
      });
  }
}
