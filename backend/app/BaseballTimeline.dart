import 'dart:convert';
import 'dart:io';

const timelineCategories = ['rules', 'recruitment', 'records', 'incidents', 'international'];

/// Offline verified catalog. Reading the records screen never crawls sources.
List<Map<String, dynamic>> readBaseballTimeline(String org, int year) {
  final file = [File('data/baseball-timeline.json'), File('backend/data/baseball-timeline.json')]
      .where((file) => file.existsSync()).firstOrNull;
  if (file == null) return [];
  return filterBaseballTimeline(jsonDecode(file.readAsStringSync()) as List, org, year);
}

List<Map<String, dynamic>> filterBaseballTimeline(List entries, String org, int year) => [
  for (final raw in entries)
    if (raw is Map && raw['org'] == org && raw['year'] is int && raw['year'] <= year &&
        timelineCategories.contains(raw['category'])) Map<String, dynamic>.from(raw),
];
