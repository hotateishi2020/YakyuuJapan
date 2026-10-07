import 'dart:io';

import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''
      SELECT id, name_shortest, name_short, name_full, source_key, color_back, color_font
      FROM m_team
      WHERE COALESCE(name_full,'') LIKE '%近鉄%'
         OR COALESCE(name_short,'') LIKE '%近鉄%'
         OR COALESCE(name_shortest,'') LIKE '%近鉄%'
         OR COALESCE(name_full,'') LIKE '%バファロー%'
         OR source_key = 'npb:franchise:kintetsu'
      ORDER BY id
    ''');
    print('${rows.length} rows');
    for (final row in rows) {
      print(row.toColumnMap());
    }
  });
  exit(0);
}
