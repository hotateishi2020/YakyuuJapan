import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/GameSeasonStats.dart';
import 'app/PostseasonForm.dart';
import 'app/PlayerDetail.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.firstOrNull ?? '2026');
  await Postgres.withConnection((c) async {
    final rows = await c.execute('''
      WITH active AS (
        SELECT DISTINCT s.id_player FROM t_game_summary s JOIN t_game g ON g.id=s.id_game
        WHERE g.datetime_start>=make_date(\$1,1,1) AND g.datetime_start<make_date(\$1+1,1,1)
          AND NOT COALESCE(s.flg_delete,false)
      )
      SELECT t.id_league,count(*) AS players,
        count(*) FILTER(WHERE EXISTS(SELECT 1 FROM v_stats_player v WHERE v.int_year=\$1 AND v.payload->>'id_player'=p.id::text AND v.payload->>'title'='打率')) AS ranked_batting,
        count(*) FILTER(WHERE EXISTS(SELECT 1 FROM v_stats_player v WHERE v.int_year=\$1 AND v.payload->>'id_player'=p.id::text AND v.payload->>'title'='防御率')) AS ranked_pitching,
        count(*) FILTER(WHERE EXISTS(SELECT 1 FROM m_player_career k WHERE k.int_year=\$1 AND k.id_player=p.id AND NOT COALESCE(k.flg_delete,false))) AS career
      FROM active a JOIN m_player p ON p.id=a.id_player JOIN m_team t ON t.id=p.id_team
      WHERE t.id_league IN(1,2,3,4) GROUP BY t.id_league ORDER BY t.id_league
    ''', parameters: [year]);
    print(jsonEncode(rows.map((r) => r.toColumnMap()).toList()));
    final people = (await c.execute('''
      SELECT p.id,p.id AS id_player,p.id_team,t.id_league,p.name_full,
        p.name_full AS name_full_summary,p.name_patterns,p.identity_sources,p.url,p.date_birth::text,
        bool_or(s.int_batting>0) AS batted,bool_or(s.double_inning_pitch>0 OR s.int_pitch>0) AS pitched
      FROM m_player p JOIN m_team t ON t.id=p.id_team JOIN t_game_summary s ON s.id_player=p.id
      JOIN t_game g ON g.id=s.id_game
      WHERE t.id_league IN(1,2,3,4) AND g.datetime_start>=make_date(\$1,1,1)
        AND g.datetime_start<make_date(\$1+1,1,1) AND NOT COALESCE(s.flg_delete,false)
      GROUP BY p.id,t.id_league
    ''', parameters: [year])).map((r) => r.toColumnMap()).toList();
    await attachOfficialIdentity(c, year, people);
    final stats = (await c.execute('SELECT payload FROM v_stats_player WHERE int_year=\$1', parameters: [year]))
        .map((r) => detailMap(r[0])).toList();
    final careers = (await c.execute('SELECT * FROM m_player_career WHERE int_year=\$1 AND NOT COALESCE(flg_delete,false) ORDER BY id DESC', parameters: [year]))
        .map((r) => r.toColumnMap()).toList();
    addCareerFormBaselines(stats, careers, people: people);
    final official = GameSeasonStats.cached(year);
    final officialOnly = <Map<String, dynamic>>[];
    addOfficialGameSeasonStats(officialOnly, people, official);
    addOfficialGameSeasonStats(stats, people, official);
    final missing = <Map<String, dynamic>>[];
    for (final p in people) {
      final titles = stats.where((s) => '${s['id_player']}' == '${p['id_player']}').map((s) => s['title']).toSet();
      final needed = [if (p['batted'] == true) ...['打率','本塁打'], if (p['pitched'] == true) ...['防御率','勝利']];
      final absent = needed.where((t) => !titles.contains(t) && !(t == '勝利' && titles.contains('最多勝'))).toList();
      if (absent.isNotEmpty) missing.add({'id': p['id'], 'name': p['name_full'], 'league': p['id_league'], 'missing': absent, 'source_id': officialPlayerId(p), 'birth': p['date_birth'], 'url': p['url'], 'team': p['id_team'], 'aliases': p['name_patterns']});
    }
    final fallback = <Map<String,dynamic>>[];
    for (final p in people) {
      final titles = officialOnly.where((s) => '${s['id_player']}' == '${p['id_player']}').map((s) => s['title']).toSet();
      final needed = [if (p['batted'] == true) ...['打率','本塁打'], if (p['pitched'] == true) ...['防御率','勝利']];
      final absent = needed.where((t) => !titles.contains(t)).toList();
      if (absent.isNotEmpty) fallback.add({'id': p['id'], 'name': p['name_full'], 'fields': absent});
    }
    print(jsonEncode({'official_records': official.length, 'appeared_players': people.length, 'missing': missing, 'career_fallback': fallback}));
    if (args.contains('--attach')) {
      final games = (await c.execute('''SELECT DISTINCT ON (h.id_league)
        g.id AS id_game,g.datetime_start::text AS date_game,g.id_team_home,g.id_team_away,
        h.id_league AS id_league_home,a.id_league AS id_league_away,g.code_game
        FROM t_game g JOIN m_team h ON h.id=g.id_team_home JOIN m_team a ON a.id=g.id_team_away
        WHERE h.id_league IN(1,2,3,4) AND g.datetime_start>=make_date(\$1,1,1)
          AND g.datetime_start<make_date(\$1+1,1,1) AND NOT COALESCE(g.flg_delete,false)
        ORDER BY h.id_league,g.datetime_start DESC''', parameters: [year])).map((r) => r.toColumnMap()).toList();
      await attachPostseasonForm(c, games, year);
      print(jsonEncode({'game_payloads': [for (final g in games) {
        'id': g['id_game'], 'version': g['season_stats_version'],
        'season_rows': (g['season_player_stats'] as List).length,
      }]}));
    }
  });
  exit(0);
}
