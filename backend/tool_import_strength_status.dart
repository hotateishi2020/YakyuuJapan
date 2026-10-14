import 'dart:convert';
import 'dart:io';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

/// dart run tool_import_strength_status.dart verified-status.json
/// Input: [{org,year,id_team,player_key,status_source,status_as_of,
///   contract_end_year?,fa_eligible?,departure_confirmed?,
///   level_appearances?: {"1":12,"2":30,"3":40,"4":0},level_coverage?:[1,2,3,4]}]
/// Confirmed facts only; omit unknown values. A source URL and date are mandatory.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('確認済み情報のJSONファイルを指定してください');
    exit(2);
  }
  try {
    final raw = jsonDecode(await File(args.single).readAsString());
    if (raw is! List || raw.isEmpty) throw FormatException('空でない配列を指定してください');
    final records = usageMaps(raw);
    if (records.length != raw.length)
      throw FormatException('各項目はオブジェクトで指定してください');
    const allowed = {
      'contract_end_year',
      'fa_eligible',
      'departure_confirmed',
      'level_appearances',
      'level_coverage',
      'status_source',
      'status_as_of'
    };
    for (final row in records) {
      if (!['npb', 'mlb'].contains(row['org']) ||
          usageInt(row['year']) < 2005 ||
          usageInt(row['id_team']) <= 0 ||
          !'${row['player_key']}'.startsWith('${row['org']}:'))
        throw FormatException('団体・年度・球団・選手キーが不正です');
      final uri = Uri.tryParse('${row['status_source']}');
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          DateTime.tryParse('${row['status_as_of']}') == null)
        throw FormatException('出典HTTPS URLと確認日が必要です');
      for (final key in ['fa_eligible', 'departure_confirmed']) {
        if (row.containsKey(key) && row[key] is! bool)
          throw FormatException('$keyは真偽値で指定してください');
      }
      if (row.containsKey('contract_end_year') &&
          (row['contract_end_year'] is! int ||
              usageInt(row['contract_end_year']) < usageInt(row['year'])))
        throw FormatException('契約満了年が不正です');
      if (row.containsKey('level_appearances')) {
        final levels = row['level_appearances'];
        final coverage = row['level_coverage'];
        if (levels is! Map ||
            coverage is! List ||
            coverage.isEmpty ||
            levels.entries.any((e) =>
                !['1', '2', '3', '4'].contains('${e.key}') ||
                e.value is! int ||
                (e.value as int) < 0) ||
            coverage.any(
                (n) => ![1, 2, 3, 4].contains(n) || !levels.containsKey('$n')))
          throw FormatException('各軍出場数と確認範囲が不正です');
      }
      if (row.keys.any((k) =>
          !allowed.contains(k) &&
          !['org', 'year', 'id_team', 'player_key'].contains(k)))
        throw FormatException('未対応の項目があります');
    }
    await StrengthUsage.ensure();
    await Postgres.withConnection((conn) => conn.runTx((tx) async {
          for (final row in records) {
            final payload = {
              for (final key in allowed)
                if (row.containsKey(key)) key: row[key]
            };
            final found = await tx.execute(
                'SELECT 1 FROM t_team_strength t,jsonb_array_elements(t.payload->\'roster\') p WHERE t.code_org=\$1 AND t.int_year=\$2 AND t.id_team=\$3 AND p->>\'player_key\'=\$4',
                parameters: [
                  row['org'],
                  row['year'],
                  row['id_team'],
                  row['player_key']
                ]);
            if (found.isEmpty)
              throw StateError('対象年度・球団の名簿に選手がいません: ${row['player_key']}');
            await tx
                .execute('''INSERT INTO t_strength_player_status(code_org,int_year,id_team,player_key,payload)
          VALUES(\$1,\$2,\$3,\$4,\$5::jsonb)
          ON CONFLICT(code_org,int_year,id_team,player_key) DO UPDATE SET payload=t_strength_player_status.payload||EXCLUDED.payload,updated_at=NOW()''',
                    parameters: [
                  row['org'],
                  row['year'],
                  row['id_team'],
                  row['player_key'],
                  jsonEncode(payload)
                ]);
            await tx
                .execute('''UPDATE t_team_strength SET payload=jsonb_set(payload,'{roster}',
          (SELECT jsonb_agg(CASE WHEN p->>'player_key'=\$4 THEN p||\$5::jsonb ELSE p END)
           FROM jsonb_array_elements(payload->'roster') p)),updated_at=NOW()
          WHERE code_org=\$1 AND int_year=\$2 AND id_team=\$3''', parameters: [
              row['org'],
              row['year'],
              row['id_team'],
              row['player_key'],
              jsonEncode(payload)
            ]);
          }
        }));
    print('確認済み選手情報を${records.length}件登録しました');
    exit(0);
  } catch (error) {
    stderr.writeln('選手情報登録失敗: $error');
    exit(1);
  }
}
