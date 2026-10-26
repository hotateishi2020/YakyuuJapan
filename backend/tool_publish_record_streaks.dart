import 'dart:convert';
import 'dart:io';
import 'app/OrgLeague.dart';
import 'app/PageSnapshot.dart';
import 'app/PlayerIdentity.dart';
import 'app/RecordStreaks.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

/// Publish audited streaks only; preserve all other saved records-page sections.
/// Usage: dart run tool_publish_record_streaks.dart YEAR BACKUP_DIRECTORY
Future<void> main(List<String> args) async {
  final year = int.parse(args[0]);
  final backup = Directory(args[1])..createSync(recursive: true);
  final bundled = usageMap(jsonDecode(File('data/records.json').readAsStringSync()));
  await Postgres.withConnection((conn) async {
    for (final org in [OrgKind.npb, OrgKind.mlb]) {
      final expected = usageMap(usageMap(usageMap(bundled[org.code])['current_streaks'])['$year']);
      final categories = usageMap(expected['categories']);
      if (categories.length != 15 || usageMap(expected['records']).length != 15) {
        throw StateError('Incomplete audited snapshot for ${org.code}');
      }
      final saved = await PageSnapshot.read(conn, kind: 'records', org: org, year: year);
      if (saved['pending'] == true) throw StateError('No existing records snapshot');
      final before = File('${backup.path}/${org.code}-$year-before.json');
      if (!before.existsSync()) before.writeAsStringSync(jsonEncode(saved));
      var streaks = [for (final row in usageMaps(saved['streaks'])) {
        for (final entry in row.entries)
          if (entry.key != 'current' && !entry.key.startsWith('current_')) entry.key: entry.value,
        ...seasonStreakPresentation(
          observed: usageMaps(usageMap(expected['records'])[row['key']]),
          official: true, completedGames: 0, loadedGames: 0,
          audit: usageMap(categories[row['key']])),
        'current_note': '${expected['note']} ${usageMap(categories[row['key']])['note']} 確認日：${expected['checked_at']}',
      }];
      if (org == OrgKind.mlb) streaks = usageMaps(await PlayerIdentity.localize(conn, streaks));
      if (streaks.length != 15 || streaks.any((r) =>
          !['verified','unavailable'].contains(r['current_status']))) {
        throw StateError('Rebuilt snapshot has unaudited categories');
      }
      await PageSnapshot.refresh(conn, kind: 'records', org: org, year: year,
        build: () async => {...saved, 'streaks': streaks}..remove('updated_at'));
      final published = await PageSnapshot.read(conn, kind: 'records', org: org, year: year);
      if (jsonEncode(published['streaks']) != jsonEncode(streaks)) {
        // JSONB may reorder object keys; compare through canonical recursive maps.
        String canonical(dynamic value) {
          if (value is Map) {
            final keys = value.keys.map((k) => '$k').toList()..sort();
            return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(value[k])}').join(',')}}';
          }
          if (value is List) return '[${value.map(canonical).join(',')}]';
          return jsonEncode(value);
        }
        if (canonical(published['streaks']) != canonical(streaks)) {
          throw StateError('Saved streak verification failed for ${org.code}');
        }
      }
      File('${backup.path}/${org.code}-$year-after.json').writeAsStringSync(jsonEncode(published['streaks']));
      print('${org.code} $year: published ${streaks.where((r) => r['current_status']=='verified').length} verified / ${streaks.length} categories; read-back matched');
    }
  });
  exit(0);
}
