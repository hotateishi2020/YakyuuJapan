import 'package:flutter_test/flutter_test.dart';

import '../backend/app/GameFetchSchedule.dart';

void main() {
  testWidgets('初期表示完了の通知までは両団体の定期取得を開始しない', (tester) async {
    GameFetchSchedule.resetForTest();
    var todayCalls = 0;
    var futureCalls = 0;
    for (final org in ['npb', 'mlb']) {
      GameFetchSchedule.scheduleTodayAgain(org, () async {
        todayCalls++;
        return false;
      });
      GameFetchSchedule.armFutureWatch(org, () async => futureCalls++);
    }

    await tester.pump(const Duration(minutes: 10));
    expect(todayCalls, 0);
    expect(futureCalls, 0);
    expect(GameFetchSchedule.isTodayQueued('npb'), isFalse);
    expect(GameFetchSchedule.isFutureQueued('mlb'), isFalse);

    GameFetchSchedule.markInitialDisplayReady();
    GameFetchSchedule.markInitialDisplayReady();
    await tester.pump(const Duration(seconds: 9));
    expect(todayCalls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(todayCalls, 2);
    expect(futureCalls, 0);
    await tester.pump(const Duration(seconds: 10));
    expect(futureCalls, 2);
    await tester.pump(const Duration(minutes: 10));
    expect(todayCalls, 2);
    expect(futureCalls, 4);
    GameFetchSchedule.resetForTest();
    await tester.pump(const Duration(minutes: 10));
  });
}
