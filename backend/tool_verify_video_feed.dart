import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/VideoFeed.dart';
import 'app/VideoChannels.dart';

Future<void> main() async {
  final client = http.Client();
  try {
    final selected = Platform.environment['VIDEO_CHANNEL_IDS']?.split(',');
    final registry = Platform.environment['VIDEO_ORG'] == 'mlb'
        ? mlbVideoChannels
        : videoChannels;
    final result = await VideoFeedService(
            client: client,
            channels: selected == null
                ? registry
                : registry.where((c) => selected.contains(c.id)).toList())
        .read();
    for (final channel in result['channels'] as List) {
      final videos = channel['videos'] as List;
      print(
          '${channel['name']}: ${channel['status']} (${videos.length}) ${videos.isEmpty ? '' : videos.first['title']}');
    }
    if ((result['channels'] as List).any((c) => c['status'] != 'ok')) {
      exitCode = 1;
    }
    if (Platform.environment['VIDEO_VERIFY_OUTPUT'] case final String path) {
      File(path).writeAsStringSync(jsonEncode(result));
    }
  } finally {
    client.close();
  }
}
