import 'package:url_launcher/url_launcher.dart';

Future<bool> openHomeRunLink(Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication)) return true;
  } catch (_) {}
  return launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
}
