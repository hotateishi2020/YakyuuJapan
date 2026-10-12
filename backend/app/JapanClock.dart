/// Yahoo の試合日は日本時間。サーバーが UTC でも、0時から9時の試合を「翌日」にしない。
class JapanClock {
  static const offset = Duration(hours: 9);

  static DateTime now() => fromUtc(DateTime.now().toUtc());

  static DateTime fromUtc(DateTime utc) {
    final shifted = utc.toUtc().add(offset);
    return DateTime(shifted.year, shifted.month, shifted.day, shifted.hour, shifted.minute, shifted.second);
  }
}
