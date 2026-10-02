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

void writeBrowserCookie(String name, String value) {
  final encoded = Uri.encodeComponent(value);
  document.cookie = '$name=$encoded; path=/; max-age=31536000; SameSite=Lax';
}
