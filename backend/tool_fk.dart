import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final fk = await conn.execute('''
      SELECT tc.constraint_name, kcu.column_name, ccu.table_name AS foreign_table, ccu.column_name AS foreign_column
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
      JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name
      WHERE tc.table_name='m_player' AND tc.constraint_type='FOREIGN KEY'
    ''').timeout(const Duration(seconds: 15));
    for (final r in fk) print(r.toColumnMap());
    // create place table
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS m_place_birth (
        id SERIAL PRIMARY KEY,
        name character varying NOT NULL,
        id_country integer REFERENCES m_country(id),
        flg_delete boolean DEFAULT false,
        crtat timestamp with time zone DEFAULT NOW(),
        crtby integer DEFAULT 0,
        crtenv text DEFAULT '',
        crtpgm character varying DEFAULT '',
        updat timestamp with time zone DEFAULT NOW(),
        updby integer DEFAULT 0,
        updenv text DEFAULT '',
        updpgm character varying DEFAULT ''
      )
    ''').timeout(const Duration(seconds: 15));
    print('m_place_birth created/exists');
    // seed Japan
    await conn.execute('''
      INSERT INTO m_country (name, emoji, flg_delete, crtby, crtenv, crtpgm, updby, updenv, updpgm)
      SELECT '日本', '🇯🇵', false, 0, 'BirthPlaceRegistry', 'BirthPlaceRegistry', 0, 'BirthPlaceRegistry', 'BirthPlaceRegistry'
      WHERE NOT EXISTS (SELECT 1 FROM m_country WHERE name = '日本' AND COALESCE(flg_delete,false)=false)
    ''').timeout(const Duration(seconds: 15));
    final c = await conn.execute("SELECT id,name,emoji FROM m_country").timeout(const Duration(seconds:10));
    for (final r in c) print(r.toColumnMap());
  });
}
