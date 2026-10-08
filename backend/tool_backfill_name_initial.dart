import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  print('connecting...');
  await Postgres.withConnection((conn) async {
    print('connected');

    final fromAbbr = await conn.execute(r'''
      WITH src AS (
        SELECT id,
               UPPER(
                 COALESCE(
                   substring(BTRIM(name_full) from '^([A-Za-z]{1,3})[\.．]'),
                   substring(BTRIM(name_last) from '^([A-Za-z]{1,3})[\.．]'),
                   substring(BTRIM(name_first) from '^([A-Za-z]{1,3})[\.．]')
                 )
               ) AS initial
        FROM m_player
        WHERE COALESCE(flg_delete, false) = false
          AND COALESCE(BTRIM(name_first_initial), '') = ''
          AND (
            BTRIM(name_full) ~ '^[A-Za-z]{1,3}[\.．]'
            OR BTRIM(name_last) ~ '^[A-Za-z]{1,3}[\.．]'
            OR BTRIM(name_first) ~ '^[A-Za-z]{1,3}[\.．]'
          )
      )
      UPDATE m_player p
      SET name_first_initial = src.initial, updat = NOW()
      FROM src
      WHERE p.id = src.id AND src.initial IS NOT NULL AND src.initial <> ''
    ''').timeout(const Duration(seconds: 45));
    print('略称名から ${fromAbbr.affectedRows} 件更新');

    final propagated = await conn.execute(r'''
      WITH abbr AS (
        SELECT id_team,
               UPPER(BTRIM(name_first_initial)) AS initial,
               regexp_replace(BTRIM(name_full), '^[A-Za-z]{1,3}[\.．]', '') AS surname
        FROM m_player
        WHERE COALESCE(flg_delete, false) = false
          AND COALESCE(BTRIM(name_first_initial), '') <> ''
          AND BTRIM(name_full) ~ '^[A-Za-z]{1,3}[\.．]'
      ),
      fulln AS (
        SELECT id, id_team,
               split_part(BTRIM(name_full), '・',
                 cardinality(string_to_array(BTRIM(name_full), '・'))
               ) AS surname
        FROM m_player
        WHERE COALESCE(flg_delete, false) = false
          AND COALESCE(BTRIM(name_first_initial), '') = ''
          AND position('・' in BTRIM(name_full)) > 0
          AND BTRIM(name_full) !~ '^[A-Za-z]{1,3}[\.．]'
      ),
      picked AS (
        SELECT DISTINCT ON (f.id) f.id, a.initial
        FROM fulln f
        JOIN abbr a ON a.id_team = f.id_team AND a.surname = f.surname
        WHERE a.initial <> ''
        ORDER BY f.id
      )
      UPDATE m_player p
      SET name_first_initial = picked.initial, updat = NOW()
      FROM picked
      WHERE p.id = picked.id
    ''').timeout(const Duration(seconds: 45));
    print('フル名へ伝播 ${propagated.affectedRows} 件更新');

    final check = await conn.execute('''
      SELECT count(*) AS total,
             count(NULLIF(BTRIM(COALESCE(name_first_initial,'')), '')) AS with_initial
      FROM m_player WHERE COALESCE(flg_delete,false)=false
    ''').timeout(const Duration(seconds: 20));
    print(check.first.toColumnMap());

    final sample = await conn.execute('''
      SELECT id, id_team, name_full, name_first_initial
      FROM m_player
      WHERE COALESCE(flg_delete,false)=false
        AND (name_full LIKE '%チョウリオ%' OR name_full IN ('ギャビン・ウィリアムズ','ジャクソン・チョウリオ'))
      ORDER BY name_full, id
      LIMIT 20
    ''').timeout(const Duration(seconds: 20));
    for (final row in sample) {
      print(row.toColumnMap());
    }
  }).timeout(const Duration(seconds: 90));
  print('done');
  exit(0);
}
