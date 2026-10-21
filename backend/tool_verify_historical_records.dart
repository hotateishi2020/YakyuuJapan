import 'dart:convert';
import 'dart:io';
import 'app/AdditionalRecords.dart';
import 'app/AllStarHistory.dart';
import 'app/OrgLeague.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  final counts = <String, dynamic>{
    'allstar_players': (readAllStarHistory(2026)['players'] as List).length
  };
  for (final org in [OrgKind.npb, OrgKind.mlb]) {
    final data =
        await Postgres.withConnection((c) => readRegularHistory(c, org, 2026));
    final rows = data;
    counts[org.code] = {
      'team_seasons': rows.length,
      'oldest':
          rows.map((r) => r['year'] as int).reduce((a, b) => a < b ? a : b),
      'latest':
          rows.map((r) => r['year'] as int).reduce((a, b) => a > b ? a : b)
    };
  }
  print(jsonEncode(counts));
  await stdout.flush();
  exit(0);
}
