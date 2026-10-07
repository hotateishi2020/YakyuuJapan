import 'package:test/test.dart';

import '../app/PlayerStatsSchedule.dart';

void main() {
  tearDown(() {
    PlayerStatsSchedule.resetForTest();
  });

  test('個人成績の定期取得は初期表示より後で、重ねて走らせない', () async {
    expect(PlayerStatsSchedule.firstDelay, const Duration(minutes: 5));
    expect(PlayerStatsSchedule.interval, const Duration(minutes: 30));

    var runs = 0;
    PlayerStatsSchedule.resetForTest(run: () async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });

    final first = PlayerStatsSchedule.tick(onUpdated: () {});
    final second = PlayerStatsSchedule.tick(onUpdated: () {});
    await Future.wait([first, second]);
    expect(runs, 1);
    expect(PlayerStatsSchedule.isBusy, isFalse);
  });
}
