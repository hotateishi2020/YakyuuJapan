import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/tools/open_home_run_link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class Launcher extends UrlLauncherPlatform {
  @override
  Null get linkDelegate => null;
  bool appInstalled = true;
  final calls = <LaunchOptions>[];
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add(options);
    expect(url, 'https://www.youtube.com/watch?v=jEPrmVTYt50');
    return appInstalled || calls.length > 1;
  }
}
void main() {
  test('YouTubeアプリを優先し、起動できた場合はブラウザを開かない', () async {
    final previous = UrlLauncherPlatform.instance;
    final launcher = Launcher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    expect(await openHomeRunLink(Uri.parse('https://www.youtube.com/watch?v=jEPrmVTYt50')), isTrue);
    expect(launcher.calls, hasLength(1));
    expect(launcher.calls.single.mode, PreferredLaunchMode.externalNonBrowserApplication);
  });
  test('アプリを開けない場合は別タブ指定でブラウザを開く', () async {
    final previous = UrlLauncherPlatform.instance;
    final launcher = Launcher()..appInstalled = false;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    await openHomeRunLink(Uri.parse('https://www.youtube.com/watch?v=jEPrmVTYt50'));
    expect(launcher.calls, hasLength(2));
    expect(launcher.calls.last.webOnlyWindowName, '_blank');
  });
}
