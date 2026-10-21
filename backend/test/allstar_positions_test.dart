import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../app/AllStarPositions.dart';

void main() {
  test('modern and legacy fielding select most frequent infield position', () {
    final result = parseAllStarFielding('''
      <h5>一塁手</h5><table><tr><td>選手 A</td><td>10</td></tr></table>
      <table><tr><th class="sthdfplayer">【三塁手】</th></tr>
      <tr><td></td><td class="stplayer">選手 A</td><td>90</td></tr></table>
      <h5>外野手</h5><table><tr><td>選手 A</td><td>100</td></tr></table>
    ''');
    expect(result['選手A'], {'position': '三塁手', 'games': 90});
  });
  test('substitute defensive appearances exclude pinch hits alone', () {
    String row(String code, String name) =>
        '<tr><td>$code</td><td>$name</td>${'<td>0</td>' * 10}</tr>';
    final result = parseAllStarAppearances(
        '<table>${row('打三', '選手A')}${row('打', '選手B')}</table>');
    expect(result, [
      {'name': '選手A', 'position': '三塁手'}
    ]);
  });
  test('modern generic infielders retain sourced display positions', () {
    final history =
        jsonDecode(File('data/allstar_history.json').readAsStringSync()) as Map;
    final rows = (history['players'] as List)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    applyAllStarPositions(rows,
        jsonDecode(File('data/allstar_positions.json').readAsStringSync()));
    for (final row in rows
        .where((r) => r['position'] == '内野手' && (r['year'] as int) >= 2002)) {
      expect(row['display_position'], isNotNull,
          reason: '${row['year']} ${row['name']}');
      expect(row['position_source'], startsWith('https://npb.jp/'));
    }
  });
}
