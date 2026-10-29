import 'package:postgres/postgres.dart';
import 'HomeBirthdays.dart';

/// Share short-lived HOME reads without holding several league-wide snapshots.
class HomeDashboardCache {
  static Map<String,dynamic>? _value;
  static Future<Map<String,dynamic>>? _pending;
  static DateTime? _expires;
  static String? _day;
  static int _generation = 0;
  static void clear() { _generation++; _value = null; _pending = null; _expires = null; _day = null; }
  static Future<Map<String,dynamic>> read(String day,
      Future<Map<String,dynamic>> Function() fetch) async {
    if (_day != day) clear();
    _day = day;
    if (_value != null && _expires!.isAfter(DateTime.now())) return _value!;
    if (_pending != null) return _pending!;
    final generation = _generation;
    final future = fetch();
    _pending = future;
    try {
      final result = await future;
      if (generation == _generation) {
        _value = result;
        _expires = DateTime.now().add(const Duration(seconds: 45));
      }
      return result;
    } finally { if (identical(_pending, future)) _pending = null; }
  }
}

/// HOME needs today's score summary and heroes, not batting blocks, postseason
/// forms, player rankings or next week's full game details.
Future<Map<String,dynamic>> readHomeSummary(Connection conn, String today) async {
  final birthdays = await homeBirthdays(conn, today);
  final games = (await conn.execute('''SELECT g.id AS id_game,
    g.datetime_start::date::text AS date_game,to_char(g.datetime_start,'HH24:MI') AS time_game,
    g.state,g.score_home,g.score_away,g.id_team_home,g.id_team_away,
    h.name_short AS name_team_home,a.name_short AS name_team_away,
    CASE WHEN h.id_league IN(1,2) THEN 'NPB' ELSE 'MLB' END AS org
    FROM t_game g JOIN m_team h ON h.id=g.id_team_home JOIN m_team a ON a.id=g.id_team_away
    WHERE g.datetime_start>=\$1::date AND g.datetime_start<\$1::date+INTERVAL '1 day'
      AND h.id_league IN(1,2,3,4) AND NOT COALESCE(g.flg_delete,false)
    ORDER BY g.datetime_start,g.id''', parameters: [today])).map((r) => r.toColumnMap()).toList();
  final lines = games.any((g) => '${g['state']}'.contains('試合終了'))
      ? await homeHeroLines(conn, today) : <Map<String,dynamic>>[];
  final heroes = <Map<String,dynamic>>[];
  for (final game in games) {
    final hero = homeHero(game, lines);
    if (hero != null) heroes.add({...hero, 'id_game': game['id_game'], 'org': game['org']});
  }
  return {'today': today, 'birthdays': birthdays, 'games': games, 'heroes': heroes,
    'notification': [], 'events': [], 'leaders': []};
}

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
      best = {'id_player': line['id_player'], 'name_player': line['name_player'], 'name_team': game[home > away ? 'name_team_home' : 'name_team_away'], ...homeHeroPerformance(line)};
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

/// Only completed game summary values, never season totals or live plate results.
Map<String, dynamic> homeHeroPerformance(Map<String, dynamic> line) {
  num n(String key) => num.tryParse('${line[key]}') ?? 0;
  final stats = <String>[];
  final highlights = <String>[];
  final innings = n('double_inning_pitch');
  final fraction = ((innings - innings.floor()) * 10).round();
  if (innings > 0 || n('int_pitch') > 0) {
    final ip = '${innings.floor()}${fraction == 0 ? '' : ' $fraction/3'}回';
    stats.add('$ip ${n('int_runs')}失点（自責点${n('int_runs_earned')}） ${n('int_strike_out')}奪三振');
    const results = {'WIN': '勝利投手', 'W': '勝利投手', 'SAVE': 'セーブ', 'S': 'セーブ', 'HOLD': 'ホールド', 'H': 'ホールド'};
    final result = results['${line['code_result_pitcher']}'];
    if (result != null) highlights.add(result);
    if (n('int_runs') == 0) highlights.add('$ip無失点');
    if (n('int_strike_out') >= 10) highlights.add('2桁奪三振');
  }
  if (n('int_batting') > 0 || n('int_fourball') > 0 || n('int_dead_batting') > 0) {
    stats.add('${n('int_batting')}打数${n('int_hit1')}安打 ${n('int_rbi')}打点'
        '${n('int_fourball') > 0 ? ' ${n('int_fourball')}四球' : ''}');
    if (n('int_homerun') > 0) highlights.add('${n('int_homerun')}本塁打');
    if (n('int_rbi') > 0) highlights.add('${n('int_rbi')}打点');
    if (n('int_hit1') >= 3) {
      highlights.add('猛打賞');
    } else if (n('int_hit1') >= 2) {
      highlights.add('マルチ安打');
    }
  }
  if (n('int_steal_base') > 0) highlights.add('${n('int_steal_base')}盗塁');
  return {'appearance_stats': stats, 'highlights': highlights};
}
