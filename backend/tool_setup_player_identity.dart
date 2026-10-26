import 'dart:io';
import 'package:postgres/postgres.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  await Postgres.withConnection((conn) async {
    await conn.runTx((tx) async {
      await tx.execute("SET LOCAL lock_timeout='5s'");
      var sql=File('sql/player_identity.sql').readAsStringSync();
      if(args.contains('--functions-only')) {sql=RegExp(r'CREATE OR REPLACE FUNCTION[\s\S]*?\$\$;').allMatches(sql).map((m)=>m[0]!).join('\n');}
      await tx.execute(sql,queryMode: QueryMode.simple);
    });
    print(
        'Player identity columns, name retention trigger, registration function installed.');
  });
  exit(0);
}
