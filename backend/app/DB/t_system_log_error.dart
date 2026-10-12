import '../../tools/DBModel.dart';

class t_system_log_error extends DBModel {
  @override
  String tableName = 't_system_log_error';
  String message_error = '';
  String stacktrace = '';
  bool flg_check = false;
  String code_log_system = '';
  String txt_detail = '';

  @override
  Map<String, dynamic> toMap() {
    return super.toMap()
      ..addAll({
        "message_error": message_error,
        "stacktrace": stacktrace,
        "flg_check": flg_check,
        "code_log_system": code_log_system,
        "txt_detail": txt_detail,
      });
  }
}
