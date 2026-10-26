import 'package:postgres/postgres.dart';

/// Read registered birthdays using the same Japan date as the HOME dashboard.
Future<List<Map<String, dynamic>>> homeBirthdays(Connection conn, String today) async {
  final rows = await conn.execute(r'''
    SELECT p.id, p.name_full, t.name_short, p.id_team, t.id_league,
      EXTRACT(YEAR FROM AGE($1::date, p.date_birth::date))::int AS age
    FROM m_player p
    JOIN m_team t ON t.id = p.id_team
    WHERE t.id_league IN (1, 2, 3, 4)
      AND NOT COALESCE(p.flg_delete, false)
      AND p.merged_into_player_id IS NULL
      AND (COALESCE(p.year_retire, 0) = 0 OR p.year_retire >= EXTRACT(YEAR FROM $1::date))
      AND p.date_birth::date <= $1::date
      AND EXTRACT(MONTH FROM p.date_birth) = EXTRACT(MONTH FROM $1::date)
      AND EXTRACT(DAY FROM p.date_birth) = EXTRACT(DAY FROM $1::date)
    ORDER BY t.id_league, t.id, p.name_full, p.id
  ''', parameters: [today]);
  return [for (final row in rows) {
    'id_player': row[0], 'name_player': row[1], 'name_team': row[2],
    'id_team': row[3], 'id_league': row[4],
    'org': (row[4] as int) <= 2 ? 'npb' : 'mlb', 'age': row[5],
  }];
}
