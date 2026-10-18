import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';

/// Apply only explicitly named identities; leave all other colors/logos intact.
Future<void> main(List<String> names) async {
  if (names.isEmpty) throw ArgumentError('更新するチーム名を指定してください');
  final rows = jsonDecode(await File('data/team_identity_visuals.json').readAsString()) as List;
  await Postgres.withConnection((conn) async {
    await conn.execute('BEGIN');
    try {
      for (final name in names) {
        final visual = rows.singleWhere((row) => row['name'] == name);
        if (visual['logo_url'] == null) throw StateError('$name のロゴが未登録です');
        final updated = await conn.execute(
          'UPDATE m_team_season_identity SET logo_url=\$1, updated_at=now() '
          'WHERE name_full=\$2 AND (\$3::integer IS NULL OR int_year<=\$3) RETURNING int_year', parameters: [visual['logo_url'], name, visual['logo_until_year']]);
        print('$name：${updated.length}年度を更新');
      }
      await conn.execute('COMMIT');
    } catch (_) {
      await conn.execute('ROLLBACK');
      rethrow;
    }
  });
  exit(0);
}
