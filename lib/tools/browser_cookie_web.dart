import 'package:web/web.dart';

const _storagePrefix = 'koko_cookie_';

String? readBrowserCookie(String name) {
  final raw = document.cookie;
  if (raw.isNotEmpty) {
    for (final part in raw.split(';')) {
      final item = part.trim();
      final eq = item.indexOf('=');
      if (eq <= 0) continue;
      if (item.substring(0, eq) == name) {
        return Uri.decodeComponent(item.substring(eq + 1));
      }
    }
  }
  try {
    final stored = window.localStorage.getItem('$_storagePrefix$name');
    if (stored != null && stored.isNotEmpty) return stored;
  } catch (_) {}
  return null;
}

void writeBrowserCookie(String name, String value, {int maxAgeSeconds = 31536000}) {
  final encoded = Uri.encodeComponent(value);
  document.cookie = '$name=$encoded; path=/; max-age=$maxAgeSeconds; SameSite=Lax';
  try {
    window.localStorage.setItem('$_storagePrefix$name', value);
  } catch (_) {}
}

void clearBrowserCookie(String name) {
  document.cookie = '$name=; path=/; max-age=0; SameSite=Lax';
  try {
    window.localStorage.removeItem('$_storagePrefix$name');
  } catch (_) {}
}
