import 'package:test/test.dart';
import '../app/StrengthMetrics.dart';
import '../app/StrengthContracts.dart';

void main() {
  test('リンクなし公式打撃成績から打席・OPS・四球込み塁打を読む', () {
    final values = [
      '+ 選手',
      10,
      30,
      25,
      2,
      10,
      2,
      1,
      3,
      23,
      7,
      0,
      0,
      0,
      0,
      5,
      0,
      0,
      2,
      0,
      '.400',
      '.920',
      '.500'
    ];
    final p = parseNpbMetrics(
            '<table><tr>${values.map((v) => '<td>$v</td>').join()}</tr></table>',
            pitching: false)
        .single;
    expect(p['name'], '選手');
    expect(p['bats'], '両');
    expect(p['pa'], 30);
    expect(p['total_bases_walks'], 28);
    expect(p['ops'], closeTo(1.420, .001));
    expect(p['singles'], 4);
  });
  test('投球回の端数をアウトに直してWHIPを計算', () {
    final values = [
      '投手',
      10,
      1,
      0,
      2,
      3,
      0,
      0,
      0,
      0,
      '.500',
      30,
      '8 1/3',
      7,
      1,
      3,
      0,
      0,
      5,
      0,
      0,
      2,
      2,
      '2.16'
    ];
    final p = parseNpbMetrics(
            '<table><tr>${values.map((v) => '<td>$v</td>').join()}</tr></table>',
            pitching: true)
        .single;
    expect(p['whip'], closeTo(1.2, .001));
    expect(p['holds'], 3);
    expect(p['saves'], 2);
  });
  test('年俸の億・万円と未公表を区別する', () {
    expect(parseYen('12億2,000万円'), 1220000000);
    expect(parseYen('480万円'), 4800000);
    expect(parseYen('未公表'), isNull);
  });
  test('年俸掲載年度から契約終了を推測しない', () {
    final p = parseContractHistory(
        '<details class="npbsd-history-card"><span class="npbsd-history-year">2026</span><span class="npbsd-history-salary">1億円</span></details>',
        'https://example.com',
        '選手',
        'npb:1');
    expect(p['periods'], isEmpty);
    expect((p['salary_history'] as List).single['year'], 2026);
  });
}
