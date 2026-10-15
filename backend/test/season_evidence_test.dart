import 'package:test/test.dart';
import '../app/SeasonUsageEvidence.dart';
import '../app/PlayerAchievements.dart';

void main() {
  test('NPB投球回の端数をアウトにして打席数と別に取得', () {
    const pitching =
        '<table><tr><th>選手</th><th>投球回</th></tr><tr><td>投 手</td><td>12.2</td></tr></table>';
    expect(parseLevelMetrics(pitching, pitching: true)['投手']?['outs'], 38);
    expect(
        parseLevelMetrics(
            '<table><tr><th>選手</th><th>打席</th></tr><tr><td>打 者</td><td>32</td></tr></table>',
            pitching: false)['打者']?['pa'],
        32);
  });
  test('出場ゼロは新しい守備位置に数えない', () {
    const source =
        '<div class="bis_table"><h5>外野手</h5><table><tbody><tr><td>内 野</td><td>1</td></tr><tr><td>未出場</td><td>0</td></tr></tbody></table></div>';
    expect(parseFieldingRoles(source), {
      '内野': {'外野手'}
    });
  });
  test('節目は到達年に一度だけ・将来年は含まない', () {
    final result = statisticalAchievements([
      {'year': 2022, 'hr': 80},
      {'year': 2023, 'hr': 40, 'sb': 40, 'avg': '.301', 'rbi': 100},
      {'year': 2024, 'hr': 10},
      {'year': 2027, 'hr': 100}
    ], 'https://example.com', 'NPB', 2026);
    expect(
        result.where((r) => r['label'] == 'NPB 通算100本塁打').single['year'], 2023);
    expect(result.any((r) => r['label'] == 'NPB 40-40'), isTrue);
    expect(result.any((r) => r['label'] == 'NPB トリプルスリー'), isTrue);
    expect(result.any((r) => r['year'] == 2027), isFalse);
  });
  test('月間MVPは月別に区別する', () {
    final result = npbMonthlyEntries(
        '<table><tr><th>5月度</th><td><a href="/bis/players/1.html">選手</a></td></tr><tr><th>6月度</th><td><a href="/bis/players/1.html">選手</a></td></tr></table>',
        2025,
        'https://npb.jp');
    expect(result['npb:1']!.map((r) => r['id']).toSet().length, 2);
  });
  test('日本一メダルは規定到達かつ優勝チームだけ', () {
    const source =
        '<div><a name="standings"></a></div><div><table><tr><td class="yearlyMain">阪神タイガース</td></tr></table></div><div><a name="indBatting"></a></div><div><table><tr><td>1</td><td>選 手</td><td>(阪神)</td><td>.300</td></tr></table></div>';
    final r = npbQualifiedEntries(source, 2023, 'https://npb.jp',
        japanChampion: '阪神タイガース')['選手']!;
    expect(r.map((b) => b['label']),
        containsAll(['規定打席到達', 'リーグ優勝レギュラー', '日本一レギュラー']));
  });
}
