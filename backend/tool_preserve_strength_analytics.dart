import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  final sql = File('sql_preserve_strength_analytics.sql').readAsStringSync();
  final split = sql.indexOf('CREATE OR REPLACE TRIGGER');
  await Postgres.withConnection((c) => c.runTx((tx) async {
        await tx.execute(sql.substring(0, split));
        await tx.execute(sql.substring(split));
      }));
  print('戦力の追加成績・契約データを更新時に保持する保護を適用しました。');
}
