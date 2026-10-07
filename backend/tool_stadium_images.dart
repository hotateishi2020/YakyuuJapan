import 'dart:io';

import 'app/StadiumImages.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await conn.execute(
      'ALTER TABLE t_game_details ADD COLUMN IF NOT EXISTS flg_fine_play BOOLEAN NOT NULL DEFAULT FALSE',
    );
    final n = await StadiumImages.seed(conn);
    print('stadium images updated: $n');
    final kintetsu = await conn.execute('''
      UPDATE m_team
      SET color_back = 'crimson', color_font = 'white', updat = NOW()
      WHERE COALESCE(flg_delete, FALSE) = FALSE
        AND (
          source_key = 'npb:franchise:kintetsu'
          OR (
            (COALESCE(name_full, '') LIKE '%近鉄%'
              OR COALESCE(name_short, '') LIKE '%近鉄%'
              OR COALESCE(name_shortest, '') LIKE '%近鉄%')
            AND COALESCE(name_full, '') NOT LIKE '%オリックス%'
          )
        )
      RETURNING id, name_full, color_back, color_font
    ''');
    print('kintetsu rows: ${kintetsu.length}');
    for (final row in kintetsu) {
      print(row.toColumnMap());
    }
    final stadiums = await conn.execute('''
      SELECT id, name_short, path_image_inside, path_image_outside
      FROM m_stadium
      WHERE COALESCE(path_image_outside, '') <> ''
      ORDER BY id
    ''');
    for (final row in stadiums) {
      print(row.toColumnMap());
    }
  });
  exit(0);
}
