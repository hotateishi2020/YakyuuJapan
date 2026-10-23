import 'package:html/dom.dart';

String _label(String text) => String.fromCharCodes(text.runes.map(
    (c) => c >= 0xFF01 && c <= 0xFF5E ? c - 0xFEE0 : c))
    .replaceAll(RegExp(r'\s'), '');

/// Read named columns from the season's matching discipline, never row offsets
/// shared by pitching, batting, and runners-in-scoring-position tables.
Map<String, double> mlbProfileStats(Document doc, {required bool pitching}) {
  for (final table in doc.querySelectorAll('#js-tabDom01 table.bb-playerStatsTable')) {
    final labels = table.querySelectorAll('th').map((e) => _label(e.text)).toSet();
    if (pitching ? !labels.contains('防御率') : !(labels.contains('打率') && labels.contains('試合'))) continue;
    final result = <String, double>{};
    var headers = <String>[];
    for (final row in table.querySelectorAll('tr')) {
      final th = row.querySelectorAll('th');
      if (th.isNotEmpty) { headers = th.map((e) => _label(e.text)).toList(); continue; }
      final cells = row.querySelectorAll('td');
      if (cells.length != headers.length) continue;
      for (var i = 0; i < cells.length; i++) {
        final value = double.tryParse(cells[i].text.trim().replaceAll(',', ''));
        if (value != null) result[headers[i]] = value;
      }
    }
    if (pitching && !result.containsKey('WHIP')) {
      final innings = result['投球回'];
      final hits = result['被安打'];
      final walks = result['与四球'];
      if (innings != null && innings.isFinite && innings >= 0 &&
          hits != null && hits >= 0 && walks != null && walks >= 0) {
        final fraction = (innings - innings.floor()) * 10;
        final remainder = fraction.round();
        final outs = innings.floor() * 3 + remainder;
        if (remainder <= 2 && (fraction - remainder).abs() < .00001 && outs > 0) {
          result['WHIP'] = double.parse(((hits + walks) * 3 / outs).toStringAsFixed(2));
        }
      }
    }
    return result;
  }
  return {};
}

String mlbProfileStatLabel(String title) => const {
  '最多勝': '勝利', '最多安打': '安打', '打席数': '打席',
  '登板回数': '登板', '投球回数': '投球回', '得点圏打率': '得点圏',
}[title] ?? title;
