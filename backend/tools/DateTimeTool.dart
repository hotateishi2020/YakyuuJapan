import 'package:intl/intl.dart';

class DateTimeTool {
  static int getThisYear() {
    return int.tryParse(DateFormat('yyyy').format(DateTime.now())) ?? 0;
  }
}
