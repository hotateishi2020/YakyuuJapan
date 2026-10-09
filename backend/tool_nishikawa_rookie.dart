import 'dart:io';

import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''
      SELECT p.id, p.name_full, p.flg_rookie,
             c.int_year, c.int_games, c.int_appearance, c.double_inning, t.id_league, t.name_short
      FROM m_player p
      LEFT JOIN m_player_career c ON c.id_player = p.id AND COALESCE(c.flg_delete, FALSE) = FALSE
      LEFT JOIN m_team t ON t.id = c.id_team
      WHERE replace(replace(p.name_full, ' ', ''), '　', '') LIKE '%西川史礁%'
      ORDER BY c.int_year
    ''').timeout(const Duration(seconds: 20));
    for (final row in rows) {
      stdout.writeln(row.toColumnMap());
    }
  });
  exit(0);
}
