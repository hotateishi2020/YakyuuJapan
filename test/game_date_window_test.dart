import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/game_date_window.dart';

void main() {
  test('current year window is today minus 3 through plus 10', () {
    final window = defaultGamesSqlWindow(DateTime(2026, 10, 7));
    expect(ymdOf(window.from), '2026-10-04');
    expect(ymdOf(window.to), '2026-10-17');
  });

  test('dates inside the loaded window do not need another SQL read', () {
    final from = DateTime(2026, 10, 4);
    final to = DateTime(2026, 10, 17);
    expect(gameDateNeedsSqlLoad(DateTime(2026, 10, 7), from, to, {}), isFalse);
    expect(gameDateNeedsSqlLoad(DateTime(2026, 10, 4), from, to, {}), isFalse);
    expect(gameDateNeedsSqlLoad(DateTime(2026, 10, 3), from, to, {}), isTrue);
    expect(
      gameDateNeedsSqlLoad(DateTime(2026, 10, 3), from, to, {'2026-10-03'}),
      isFalse,
    );
    expect(
      gameDateNeedsSqlLoad(DateTime(2026, 10, 6), from, to, {}, hasGamesForDate: true),
      isFalse,
    );
    expect(
      gameDateNeedsSqlLoad(DateTime(2026, 10, 6), from, to, {}, hasGamesForDate: false),
      isTrue,
    );
  });

  test('merge keeps extra past days when the default window refreshes', () {
    final merged = mergeGamesForDateRange(
      [
        {'id_game': 1, 'date_game': '2026-10-03', 'name_team_home': '旧日'},
        {'id_game': 2, 'date_game': '2026-10-07', 'name_team_home': '古い今日'},
      ],
      [
        {'id_game': 3, 'date_game': '2026-10-07', 'name_team_home': '新しい今日'},
      ],
      DateTime(2026, 10, 4),
      DateTime(2026, 10, 17),
    );
    expect(merged.map((game) => game['id_game']).toList(), [1, 3]);
  });
}
