import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/player_related_videos.dart';

void main() {
  testWidgets('最近と再生数の多い動画をそれぞれの順序で表示する', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: PlayerRelatedVideos(name: '山田太郎', org: 'npb'),
      ))));
      await tester.pumpAndSettle();
      final titles = tester.widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title as Text).data).toList();
      expect(titles, ['山田太郎 新着', '山田太郎 人気', '山田太郎 人気', '山田太郎 新着']);
      expect(find.text('最近の動画'), findsOneWidget);
      expect(find.text('再生数の多い動画'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async => http.Response(jsonEncode({
      'channels': [{'name': '公式', 'videos': [
        {'id': 'abcdefghijk', 'title': '山田太郎 人気', 'published_at': '2026-10-01T00:00:00Z', 'view_count': 10000},
        {'id': 'abcdefghijl', 'title': '山田太郎 新着', 'published_at': '2026-10-20T00:00:00Z', 'view_count': 100},
      ]}],
    }), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
  });

  test('フルネームで照合し、重複動画をまとめ、再生数を保持する', () {
    final videos = relatedPlayerVideos([
      {'name': '球団', 'videos': [
        {'id': 'abcdefghijk', 'title': '山田 太郎の本塁打', 'published_label': '1日前'},
        {'id': 'abcdefghijl', 'title': '山田次郎の本塁打'},
      ]},
      {'name': '球団', 'videos': [
        {'id': 'abcdefghijk', 'title': '山田太郎の本塁打', 'view_count': 12345, 'published_label': '1日前'},
      ]},
    ], '山田　太郎', DateTime.utc(2026, 10, 21));
    expect(videos, hasLength(1));
    expect(videos.single['view_count'], 12345);
    expect(videos.single['published_sort_at'], '2026-10-20T00:00:00.000Z');
    expect(relatedPlayerVideos([], '', DateTime.now()), isEmpty);
  });
}
