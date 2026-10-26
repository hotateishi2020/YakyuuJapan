import 'dart:convert';
import 'dart:io';
import 'app/OrgLeague.dart';
import 'app/Records.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.first);
  final org = OrgKind.parse(args.length > 1 ? args[1] : 'npb');
  final data = await Postgres.withConnection((conn) => Records.read(conn, org: org, year: year, force: true));
  final rows = [for (final row in usageMaps(data['streaks'])) {
    for (final key in ['key','label','current','current_status','current_label','current_message','current_note'])
      if (row.containsKey(key)) key: row[key],
  }];
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(rows));
  await stdout.flush();
  exit(0);
}
