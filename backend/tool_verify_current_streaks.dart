import 'dart:convert';
import 'dart:io';
import 'app/OrgLeague.dart';
import 'app/Records.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  final data = await Postgres.withConnection(
      (conn) => Records.read(conn, org: OrgKind.npb, year: year));
  final rows = usageMaps(data['streaks']);
  print(jsonEncode({
    'year': year,
    'visible_categories': rows.where((r) => usageMaps(r['current']).isNotEmpty).length,
    'categories': [
      for (final row in rows) {
        'key': row['key'],
        'players': usageMaps(row['current']).length,
        'status': row['current_status'] ?? 'verified',
      }
    ],
  }));
  await stdout.flush();
  exit(0);
}
