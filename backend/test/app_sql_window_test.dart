import 'package:test/test.dart';

import '../app/AppSql.dart';

void main() {
  test('current-year games window looks back 3 days', () {
    expect(AppSql.gamesPastDays, 3);
    expect(AppSql.gamesFutureDays, 10);
    final sql = AppSql.gameDateWindow();
    expect(sql, contains('CURRENT_DATE - 3'));
    expect(sql, contains('CURRENT_DATE + 10'));
    expect(sql, isNot(contains('CURRENT_DATE - 10')));
  });

  test('ranged window uses explicit from/to parameters', () {
    final sql = AppSql.selectGames(ranged: true);
    expect(sql, contains(r'$2::date'));
    expect(sql, contains(r'$3::date'));
    expect(sql, contains(r'$1::int'));
    expect(sql, contains('EXTRACT(YEAR FROM datetime_start)::int = \$1::int'));
    expect(AppSql.selectGamePlayRows(ranged: true), contains(r'$2::date'));
    expect(AppSql.selectGamePlayRows(ranged: true), contains(r'$1::int'));
    expect(AppSql.selectBattingLines(ranged: true), contains(r'$2::date'));
    expect(AppSql.selectBattingLines(ranged: true), contains(r'$1::int'));
  });
}
