import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/SamuraiSelections.dart';

/// Enrich only the Samurai fields in existing personal-stat snapshots.
Future<void> main(List<String> args) async {
  await Postgres.withConnection((conn) async {
    final years = args.isEmpty
        ? (await conn.execute(
                'SELECT DISTINCT int_year FROM v_stats_player ORDER BY int_year'))
            .map((r) => r[0] as int)
            .toList()
        : args.map(int.parse).toList();
    for (final year in years) {
      final ids = await conn.execute(
          "SELECT DISTINCT (payload->>'id_player')::int FROM v_stats_player WHERE int_year=\$1 AND payload->>'id_player' ~ '^[0-9]+\$'",
          parameters: [year]);
      final rows = [
        for (final id in ids) <String, dynamic>{'id_player': id[0]}
      ];
      await attachSamuraiSelections(conn, year, rows);
      final marks = {
        for (final row in rows.where((r) => r.containsKey('samurai_category')))
          '${row['id_player']}': Map<String, dynamic>.from(row)
            ..remove('id_player')
      };
      await conn.execute(
          "UPDATE v_stats_player SET payload=payload || (\$2::jsonb -> (payload->>'id_player')) WHERE int_year=\$1 AND \$2::jsonb ? (payload->>'id_player')",
          parameters: [year, jsonEncode(marks)]);
      print(
          '$year: ${marks.values.where((r) => r['samurai_category'] != null).length} selected player records / ${marks.length} NPB records');
    }
  });
  exit(0);
}
