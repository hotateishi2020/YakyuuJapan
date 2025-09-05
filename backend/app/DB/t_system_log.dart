import '../../tools/DBModel.dart';

class t_system_log extends DBModel {
  String tableName = 't_system_log';
  String method = '';
  String category = '';
  String code = '';
  String memo = '';
  bool flg_user = false;
  String url = '';
  String url_pre = '';
  int id_log_error = 0;
  bool flg_check = false;

  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "method": method,
        "category": category,
        "code": code,
        "memo": memo,
        "flg_user": flg_user,
        "url": url,
        "url_pre": url_pre,
        "id_log_error": id_log_error,
        "flg_check": flg_check,
      });
  }
}
