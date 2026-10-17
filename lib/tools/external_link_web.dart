import 'package:web/web.dart' as web;

void openExternalLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme == 'https') {
    web.window.open(url, '_blank', 'noopener,noreferrer');
  }
}
