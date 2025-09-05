import '../../tools/DBModel.dart';
import 'package:postgres/postgres.dart';
import '../AppSql.dart';
import '../../tools/Postgres.dart';

class m_user extends DBModel {
  String tableName = 'm_user';
  String name_last = '';
  String name_first = '';
  String nickname = '';
  String mailaddress = '';
  String password = '';
  String code_color = '';

  //操作ログ用に追加（カラムではない）
  String category_system = '';
  String code_system = '';
  bool flg_user = false;

  Future loadProperty(Connection conn, int id) async {
    final user = m_user();
    user.id = id;

    if (id == 0) {
      return user;
    }
    final result =
        await Postgres.execute(conn, AppSql.selectUserWhereId(), data: [id]);
    user.name_last = result.first.toColumnMap()['name_last'];
    user.name_first = result.first.toColumnMap()['name_first'];
    user.nickname = result.first.toColumnMap()['nickname'];
    user.mailaddress = result.first.toColumnMap()['mailaddress'];
    user.password = result.first.toColumnMap()['password'];
    user.code_color = result.first.toColumnMap()['code_color'];
    user.flg_user = true;
    return user;
  }

  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "name_last": name_last,
        "name_first": name_first,
        "nickname": nickname,
        "mailaddress": mailaddress,
        "password": password,
        "code_color": code_color,
      });
  }
}
