class DateFormatUtil {
  static String ymdWithOffset(int offset) {
    return ymd(DateTime.now().add(Duration(days: offset)));
  }

  static String ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  static String jaDateWithOffset(int offset) {
    final d = DateTime.now().add(Duration(days: offset));
    const youbi = ['月', '火', '水', '木', '金', '土', '日'];
    final wd = youbi[(d.weekday - 1).clamp(0, 6)];
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y年$m月$dd日($wd)';
  }
}
