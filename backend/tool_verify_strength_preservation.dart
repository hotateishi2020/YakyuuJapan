import 'tools/Postgres.dart';

// Exercise an old worker's full replacement and an empty fetch, then roll back.
Future<void> main() async {
  final rollback = Object();
  var verified = false;
  try {
    await Postgres.withConnection((c) => c.runTx((tx) async {
          final before = await tx.execute("""
        SELECT int_year, code_org, id_team, payload FROM t_team_strength
        WHERE jsonb_array_length(payload->'batting_stats') > 0
          AND jsonb_array_length(payload->'contracts') > 0
        ORDER BY code_org DESC, id_team LIMIT 1 FOR UPDATE
      """);
          if (before.isEmpty) throw StateError('検証用の成績・契約データがありません');
          final row = before.single;
          final result = await tx.execute("""
        UPDATE t_team_strength SET payload =
          (payload - 'batting_stats' - 'contracts' - 'metrics_updated_at') || '{"pitching_stats": []}'::jsonb
        WHERE int_year=\$1 AND code_org=\$2 AND id_team=\$3
        RETURNING payload = \$4::jsonb
      """, parameters: [row[0], row[1], row[2], row[3]]);
          if (result.single[0] != true) throw StateError('更新で成績・契約データが変わりました');
          verified = true;
          throw rollback;
        }));
  } catch (error) {
    if (!identical(error, rollback)) rethrow;
  }
  if (!verified) throw StateError('未検証');
  print('欠落・空配列による更新でも保存済みデータを維持。検証更新はロールバック済み。');
}
