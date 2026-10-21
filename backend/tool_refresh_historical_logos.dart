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
          'WHERE name_full=\$2 AND (\$3::integer IS NULL OR int_year<=\$3) AND (\$4::integer IS NULL OR int_year>=\$4) RETURNING int_year', parameters: [visual['logo_url'], name, visual['logo_until_year'], visual['logo_from_year']]);
        print('$name：${updated.length}年度を更新');
      }
      // The timeline reads saved page JSON rather than the identity table.
      // Update only these logos, without rebuilding unrelated statistics or
      // resetting snapshot freshness for the rest of the payload.
      final snapshots = await conn.execute(
          "SELECT int_year,payload->'standings' FROM t_page_snapshot "
          "WHERE kind='records' AND code_org='npb' FOR UPDATE");
      var changedPages = 0;
      for (final snapshot in snapshots) {
        final raw = snapshot[1];
        if (raw == null) continue;
        final seasons = raw is String ? jsonDecode(raw) : raw;
        if (seasons is! List) continue;
        var changed = false;
        for (final season in seasons) {
          final year = int.tryParse('${season['year']}');
          if (year == null) continue;
          for (final league in season['leagues'] as List? ?? []) {
            for (final team in league['teams'] as List? ?? []) {
              final visual = rows.where((v) => names.contains(v['name']) && v['name'] == team['name']).firstOrNull;
              if (visual == null || visual['logo_url'] == null) continue;
              final from = visual['logo_from_year'] as int?;
              final until = visual['logo_until_year'] as int?;
              if ((from != null && year < from) || (until != null && year > until)) continue;
              if (team['logo_url'] != visual['logo_url']) {
                team['logo_url'] = visual['logo_url'];
                changed = true;
              }
            }
          }
        }
        if (changed) {
          await conn.execute(
              "UPDATE t_page_snapshot SET payload=jsonb_set(payload,'{standings}',\$1::jsonb) "
              "WHERE kind='records' AND code_org='npb' AND int_year=\$2",
              parameters: [jsonEncode(seasons), snapshot[0]]);
          changedPages++;
        }
      }
      print('年表の事前集計：$changedPages件を更新');
      await conn.execute('COMMIT');
    } catch (_) {
      await conn.execute('ROLLBACK');
      rethrow;
    }
  });
  exit(0);
}
