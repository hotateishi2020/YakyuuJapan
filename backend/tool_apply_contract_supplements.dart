import 'dart:convert';
import 'dart:io';
import 'app/StrengthUsage.dart';
import 'app/ContractSupplements.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.first);
  await Postgres.withConnection((c) async {
    await c.runTx((tx) async {
      final rows = await tx.execute(
          'SELECT id_team,code_org,payload FROM t_team_strength WHERE int_year=\$1 FOR UPDATE',
          parameters: [year]);
      var changed = 0;
      for (final row in rows) {
        final payload =
            usageMap(row[2] is String ? jsonDecode(row[2] as String) : row[2]);
        final old = usageMaps(payload['contracts']);
        final updated =
            old.map((r) => supplementContracts('${row[1]}', r)).toList();
        if (jsonEncode(old) == jsonEncode(updated)) continue;
        await tx.execute(
            'UPDATE t_team_strength SET payload=payload || \$1::jsonb, updated_at=NOW() WHERE id_team=\$2 AND code_org=\$3 AND int_year=\$4',
            parameters: [
              jsonEncode({'contracts': updated}),
              row[0],
              row[1],
              year
            ]);
        changed++;
      }
      print('補完更新: $changed球団');
    });
  });
  exit(0);
}
