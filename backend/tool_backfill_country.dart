import 'dart:io';

import 'app/FetchMLB.dart';
import 'tools/Postgres.dart';

/// Yahoo「MLB日本人選手」一覧から国籍を補完する。
///   cd backend && dart run tool_backfill_country.dart
Future<void> main() async {
  print('backfill start');
  await Postgres.withConnection((conn) async {
    final n = await FetchMLB.syncJapanesePlayers(conn);
    print('updated=$n');
  }).timeout(const Duration(seconds: 180));
  print('done');
  exit(0);
}
