import 'app/ContractTransferShares.dart';
import 'dart:convert';
import 'dart:io';
import 'app/ContractSalaryShares.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.first);
  final evidence = args.contains('--cached') ? usageMap(jsonDecode(contractTransferFile(year).readAsStringSync())) : await refreshContractTransfers(year);
  for (final org in ['npb', 'mlb']) { print('$org 移籍履歴: ${usageMaps(usageMap(evidence[org])['moves']).length}件'); }
  await Postgres.withConnection((c) async {
    await c.runTx((tx) async {
      final rows = await tx.execute('SELECT id_team,code_org,payload FROM t_team_strength WHERE int_year=\$1 FOR UPDATE', parameters: [year]);
      final known = <String,List<Map<String,dynamic>>>{};
      for(final row in rows) {
        final payload=usageMap(row[2] is String?jsonDecode(row[2] as String):row[2]);
        known.putIfAbsent('${row[1]}',()=>[]).addAll(usageMaps(payload['contracts']).map((r)=>supplementTransferShares('${row[1]}',supplementSalaryShares('${row[1]}',r))));
      }
      var changed = 0;
      for (final row in rows) {
        final payload = usageMap(row[2] is String ? jsonDecode(row[2] as String) : row[2]);
        final old = usageMaps(payload['contracts']);
        final updated = shareTransferredContracts(old.map((r) => supplementTransferShares('${row[1]}', supplementSalaryShares('${row[1]}', r))).toList(), usageMaps(payload['roster']), known['${row[1]}'] ?? [], year);
        if (jsonEncode(old) == jsonEncode(updated)) continue;
        await tx.execute('UPDATE t_team_strength SET payload=payload || \$1::jsonb,updated_at=NOW() WHERE id_team=\$2 AND code_org=\$3 AND int_year=\$4', parameters: [jsonEncode({'contracts': updated}),row[0],row[1],year]);
        final allocated = updated.where((r) => usageMaps(r['salary_history']).any((s) => s['year'] == year && usageMaps(s['team_shares']).length > 1)).toList();
        print('${row[1]} 球団 ${row[0]}: ${allocated.length}人 ${allocated.map((r) => r['name']).join('、')}');
        changed++;
      }
      print('負担額更新: $changed球団');
    });
  });
  exit(0);
}
