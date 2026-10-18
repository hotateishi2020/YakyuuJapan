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
