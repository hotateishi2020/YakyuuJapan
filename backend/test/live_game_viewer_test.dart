import 'package:test/test.dart';
import '../app/GameStatsLoad.dart';
void main() {
  test('ID1・2だけが期限付きで試合中の打席取得を有効にする', () {
    final now = DateTime.now();
    expect(GameStatsLoad.enableLiveViewer(null, now: now), false);
    expect(GameStatsLoad.enableLiveViewer(3, now: now), false);
    expect(GameStatsLoad.enableLiveViewer(1, now: now), true);
    expect(GameStatsLoad.needsRefresh(finished: false, loaded: false, live: true), true);
    expect(GameStatsLoad.needsRefresh(finished: false, loaded: false), false);
    expect(GameStatsLoad.liveViewerActive(now: now.add(const Duration(seconds: 91))), false);
    expect(GameStatsLoad.enableLiveViewer(2, now: now), true);
    expect(GameStatsLoad.isLive('5回表'), true);
    expect(GameStatsLoad.isLive('試合終了'), false);
    expect(GameStatsLoad.isLive('試合前'), false);
    GameStatsLoad.enableLiveViewer(1, now: now.subtract(const Duration(minutes: 5)));
    expect(GameStatsLoad.needsRefresh(finished: false, loaded: false, live: true), false);
  });
}
