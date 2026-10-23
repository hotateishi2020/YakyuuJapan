import 'package:postgres/postgres.dart';

const homeBattingTitles = ['打率', '本塁打', '打点', '盗塁', '最多安打', '出塁率'];
const homePitchingTitles = ['防御率', '最多勝', '勝率', '奪三振', 'HP', 'セーブ'];

List<Map<String, dynamic>> homeLeaders(Iterable<Map<String, dynamic>> rows) {
  const aliases = {'安打': '最多安打', '勝利': '最多勝', 'ホールドポイント': 'HP', '最高出塁率': '出塁率'};
  final result = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final row in rows) {
    final title = aliases['${row['title']}'] ?? '${row['title']}';
    if (!homeBattingTitles.contains(title) && !homePitchingTitles.contains(title)) continue;
    if (int.tryParse('${row['int_rank']}') != 1) continue;
    final key = '${row['id_league']}:$title:${row['id_player'] ?? row['name_player']}';
    if (seen.add(key)) result.add({...row, 'title': title});
  }
  return result;
}

/// App selection, not the official player-of-the-game award.
/// Total bases + RBI + steals, or outs + strikeouts - 3 * earned runs.
Map<String, dynamic>? homeHero(Map<String, dynamic> game, Iterable<Map<String, dynamic>> lines) {
  if (!'${game['state']}'.contains('試合終了')) return null;
  num n(dynamic value) => num.tryParse('$value') ?? 0;
  if (game['score_home'] == null || game['score_away'] == null) return null;
  final home = n(game['score_home']), away = n(game['score_away']);
  if (home == away || home < 0 || away < 0) return null;
  final team = game[home > away ? 'id_team_home' : 'id_team_away'];
  Map<String, dynamic>? best;
  num bestScore = -double.infinity;
  final ordered = lines.toList()..sort((a,b) => n(a['id_player']).compareTo(n(b['id_player'])));
  for (final line in ordered) {
    if ('${line['id_game']}' != '${game['id_game']}' || '${line['id_team']}' != '$team') continue;
    final innings = n(line['double_inning_pitch']);
    final outs = innings.floor() * 3 + ((innings - innings.floor()) * 10).round();
    final batting = n(line['int_hit1']) + n(line['int_hit2']) + 2*n(line['int_hit3']) + 3*n(line['int_homerun']) + n(line['int_rbi']) + n(line['int_steal_base']);
    final pitching = outs + n(line['int_strike_out']) - 3*n(line['int_runs_earned']);
    if (n(line['int_batting']) == 0 && outs == 0 && batting == 0) continue;
    final score = batting > pitching ? batting : pitching;
    if (score > bestScore) {
      bestScore = score;
      best = {'id_player': line['id_player'], 'name_player': line['name_player'], 'name_team': game[home > away ? 'name_team_home' : 'name_team_away']};
    }
  }
  return best;
}

Future<List<Map<String, dynamic>>> homeHeroLines(Connection conn, String today) async {
  final result = await conn.execute('''
    SELECT s.*, p.id_team, p.name_full AS name_player
    FROM t_game_summary s JOIN t_game g ON g.id=s.id_game
    JOIN m_player p ON p.id=s.id_player
    WHERE g.datetime_start >= \$1::date AND g.datetime_start < \$1::date + INTERVAL '1 day'
      AND g.state LIKE '%試合終了%' AND COALESCE(g.flg_stats_loaded, false)
  ''', parameters: [today]);
  return result.map((r) => r.toColumnMap()).toList();
}
