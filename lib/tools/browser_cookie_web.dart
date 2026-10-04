import 'package:web/web.dart';

String? readBrowserCookie(String name) {
  final raw = document.cookie;
  if (raw.isEmpty) return null;
  for (final part in raw.split(';')) {
    final item = part.trim();
    final eq = item.indexOf('=');
    if (eq <= 0) continue;
    if (item.substring(0, eq) == name) return Uri.decodeComponent(item.substring(eq + 1));
  }
  return null;
}

void writeBrowserCookie(String name, String value, {int maxAgeSeconds = 31536000}) {
  final encoded = Uri.encodeComponent(value);
  document.cookie = '$name=$encoded; path=/; max-age=$maxAgeSeconds; SameSite=Lax';
}

void clearBrowserCookie(String name) {
  document.cookie = '$name=; path=/; max-age=0; SameSite=Lax';
}
