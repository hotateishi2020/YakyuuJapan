import 'package:test/test.dart';
import '../app/QualifiedBattingMetrics.dart';

void main() {
  test('NPB and MLB qualifying plate-appearance boundaries', () {
    expect(hasQualifiedBattingAppearances(443, 143), true);
    expect(hasQualifiedBattingAppearances(442, 143), false);
    expect(hasQualifiedBattingAppearances(502, 162), true);
    expect(hasQualifiedBattingAppearances(501, 162), false);
    expect(hasQualifiedBattingAppearances(null, 143), false);
    expect(hasQualifiedBattingAppearances(500, null), false);
    expect(hasQualifiedBattingAppearances(500, 0), false);
  });
  test(
      'RISP excludes underqualified and unknown players then reranks ties per league',
      () {
    final rows = <Map<String, dynamic>>[
      {'title': '本塁打', 'cnt_play': 10, 'int_game': 143},
      for (final e in [
        (1, 100, '.900'),
        (1, 443, '.400'),
        (1, 500, '.400'),
        (1, 550, '.300'),
        (2, 443, '.350'),
        (2, 0, '.500')
      ])
        {
          'title': '得点圏打率',
          'id_league': e.$1,
          'cnt_play': e.$2,
          'int_game': 143,
          'stats': e.$3,
          'int_rank': 99
        },
      {'title': '得点圏打率', 'stats': '.500'},
    ];
    retainQualifiedRisp(rows);
    expect(rows.length, 5);
    expect(rows.skip(1).map((r) => r['int_rank']), [1, 1, 3, 1]);
    expect(rows.first['title'], '本塁打');
  });
}
