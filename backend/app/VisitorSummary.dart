import 'dart:convert';
import 'LogDetail.dart';

/// Client activity only: jobs and server requests are not visits.
Map<String, int> visitorSummary(Iterable<Map<String, dynamic>> rows, DateTime now) {
  final visitors = {for (final days in [1, 7, 30]) days: <String>{}};
  for (final row in rows) {
    final id = int.tryParse('${row['crtby']}') ?? 0;
    if (id == 1 || id == 2 || id < 0) continue;
    final at = row['crtat'] is DateTime ? row['crtat'] as DateTime : DateTime.tryParse('${row['crtat']}');
    if (at == null || at.isAfter(now)) continue;
    final detail = LogDetail.decode(row['txt_detail']);
    final ip = '${detail['ip_address'] ?? ''}'.trim();
    final ua = '${detail['user_agent'] ?? ''}'.trim();
    final environment = ua.isNotEmpty ? ua : '${detail['browser'] ?? ''}|${detail['device_type'] ?? ''}';
    if (id == 0 && (ip.isEmpty || environment == '|')) continue;
    final key = id > 0 ? 'user:$id' : jsonEncode([ip, environment, detail['environment'] ?? 'web']);
    for (final entry in visitors.entries) {
      if (!at.isBefore(now.subtract(Duration(days: entry.key)))) entry.value.add(key);
    }
  }
  return {for (final entry in visitors.entries) '${entry.key}': entry.value.length};
}
