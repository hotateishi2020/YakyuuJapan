import 'package:postgres/postgres.dart';
import 'AppSql.dart';

Future<Map<String, dynamic>> readJapaneseMlbStats(Connection conn, int year) async {
  final careers = await conn.execute('''
    SELECT DISTINCT ON(c.id_player,c.id_team) c.*, p.name_full AS name_player,
      t.name_short AS name_team, t.color_back, t.color_font, t.id_league
    FROM m_player_career c JOIN m_player p ON p.id=c.id_player
    JOIN m_country country ON country.id=p.id_country
    JOIN m_team t ON t.id=c.id_team
    WHERE c.int_year=\$1 AND t.id_league IN (3,4) AND country.name='日本'
      AND NOT COALESCE(c.flg_delete,false) AND NOT COALESCE(p.flg_delete,false)
    ORDER BY c.id_player,c.id_team,c.updat DESC NULLS LAST,c.id DESC
  ''', parameters: [year]);
  final stats = await conn.execute(AppSql.selectStatsPlayer(), parameters: [year]);
  return buildJapaneseMlbStats(careers.map((r) => r.toColumnMap()).toList(),
    stats.map((r) => r.toColumnMap()).toList(), year);
}

Map<String, dynamic> buildJapaneseMlbStats(List<Map<String, dynamic>> careers,
    List<Map<String, dynamic>> stats, int year) {
  bool yes(Object? v) => v == true || v == 1 || v == 'true';
  num number(Object? v) => num.tryParse('$v') ?? 0;
  final result = <String, Map<String, dynamic>>{};
  void put(Map<String, dynamic> row, bool pitching, String title, Object? value) {
    final key = '${row['id_player']}:$pitching';
    final player = result.putIfAbsent(key, () => {
      'id_player': row['id_player'], 'name_player': row['name_player'],
      'name_team': row['name_team'], 'color_back': row['color_back'],
      'color_font': row['color_font'], 'pitching': pitching, 'stats': <String, dynamic>{},
    });
    (player['stats'] as Map<String, dynamic>)[title] = value;
  }
  // These fields are populated by the existing Japanese-player career importer.
  // Do not treat unimported career columns (default zero) as measured results.
  final grouped = <String,List<Map<String,dynamic>>>{};
  for (final row in careers) {
    grouped.putIfAbsent('${row['id_player']}', () => []).add(row);
  }
  for (final teams in grouped.values) {
    final row = {...teams.first, 'name_team': teams.map((r) => r['name_team']).toSet().join(' / ')};
    num sum(String field) => teams.fold<num>(0, (n,r) => n + number(r[field]));
    if (sum('int_appearance') > 0 || sum('int_batting') > 0) {
      put(row, false, '打席', sum('int_appearance'));
      put(row, false, '打数', sum('int_batting'));
      // A multi-team average cannot be obtained by averaging rounded averages.
      if (teams.length == 1) put(row, false, '打率', number(row['double_average_batting']).toStringAsFixed(3));
    }
    if (sum('int_pitching') > 0) {
      for (final entry in {'登板':'int_pitching','勝利':'int_win','敗戦':'int_lose','奪三振':'int_strike_out_pitcher'}.entries) {
        put(row, true, entry.key, sum(entry.value));
      }
      final outs = teams.fold<int>(0, (n,r) {
        final innings = number(r['double_inning']);
        return n + innings.floor()*3 + ((innings-innings.floor())*10).round();
      });
      put(row, true, '投球回', '${outs ~/ 3}.${outs % 3}');
      if (teams.length == 1) put(row, true, '防御率', number(row['double_average_earned_runs']).toStringAsFixed(2));
    }
  }
  const aliases = {'最多勝':'勝利','最多安打':'安打','打席数':'打席','登板回数':'登板','投球回数':'投球回','ホールド':'HP'};
  for (final row in stats) {
    if (!yes(row['flg_japan']) || ![3,4].contains(number(row['id_league']))) continue;
    final title = '${row['title']}';
    put(row, yes(row['flg_pitcher']), aliases[title] ?? title, row['stats']);
  }
  final players = result.values.toList()..sort((a,b) => '${a['name_player']}'.compareTo('${b['name_player']}'));
  return {'year': year, 'players': players};
}
