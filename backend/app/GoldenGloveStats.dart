import 'SeasonAwards.dart';
import 'package:postgres/postgres.dart';

final _cachedAwards =
    <int, ({DateTime at, Map<String, Map<String, dynamic>> rows})>{};

String _name(dynamic value) => '$value'.replaceAll(RegExp(r'[\s　・･]'), '');

List<Map<String, dynamic>> goldenGloveRows(
    int year, List<Map<String, dynamic>> people,
    {Map<int, List<Map<String, dynamic>>>? awards, bool pitching = false}) {
  final cached = _cachedAwards[year];
  final useCache = awards == null &&
      cached != null &&
      DateTime.now().difference(cached.at).inMinutes < 5;
  final latest = useCache ? cached.rows : <String, Map<String, dynamic>>{};
  if (!useCache) {
    for (var y = 1972; y <= year; y++) {
      final pages =
          awards == null ? SeasonAwards.read(y, refresh: false)['pages'] : null;
      final rows = awards?[y] ??
          (pages is Map
              ? pages.values
                  .whereType<List>()
                  .expand((v) => v)
                  .whereType<Map>()
                  .map((r) => Map<String, dynamic>.from(r))
                  .toList()
              : <Map<String, dynamic>>[]);
      for (final r in rows.where((r) => r['key'] == 'glove')) {
        // Official cumulative counts avoid undercounting when old archives are absent.
        if (r['career_count'] == null) continue;
        latest['${r['source_player_id'] ?? _name(r['name'])}'] = r;
      }
    }
    if (awards == null) {
      if (_cachedAwards.length >= 2) {
        _cachedAwards.remove(_cachedAwards.keys.first);
      }
      _cachedAwards[year] = (at: DateTime.now(), rows: latest);
    }
  }
  final result = <Map<String, dynamic>>[];
  for (final p in people.where((p) => p['active_season'] == year && [1, 2].contains(p['id_league']))) {
    final id = p['official_source_player_id']?.toString() ??
        RegExp(r'/players/(\d+)\.html').firstMatch('${p['url']}')?[1];
    final matches = latest.values
        .where((r) => id != null && r['source_player_id'] != null
            ? '${r['source_player_id']}' == id
            : _name(r['name']) == _name(p['name_full']))
        .toList();
    if (matches.length != 1) continue;
    final award = matches.single;
    final isPitcher = '${p['txt_position'] ?? ''}'.contains('投手') ||
        '${award['detail'] ?? ''}'.contains('投手');
    if (isPitcher != pitching) continue;
    result.add({
      ...p,
      'id_player': p['id'],
      'name_player': p['name_full'],
      'int_year': year,
      'title': 'GG受賞回数',
      'flg_pitcher': pitching,
      if (pitching) 'txt_position': '投手',
      'numeric_value': award['career_count'],
      'stats': '${award['career_count']}',
      'id_users': null,
      'colors_user': null,
      'colors': null,
      'id_stats': null,
      'int_rank': 1000,
      'source': award['source']
    });
  }
  return result;
}


/// A historical club assignment is evidence of activity only in that season.
/// The roster also includes active players with no first-team appearances.
Future<List<Map<String, dynamic>>> goldenGloveSeasonPlayers(
    Connection conn, int year, List<int> leagues) async {
  final rows = await conn.execute(r"""
    WITH roster AS MATERIALIZED (
      SELECT ts.id_team,r->>'source_player_id' AS source_id,
        regexp_replace(r->>'name','[[:space:]　]+','','g') AS name
      FROM t_team_strength ts
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(ts.payload->'roster','[]'::jsonb)) r
      WHERE ts.int_year=$1
    ), season_members AS (
      SELECT c.id_player, c.id_team, 0 AS priority, c.id AS sequence
      FROM m_player_career c
      WHERE c.int_year=$1 AND NOT COALESCE(c.flg_delete,false)
        AND (COALESCE(c.int_games,0)>0 OR COALESCE(c.int_pitching,0)>0
          OR COALESCE(c.int_appearance,0)>0 OR COALESCE(c.int_batting,0)>0)
      UNION ALL
      SELECT p.id,r.id_team,1,r.id_team FROM roster r JOIN m_player p
        ON substring(p.url from '/players/([0-9]+)\.html')=r.source_id
      WHERE NULLIF(r.source_id,'') IS NOT NULL
      UNION ALL
      SELECT p.id,r.id_team,1,r.id_team FROM roster r JOIN m_player p
        ON p.id_team=r.id_team AND regexp_replace(p.name_full,'[[:space:]　]+','','g')=r.name
    )
    SELECT DISTINCT ON (p.id) p.id,p.name_full,p.url,p.txt_position,
      members.id_team,t.id_league,t.name_shortest AS name_team,t.color_back,t.color_font
    FROM season_members members
    JOIN m_player p ON p.id=members.id_player
    JOIN m_team t ON t.id=members.id_team
    WHERE t.id_league IN (1,2) AND t.id_league=ANY($2::int[])
      AND NOT COALESCE(p.flg_delete,false)
    ORDER BY p.id,members.priority DESC,members.sequence DESC
  """, parameters: [year, leagues]);
  return rows.map((r) => {...r.toColumnMap(), 'active_season': year}).toList();
}
