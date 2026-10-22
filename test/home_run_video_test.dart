import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/home_run_video.dart';

void main() {
  test('CS満塁弾は確認済み試合日を照合し、投稿日のみでは採用しない', () {
    final video = {'id': 'jEPrmVTYt50', 'title': '【サヨナラ満塁弾】栗原陵矢 日本シリーズ進出に王手', 'published_at': '2026-10-15'};
    List<Map<String, dynamic>> channels() => [{'id': pacificHighlightChannel, 'videos': [video]}];
    expect(matchingHomeRunVideo(channels(), '栗原 陵矢', DateTime(2026, 10, 15), pacific: true), isNull);
    video.addAll({'game_date': '2026-10-15', 'game_date_source': 'https://pacificleague.com/news/2026/10/87029'});
    expect(matchingHomeRunVideo(channels(), '栗原 陵矢', DateTime(2026, 10, 15), pacific: true), 'jEPrmVTYt50');
    expect(matchingHomeRunVideo(channels(), '栗原 陵矢', DateTime(2026, 10, 16), pacific: true), isNull);
    expect(matchingHomeRunVideo([{'id': pacificHighlightChannel, 'videos': [{'id': 'abcdefghijk', 'title': '栗原陵矢 満塁HR 2026年10月15日'}]}], '栗原陵矢', DateTime(2026,10,15), pacific: true), 'abcdefghijk');
  });
  test('home runs only, not pitchers runs conceded', () {
    expect(
        hasHomeRun({
          'plays': [
            {'result': '左本①', 'bases': 1}
          ]
        }),
        isTrue);
    expect(
        hasHomeRun({
          'lines': [
            {'int_homerun': 1}
          ]
        }),
        isTrue);
    expect(
        hasHomeRun({
          'plays': [
            {'result': '左安'}
          ],
          'lines': [
            {'int_runs': 4}
          ]
        }),
        isFalse);
  });
  test('direct video requires player, game date and correct Pacific channel',
      () {
    final date = DateTime(2026, 10, 20);
    final video = {
      'id': 'abcdefghijk',
      'title': '佐藤太郎 ホームラン 2026/10/20',
      'published_at': '2026-10-20'
    };
    expect(
        matchingHomeRunVideo([
          {
            'id': pacificHighlightChannel,
            'videos': [video]
          }
        ], '佐藤 太郎', date, pacific: true),
        'abcdefghijk');
    expect(
        matchingHomeRunVideo([
          {
            'id': 'wrong',
            'videos': [video]
          }
        ], '佐藤太郎', date, pacific: true),
        isNull);
    expect(
        matchingHomeRunVideo([
          {
            'id': pacificHighlightChannel,
            'videos': [video]
          }
        ], '佐藤太郎', DateTime(2026, 10, 2), pacific: true),
        isNull);
  });
}
