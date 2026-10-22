import 'package:postgres/postgres.dart';
import 'ClubData.dart';
import 'StrengthUsage.dart';

const samuraiCategoryPriority = ['wbc', 'olympics', 'premier12', 'other'];

/// Match both name and birthday so namesakes never inherit a selection.
Map<String, dynamic> samuraiSelectionDisplay(
    Map<String, dynamic> player, Iterable<Map<String, dynamic>> selections,
    {required int year}) {
  final name = usageName('${player['name_full'] ?? ''}');
  final birth = '${player['date_birth'] ?? ''}'.split(' ').first;
  final eligible = selections
      .where((s) =>
          name.isNotEmpty &&
          birth.isNotEmpty &&
          usageName('${s['name']}') == name &&
          '${s['birth_date']}' == birth &&
          usageInt(s['year']) <= year &&
          samuraiCategoryPriority.contains(s['category']))
      .toList();
  final categories = samuraiCategoryPriority
      .where((c) => eligible.any((s) => s['category'] == c))
      .toList();
  return {
    'samurai_category': categories.firstOrNull,
    'samurai_selections': [
      for (final category in categories)
        {
          'category': category,
          'years': (eligible
              .where((s) => s['category'] == category)
              .map((s) => usageInt(s['year']))
              .toSet()
              .toList()
            ..sort()),
        },
    ],
  };
}

Future<void> attachSamuraiSelections(
    Connection conn, int year, List<Map<String, dynamic>> rows) async {
  final ids = rows
      .map((r) => usageInt(r['id_player'] ?? r['id']))
      .where((id) => id > 0)
      .toSet()
      .toList();
  if (ids.isEmpty) return;
  final people = await conn
      .execute('''SELECT p.id,p.id_team,p.name_full,p.date_birth::date::text
    FROM m_player p JOIN m_team t ON t.id=p.id_team
    WHERE t.id_league IN (1,2) AND p.id=ANY(\$1::int[])''', parameters: [ids]);
  // Older Yahoo identities lack birthdays. Resolve them only against a unique
  // official roster identity in the same club; never infer from a surname.
  final roster = (await conn.execute(
          "SELECT t.id_team,p->>'name' AS name,p->>'date_birth' AS date_birth FROM t_team_strength t CROSS JOIN LATERAL jsonb_array_elements(COALESCE(t.payload->'roster','[]'::jsonb)) p WHERE t.int_year=\$1 AND t.code_org='npb'",
          parameters: [year]))
      .map((r) => r.toColumnMap())
      .toList();
  final resolved = people.map((r) => r.toColumnMap()).toList();
  for (final p in resolved) {
    if (p['date_birth'] != null) continue;
    final births = roster
        .where((r) =>
            r['id_team'] == p['id_team'] &&
            usageName('${r['name']}') == usageName('${p['name_full']}'))
        .map((r) => r['date_birth'])
        .whereType<String>()
        .where((b) => b.isNotEmpty)
        .toSet();
    if (births.length == 1) p['date_birth'] = births.single;
  }
  final selections =
      usageMaps(readClubFile('samurai_selections.json')['selections']);
  final marks = {
    for (final row in resolved)
      row['id']: samuraiSelectionDisplay(row, selections, year: year)
  };
  for (final row in rows) {
    final mark = marks[usageInt(row['id_player'] ?? row['id'])];
    if (mark != null) row.addAll(mark);
  }
}
