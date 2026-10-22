import 'dart:convert';
import 'dart:io';
import 'app/QualifiedBattingMetrics.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final stored = await conn.execute(
        "SELECT int_year,row_no,payload FROM v_stats_player WHERE payload->>'title'='得点圏打率'");
    final byYear = <int, List<Map<String, dynamic>>>{};
    for (final row in stored) {
      final payload = row[2] is String ? jsonDecode(row[2] as String) : row[2];
      byYear.putIfAbsent(row[0] as int, () => []).add(
          {...Map<String, dynamic>.from(payload as Map), '_row_no': row[1]});
    }
    await conn.runTx((tx) async {
      for (final entry in byYear.entries) {
        final before = entry.value.length;
        retainQualifiedRisp(entry.value);
        final updates = {
          for (final p in entry.value)
            '${p['_row_no']}': Map<String, dynamic>.from(p)..remove('_row_no')
        };
        await tx.execute(
            "DELETE FROM v_stats_player WHERE int_year=\$1 AND payload->>'title'='得点圏打率' AND NOT (\$2::jsonb ? row_no::text)",
            parameters: [entry.key, jsonEncode(updates)]);
        await tx.execute(
            "UPDATE v_stats_player SET payload=\$2::jsonb -> row_no::text WHERE int_year=\$1 AND payload->>'title'='得点圏打率' AND \$2::jsonb ? row_no::text",
            parameters: [entry.key, jsonEncode(updates)]);
        print(
            '${entry.key}: RISP $before -> ${entry.value.length} qualified players');
      }
    });
  });
  exit(0);
}
