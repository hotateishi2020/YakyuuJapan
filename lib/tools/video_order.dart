// Relative labels provide an approximate ordering only, never a publication date.
DateTime? estimateVideoPublishedAt(String label, DateTime reference) {
  final compact = label.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final match = RegExp(
          r'(\d+)(秒|分|時間|日|週間|か月|ヶ月|年|seconds?|minutes?|hours?|days?|weeks?|months?|years?)(?:前|ago)')
      .firstMatch(compact);
  if (match == null) return null;
  final unit = match[2]!;
  final seconds = switch (unit) {
    '秒' || 'second' || 'seconds' => 1,
    '分' || 'minute' || 'minutes' => 60,
    '時間' || 'hour' || 'hours' => 3600,
    '日' || 'day' || 'days' => 86400,
    '週間' || 'week' || 'weeks' => 604800,
    'か月' || 'ヶ月' || 'month' || 'months' => 2592000,
    '年' || 'year' || 'years' => 31536000,
    _ => 0,
  };
  return reference
      .toUtc()
      .subtract(Duration(seconds: int.parse(match[1]!) * seconds));
}

Map<String, dynamic> withVideoSortTime(
    Map<String, dynamic> video, DateTime reference) {
  if (DateTime.tryParse('${video['published_at']}') != null ||
      DateTime.tryParse('${video['published_sort_at']}') != null) {
    return video;
  }
  final estimated =
      estimateVideoPublishedAt('${video['published_label'] ?? ''}', reference);
  return estimated == null
      ? video
      : {
          ...video,
          'published_sort_at': estimated.toIso8601String(),
        };
}
