import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final names = args.isNotEmpty ? args : [
    '西鉄ライオンズ',
    'ロッキーズ', 'コロラド・ロッキーズ', 'コロラドロッキーズ',
    'オリックス・バファローズ', 'オリックスバファローズ',
    'オリックス・ブルーウェーブ', 'オリックスブルーウェーブ',
  ];
  await Postgres.withConnection((conn) async {
    await conn.execute('BEGIN');
    try {
      final historical = await conn.execute(
        "UPDATE m_team_season_identity SET color_font='#FFFFFF', updated_at=now() "
        'WHERE name_full=ANY(\$1::text[]) RETURNING int_year', parameters: [names]);
      final current = await conn.execute(
        "UPDATE m_team SET color_font='#FFFFFF' "
        'WHERE name_full=ANY(\$1::text[]) OR name_short=ANY(\$1::text[]) RETURNING id',
        parameters: [names]);
      await conn.execute('COMMIT');
      print('白文字に更新：年度別 ${historical.length}件、球団マスター ${current.length}件');
    } catch (_) {
      await conn.execute('ROLLBACK');
      rethrow;
    }
  });
  exit(0);
}
