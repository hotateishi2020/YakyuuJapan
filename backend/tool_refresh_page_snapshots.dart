import 'dart:io';
import 'app/PageSnapshot.dart';
import 'app/DisplaySnapshot.dart';
import 'app/OrgLeague.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  try {
    await Postgres.withConnection(PageSnapshot.ensure);
    for (final org in [OrgKind.npb, OrgKind.mlb]) {
      for (final kind in ['schedule', 'records']) {
        final timer = Stopwatch()..start();
        await Postgres.withConnection((conn) => PageSnapshot.refresh(conn, kind: kind, org: org, year: year));
        final readTimer = Stopwatch()..start();
        final data = await Postgres.withConnection((conn) => PageSnapshot.read(conn, kind: kind, org: org, year: year));
        print('${org.code} $year $kind: build=${timer.elapsedMilliseconds}ms read=${readTimer.elapsedMilliseconds}ms saved=${data['updated_at']}');
      }
    }
    await Postgres.withConnection((conn) => DisplaySnapshot.refreshTeams(conn, year));
    exit(0);
  } catch (e) { stderr.writeln(e); exit(1); }
}
