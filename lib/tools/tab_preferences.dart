import 'browser_cookie.dart';

/// Restore only tabs that still exist; removed or invalid values use the default.
int readSavedTab(String scope, List<int> available, {required int fallback}) {
  final saved = int.tryParse(readBrowserCookie('koko_tab_$scope') ?? '');
  return available.contains(saved) ? saved! : fallback;
}

void saveTab(String scope, int tab) =>
    writeBrowserCookie('koko_tab_$scope', '$tab');
