import '../../tools/DBModel.dart';

class m_country extends DBModel {
  String name = '';
  String emoji = '';

  @override
  String get tableName => 'm_country';

  @override
  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        'name': name,
        'emoji': emoji,
      });
  }
}
