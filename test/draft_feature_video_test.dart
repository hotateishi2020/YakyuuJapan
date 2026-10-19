import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_research.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _Launcher extends UrlLauncherPlatform {
  @override
  Null get linkDelegate => null;
  String? opened;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {opened=url; return true;}
}
void main() {
  test('関連動画は重複とショートを除いて再生数順に最大4件', () {
    final videos = draftRelatedVideos({'feature_videos': [
      for (var i = 0; i < 6; i++) {'video_id': 'abcdefghij$i', 'view_count': i * 100},
      {'video_id': 'abcdefghij5', 'view_count': 500},
      {'video_id': 'abcdefghij9', 'view_count': 900, 'is_short': true},
    ]});
    expect(videos.map((v) => v['video_id']), ['abcdefghij5', 'abcdefghij4', 'abcdefghij3', 'abcdefghij2']);
  });
  test('選手に焦点を当てた内容を再生数より優先する', () {
    final videos = draftRelatedVideos({'feature_videos': [
      {'video_id': 'abcdefghij0', 'title': 'ドラフト指名予想', 'view_count': 999999},
      {'video_id': 'abcdefghij1', 'title': '選手の素顔と休日に密着', 'view_count': 10},
      {'video_id': 'abcdefghij2', 'title': '全打席ハイライト', 'view_count': 100},
      {'video_id': 'abcdefghij3', 'title': '投球フォームとプレイスタイル', 'view_count': 50},
      {'video_id': 'abcdefghij4', 'title': '選手の能力を解説', 'view_count': 20},
    ]});
    expect(videos.map((v) => v['video_id']), ['abcdefghij2', 'abcdefghij3', 'abcdefghij4', 'abcdefghij1']);
  });
  testWidgets('右端の特集動画サムネイルからYouTubeを開く', (tester) async {
    final launcher = _Launcher();
    final previous=UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance=launcher;
    addTearDown(()=>UrlLauncherPlatform.instance=previous);
    await tester.binding.setSurfaceSize(const Size(1200,800));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.runAsync(()=>rootBundle.loadString('backend/assets/data/draft_2026.json'));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StrengthDraft(year:2026))));
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
    await tester.pumpAndSettle();
    final thumbnail=find.byKey(const ValueKey('draft-video-織田翔希'));
    expect(thumbnail,findsOneWidget);
    expect(find.ancestor(of: thumbnail, matching: find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal)), findsOneWidget);
    final videoRow = find.ancestor(of: thumbnail, matching: find.byType(Row)).first;
    expect(tester.getSize(videoRow).width, greaterThanOrEqualTo(4 * 168 + 3 * 8));

    expect(find.byWidgetPredicate((widget) => widget is InkWell && '${widget.key}'.contains('draft-video-織田翔希')), findsNWidgets(4));
    final scroller=tester.widget<SingleChildScrollView>(find.byKey(const ValueKey('draft-horizontal-scroll')));
    scroller.controller!.jumpTo(scroller.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(thumbnail);
    await tester.pumpAndSettle();
    expect(launcher.opened,startsWith('https://www.youtube.com/watch?v='));
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
