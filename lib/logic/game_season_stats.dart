/// Compact season totals; missing values stay unknown rather than becoming zero.
String gameSeasonStats(List<Map<String, dynamic>> rows, {required bool pitching, String role = ''}) {
  String value(List<String> titles, {int? decimals, String suffix = ''}) {
    for (final title in titles) {
      for (final row in rows.where((r) => r['title'] == title)) {
        final raw = '${row['stats'] ?? row['numeric_value'] ?? ''}'.trim();
        if (const ['登板なし', '打席なし', '算出不可', '∞'].contains(raw)) return raw;
        final n = num.tryParse(RegExp(r'^(?:\d+(?:\.\d+)?|\.\d+)').firstMatch(raw)?.group(0) ?? '');
        if (n == null) continue;
        var text = decimals == null ? n.toInt().toString() : n.toStringAsFixed(decimals);
        if (decimals == 3 && text.startsWith('0.')) text = text.substring(1);
        return '$text$suffix';
      }
    }
    return '—$suffix';
  }
  if (!pitching) return '${value(['打率'], decimals: 3)} ${value(['本塁打', '本塁打数'], suffix: '本')}';
  final total = role == '先' ? value(['最多勝', '勝利', '勝利数'], suffix: '勝')
      : role == '抑' ? value(['セーブ', 'セーブ数'], suffix: 'S')
      : value(['ホールド', 'ホールド数'], suffix: 'H');
  return '${value(['防御率'], decimals: 2)} $total';
}
