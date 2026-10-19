import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mobile web stays in the current browsing context to avoid a blank extra tab.
Future<bool> openYoutube(String id, {bool channel = false}) async {
  if (!(channel ? RegExp(r'^UC[A-Za-z0-9_-]{22}$') : RegExp(r'^[A-Za-z0-9_-]{11}$')).hasMatch(id)) return false;
  final mobile = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
  final uri = channel ? Uri.https('www.youtube.com', '/channel/$id') : Uri.https('www.youtube.com', '/watch', {'v': id});
  if (!kIsWeb && mobile) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication)) return true;
    } catch (_) {}
  }
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: mobile ? '_self' : '_blank');
  } catch (_) { return false; }
}
