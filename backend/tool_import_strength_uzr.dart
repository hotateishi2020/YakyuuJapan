import 'dart:convert';
import 'dart:io';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

/// dart run tool_import_strength_uzr.dart file.json
/// [{"org":"npb","year":2026,"id_team":1,"player_key":"npb:123",
/// "position":"SS","uzr":1.2,"source_url":"https://...","as_of":"2026-10-10"}]
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('UZRデータのJSONファイルを指定してください');
  final rows = usageMaps(jsonDecode(File(args.single).readAsStringSync()));
  if (rows.isEmpty) throw ArgumentError('データが空です');
  await Postgres.withConnection((conn) => conn.runTx((tx) async {
        for (final row in rows) {
          final value = double.tryParse('${row['uzr']}');
          final source = Uri.tryParse('${row['source_url']}');
          if (!['npb', 'mlb'].contains(row['org']) || usageInt(row['year']) < 2005 || value == null || !value.isFinite || source == null || !['http', 'https'].contains(source.scheme) || DateTime.tryParse('${row['as_of']}') == null || !['C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF'].contains(row['position'])) {
            throw ArgumentError('年度・UZR・守備位置・出典・基準日を確認してください');
          }
          final found = await tx.execute('SELECT payload FROM t_team_strength WHERE code_org=\$1 AND int_year=\$2 AND id_team=\$3 FOR UPDATE', parameters: [row['org'], row['year'], row['id_team']]);
          if (found.length != 1) throw StateError('球団データがありません');
          final team = usageMap(found.single[0]);
          if (!usageMaps(team['roster']).any((p) => p['player_key'] == row['player_key'])) {
            throw StateError('選手IDが名簿にありません');
          }
          final fields = usageMaps(team['fielding_metrics']);
          final old = fields.where((p) => p['player_key'] == row['player_key']).firstOrNull;
          final next = {
            ...?(old),
            'player_key': row['player_key'],
            'uzr_by_position': {...usageMap(old?['uzr_by_position']), '${row['position']}': value},
            'source_url': row['source_url'],
            'as_of': row['as_of']
          };
          fields.removeWhere((p) => p['player_key'] == row['player_key']);
          fields.add(next);
          await tx.execute('UPDATE t_team_strength SET payload=payload || \$1::jsonb WHERE code_org=\$2 AND int_year=\$3 AND id_team=\$4', parameters: [
            jsonEncode({'fielding_metrics': fields}),
            row['org'],
            row['year'],
            row['id_team']
          ]);
        }
      }));
  print('${rows.length}件のUZRを登録しました');
  exit(0);
}
