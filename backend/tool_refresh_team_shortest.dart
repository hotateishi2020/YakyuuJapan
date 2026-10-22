import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  final file = File('data/team_identity_visuals.json');
  final identities = jsonDecode(await file.readAsString()) as List;
  await Postgres.withConnection((conn) async {
    await conn.execute('BEGIN');
    try {
      var updated = 0;
      for (final identity in identities) {
        final parameters = [identity['name_shortest'], identity['name']];
        for (final target in [
          ('m_team_season_identity', 'name_full'),
          ('t_stats_team', 'name_team'),
          ('m_team', 'name_full')
        ]) {
          final result = await conn.execute(
              'UPDATE ${target.$1} SET name_shortest=\$1 WHERE trim(${target.$2})=\$2 AND name_shortest IS DISTINCT FROM \$1 RETURNING name_shortest',
              parameters: parameters);
          updated += result.length;
        }
      }
      final check = await conn.execute(
          "SELECT DISTINCT name_full,name_shortest FROM m_team_season_identity WHERE name_full LIKE '%ダイエー%' OR name_full LIKE '%近鉄%' ORDER BY name_full");
      for (final row in check) {
        print(row.toColumnMap());
      }
      await conn.execute('COMMIT');
      print('Updated $updated shortest-name rows.');
    } catch (_) {
      await conn.execute('ROLLBACK');
      rethrow;
    }
  });
  exit(0);
}
