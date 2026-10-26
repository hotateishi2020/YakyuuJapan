import 'package:postgres/postgres.dart';

/// Full season schedule is required: a date-window response cannot prove a streak.
Future<void> attachGameStory(Connection conn, List<Map<String, dynamic>> games, int year) async {
  if (games.isEmpty) return;
  final result = await conn.execute('''
    SELECT DISTINCT ON (datetime_start,id_team_home,id_team_away,code_game)
      id,datetime_start::date::text AS day,id_team_home,id_team_away,
      score_home,score_away,state,code_game
    FROM t_game
    WHERE datetime_start >= make_date(\$1,1,1)
      AND datetime_start < make_date(\$1+1,1,1)
      AND NOT COALESCE(flg_delete,false)
    ORDER BY datetime_start,id_team_home,id_team_away,code_game,updat DESC NULLS LAST,id DESC
  ''', parameters: [year]);
  final history = result.map((r) => r.toColumnMap()).toList().reversed.toList();
  int number(dynamic v) => int.tryParse('$v') ?? -1;
  for (final game in games) {
    final date = '${game['date_game']}'.split(' ').first.split('T').first;
    for (final side in ['home','away']) {
      final team = number(game['id_team_$side']);
      var count = 0;
      for (final row in history) {
        if ('${row['day']}'.compareTo(date) >= 0 || row['code_game'] != game['code_game']) continue;
        if (number(row['id_team_home']) != team && number(row['id_team_away']) != team) continue;
        final state = '${row['state']}';
        if (state.contains('中止') || state.contains('延期')) continue;
        // Unknown scores / unverified games interrupt coverage.
        if (state != '試合終了' && !state.contains('コールド')) { count = 0; break; }
        final h = number(row['score_home']), a = number(row['score_away']);
        if (h < 0 || a < 0) { count = 0; break; }
        if (h == a) continue; // NPB streaks exclude draws.
        final winner = h > a ? number(row['id_team_home']) : number(row['id_team_away']);
        final direction = winner == team ? 1 : -1;
        if (count != 0 && count.sign != direction) break;
        count += direction;
      }
      game['story_streak_$side'] = count;
    }
  }
}
