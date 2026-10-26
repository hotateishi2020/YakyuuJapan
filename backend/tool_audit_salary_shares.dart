import 'dart:convert';
import 'dart:io';
import 'app/StrengthUsage.dart';
import 'app/ContractTransferShares.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.first);
  final evidence = usageMap(jsonDecode(contractTransferFile(year).readAsStringSync()));
  await Postgres.withConnection((c) async {
    final rows = await c.execute('SELECT code_org,payload FROM t_team_strength WHERE int_year=\$1', parameters: [year]);
    for (final org in ['npb', 'mlb']) {
      final moves = usageMaps(usageMap(evidence[org])['moves']);
      final keys = moves.map((m) => m['player_key']).toSet();
      final matched = <String>{}, missing = <String>{}, seen = <String>{};
      for (final row in rows.where((r) => r[0] == org)) {
        final payload = usageMap(row[1] is String ? jsonDecode(row[1] as String) : row[1]);
        for (final r in usageMaps(payload['contracts'])) {
          final key = '${r['player_key']}';
          if (!keys.contains(key)) continue;
          seen.add(key);
          final salaries = usageMaps(r['salary_history']).where((s) => s['year'] == year);
          if (salaries.any((s) => usageMaps(s['team_shares']).length > 1)) {
            matched.add(key);
          } else {
            missing.add(key);
          }
        }
      }
      missing.removeAll(matched);
      print('$org 分割済み${matched.length}人 / 年俸等不足${missing.length}人 / 契約データ未取得${keys.difference(seen).length}人');
      print('不足: ${moves.where((m) => missing.contains(m['player_key']) || (org == 'npb' && !seen.contains(m['player_key']))).map((m) => '${m['player_key']} ${m['name']}').toSet().join('、')}');
    }
  });
  exit(0);
}
