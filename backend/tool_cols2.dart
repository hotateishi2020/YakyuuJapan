import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    for (final t in ['m_player', 'm_team', 'm_league']) {
      final cols = await conn.execute('''
        SELECT column_name FROM information_schema.columns
        WHERE table_name=\$1 ORDER BY ordinal_position
      ''', parameters: [t]);
      print('== $t == ${cols.map((r) => r[0]).join(', ')}');
    }
  });
}
