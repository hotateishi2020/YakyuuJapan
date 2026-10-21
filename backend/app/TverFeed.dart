import 'VideoClassification.dart';

/// TVer has amateur baseball and general news too; unknown is not NPB.
String? tverVideoOrganization(String title) {
  final organizations = videoOrganizations(title);
  if (organizations.isNotEmpty) {
    return organizations.length == 1 ? organizations.single : null;
  }
  if (title.contains('プロ野球')) return 'npb';
  return null;
}

DateTime? _broadcastDate(String label, DateTime now) {
  final match = RegExp(r'(\d{1,2})月(\d{1,2})日.*?(?:(\d{1,2}):(\d{2}))?')
      .firstMatch(label);
  if (match == null) return null;
  final jst = now.toUtc().add(const Duration(hours: 9));
  final time = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(label);
  var date = DateTime.utc(jst.year, int.parse(match[1]!), int.parse(match[2]!),
      int.parse(time?[1] ?? '0'), int.parse(time?[2] ?? '0'));
  if (date.isAfter(jst.add(const Duration(days: 1)))) {
    date = DateTime.utc(
        jst.year - 1, date.month, date.day, date.hour, date.minute);
  }
  return date.subtract(const Duration(hours: 9));
}

List<Map<String, dynamic>> parseTverSearch(
    Map<String, dynamic> data, DateTime now) {
  if (data['code'] != 0 ||
      data['result'] is! Map ||
      data['result']['contents'] is! List) {
    throw const FormatException('Invalid TVer search');
  }
  final videos = <String, Map<String, dynamic>>{};
  for (final row in (data['result']['contents'] as List).whereType<Map>()) {
    if (row['type'] != 'episode' || row['content'] is! Map) continue;
    final episode = row['content'] as Map;
    final id = '${episode['id'] ?? ''}';
    final title = [
      '${episode['seriesTitle'] ?? ''}',
      '${episode['title'] ?? ''}'
    ].where((s) => s.isNotEmpty).join('：');
    final end = int.tryParse('${episode['endAt']}');
    if (!RegExp(r'^ep[a-zA-Z0-9]+$').hasMatch(id) ||
        episode['isAvailable'] != true ||
        end == null ||
        end * 1000 <= now.millisecondsSinceEpoch ||
        tverVideoOrganization(title) == null) {
      continue;
    }
    final path = '${episode['thumbnailPath'] ?? ''}';
    final thumbnail = Uri.parse('https://statics.tver.jp').resolve(path);
    if (path.isEmpty ||
        thumbnail.scheme != 'https' ||
        !['statics.tver.jp', 'image-cdn.tver.jp'].contains(thumbnail.host)) {
      continue;
    }
    final label = '${episode['broadcastDateLabel'] ?? ''}';
    final date = _broadcastDate(label, now);
    videos[id] = {
      'id': id,
      'title': title,
      'platform': 'tver',
      'url': 'https://tver.jp/episodes/$id',
      'thumbnail_url': thumbnail.toString(),
      'source_name': '${episode['broadcasterName'] ?? 'TVer'}',
      'published_label': label,
      if (date != null) 'published_sort_at': date.toIso8601String(),
      'expires_at': DateTime.fromMillisecondsSinceEpoch(end * 1000, isUtc: true)
          .toIso8601String(),
    };
  }
  return videos.values.toList();
}
