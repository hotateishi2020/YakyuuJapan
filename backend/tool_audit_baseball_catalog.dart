import 'dart:io';
import 'app/BaseballCatalog.dart';
import 'app/OrgLeague.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  try {
    await Postgres.withConnection((conn) async {
      for (final org in [OrgKind.npb, OrgKind.mlb]) {
        for (final section in ['stadiums', 'uniforms', 'hall']) {
          final data = await BaseballCatalog.read(conn,
              org: org, year: 2026, section: section);
          stdout.writeln(
              '${org.code}/$section ${data.entries.where((e) => e.value is List).map((e) => '${e.key}:${(e.value as List).length}').join(', ')}');
          if (section == 'uniforms') {
            final rows = data['uniforms'] as List;
            stdout.writeln(
                'unknown status: ${rows.where((r) => r['status'] == 'unknown').length}; unseparated name: ${rows.where((r) => r['surname'] == r['name']).length}');
          }
        }
      }
    });
  } catch (e) {
    stderr.writeln(e.runtimeType);
    exit(1);
  }
  exit(0);
}
