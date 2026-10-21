import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../app/HomeRunVideoSearch.dart';
import '../app/VideoFeed.dart';

void main() {
  test('栗原のCS満塁弾は検証済み公式動画を返す', () async {
    final channels = await searchHomeRunVideos('栗原 陵矢', DateTime(2026, 10, 15), 'vs日本ハム', true);
    final video = (channels.single['videos'] as List).single;
    expect(video['id'], 'jEPrmVTYt50');
    expect(video['game_date'], '2026-10-15');
    expect(video['game_date_source'], startsWith('https://pacificleague.com/'));
  });
  test('YouTube search parses a matching video and uses fixed search endpoint',
      () async {
    final html = 'var ytInitialData = ${jsonEncode({
          'contents': {
            'twoColumnSearchResultsRenderer': {
              'contents': [
                {
                  'videoRenderer': {
                    'videoId': 'abcdefghijk',
                    'title': {'simpleText': '甲選手 ホームラン 2026/10/20'}
                  }
                }
              ]
            }
          }
        })};';
    expect(parseVideoSearchPage(html).single['id'], 'abcdefghijk');
    await http.runWithClient(() async {
      final result = await searchHomeRunVideos(
          '甲選手', DateTime(2026, 10, 20), 'vs巨人', false);
      expect((result.single['videos'] as List).single['id'], 'abcdefghijk');
    },
        () => MockClient((request) async {
              expect(request.url.host, 'www.youtube.com');
              expect(request.url.path, '/results');
              expect(request.url.queryParameters['search_query'],
                  contains('2026/10/20'));
              return http.Response.bytes(utf8.encode(html), 200);
            }));
  });
  test('Pacific search rejects content from a different channel', () async {
    await http.runWithClient(() async {
      final result = await searchHomeRunVideos(
          '乙選手', DateTime(2026, 10, 20), 'vs西武', true);
      expect(result, isEmpty);
    },
        () => MockClient((request) async {
              expect(
                  request.url.path, '/channel/UC0v-pxTo1XamIDE-f__Ad0Q/search');
              return http.Response(
                  'var ytInitialData = ${jsonEncode({
                        'metadata': {
                          'channelMetadataRenderer': {'externalId': 'wrong'}
                        }
                      })};',
                  200);
            }));
  });
}
