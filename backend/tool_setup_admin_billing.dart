import 'dart:io';
import 'app/AdminBilling.dart';
import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await AdminBilling.ensure(conn);
    final result = await conn.execute("SELECT to_regclass('public.t_admin_billing') IS NOT NULL");
    if (result.single[0] != true) throw StateError('Billing table not found');
    print('管理者用の月次費用テーブルを確認しました');
  });
  exit(0);
}
