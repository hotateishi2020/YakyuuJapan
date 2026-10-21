import 'dart:convert';
import 'dart:io';
import 'app/PageSnapshot.dart';
import 'app/OrgLeague.dart';
import 'tools/Postgres.dart';
Future<void> main() async {
  for (final org in [OrgKind.npb, OrgKind.mlb]) {
    for (final section in ['titles','timeline']) {
      final watch = Stopwatch()..start();
      final data = await Postgres.withConnection((conn) => PageSnapshot.read(conn,
        kind: 'records', org: org, year: DateTime.now().year, section: section));
      print('${org.code} $section: ${watch.elapsedMilliseconds}ms ${utf8.encode(jsonEncode(data)).length} bytes pending=${data['pending'] == true}');
    }
  }
  exit(0);
}
