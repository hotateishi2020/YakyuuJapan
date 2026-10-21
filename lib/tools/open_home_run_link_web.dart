import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Called directly by the tap handler, after the video URL has been resolved.
Future<bool> openHomeRunLink(Uri uri) async {
  final agent = web.window.navigator.userAgent;
  final mobile = RegExp(r'Android|iPhone|iPad|iPod').hasMatch(agent) ||
      (agent.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1);
  if (!mobile || uri.path != '/watch') {
    web.window.open(uri.toString(), '_blank', 'noopener,noreferrer');
    return true;
  }
  // Do not create an intermediary tab before handing the video to YouTube.
  var leftPage = false;
  late final JSFunction listener;
  listener = ((web.Event _) {
    if (web.document.visibilityState == 'hidden') leftPage = true;
  }).toJS;
  web.document.addEventListener('visibilitychange', listener);
  final appUri = Uri(scheme: 'youtube', host: 'www.youtube.com', path: '/watch', query: uri.query);
  web.window.location.href = agent.contains('Android')
      ? 'intent://www.youtube.com/watch?${uri.query}#Intent;scheme=https;package=com.google.android.youtube;end'
      : appUri.toString();
  Timer(const Duration(milliseconds: 1800), () {
    web.document.removeEventListener('visibilitychange', listener);
    if (!leftPage && web.document.visibilityState == 'visible') {
      web.window.open(uri.toString(), '_blank', 'noopener,noreferrer');
    }
  });
  return true;
}
