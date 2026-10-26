import 'postseason_bracket.dart';

/// Only uses results on/before this game; never previews a later outcome.
String gameStory(Map<String, dynamic> game, {
  List<Map<String, dynamic>> seriesGames = const [],
  List<Map<String, dynamic>> standings = const [],
}) {
  final date = '${game['date_game'] ?? ''}'.split(' ').first.split('T').first;
  final state = '${game['state'] ?? ''}';
  if (RegExp('中止|延期|未実施').hasMatch(state)) return '';
  final ended = state == '試合終了' || state.contains('コールド');
  final history = <String, Map<String, dynamic>>{};
  for (final row in [...seriesGames, if (ended) game]) {
    final day = '${row['date_game'] ?? ''}'.split(' ').first.split('T').first;
    if (day.isEmpty || day.compareTo(date) > 0 || (!ended && day == date)) continue;
    if (day.length < 10 || date.length < 10 || day.substring(0, 4) != date.substring(0, 4)) continue;
    history['${row['id_game'] ?? '$day-${row['id_team_home']}-${row['id_team_away']}-${row['code_game']}'}'] = row;
  }
  final code = '${game['code_game'] ?? ''}'.toUpperCase();
  final stars = [for (final home in [true, false])
    date.length >= 10 ? seriesStarsForSide(game: game, home: home,
      seriesGames: history.values.toList(), standings: standings) : null];
  final postseason = stars.any((s) => s != null);
  String team(int i) {
    final name = '${game['name_team_${i == 0 ? 'home' : 'away'}'] ?? ''}';
    return name.contains('ソフトバンク') ? 'ホークス' : name;
  }
  int winningStreak(int i) {
    final side = i == 0 ? 'home' : 'away';
    final saved = int.tryParse('${game['story_streak_$side']}');
    if (saved != null) return saved > 0 ? saved : 0;
    final id = '${game['id_team_$side']}';
    final games = history.values.where((r) =>
      '${r['code_game']}'.toUpperCase() == code &&
      {'${r['id_team_home']}', '${r['id_team_away']}'}.containsAll(
        ['${game['id_team_home']}', '${game['id_team_away']}'])).toList()
      ..sort((a,b) => '${b['date_game']}'.compareTo('${a['date_game']}'));
    var count = 0;
    for (final row in games) {
      if (row['state'] != '試合終了' && !'${row['state']}'.contains('コールド')) break;
      final h = int.tryParse('${row['score_home']}');
      final a = int.tryParse('${row['score_away']}');
      if (h == null || a == null || h < 0 || a < 0) break;
      if (h == a) continue;
      if ('${row[h > a ? 'id_team_home' : 'id_team_away']}' != id) break;
      count++;
    }
    return count;
  }

  String subject(int i) {
    final side = i == 0 ? 'home' : 'away';
    final ace = game['flg_ace_pitcher_$side'];
    final raw = '${game['name_pitcher_$side'] ?? ''}'.trim();
    final pitcher = raw.split(RegExp(r'[\s　]+')).first;
    return (ace == true || ace == 1 || ace == 'true') && pitcher.isNotEmpty
        ? '${team(i)}、エースの$pitcherで' : '${team(i)}、';
  }
  String contest(int leader, String goal, String stop) {
    final streak = winningStreak(leader);
    final momentum = streak >= 2 ? '${streak + 1}連勝で' : '';
    final defender = subject(1-leader).replaceFirst('、', 'は');
    return '${team(leader)}$momentum$goalか、$defender$stopなるか？';
  }
  final stage = code == 'JS' ? '日本一' : code == 'WS' ? '世界一' : 'シリーズ突破';
  for (var i = 0; i < 2; i++) {
    final s = stars[i];
    if (s != null && s.wins >= s.slots) return '${team(i)}、$stage決定！';
  }
  if (!ended && postseason) {
    // A clinch threat takes priority over every streak or ace-only storyline.
    for (var i = 0; i < 2; i++) {
      final s = stars[i];
      if (s != null && s.wins == s.slots - 1) {
        if (stars[1-i]?.wins == s.slots - 1) return '${team(0)}対${team(1)}、$stageを懸けた最終決戦！';
        final target = code == 'JS' || code == 'WS' ? '優勝阻止' : '突破阻止';
        return contest(i, stage, target);
      }
    }
    for (var i = 0; i < 2; i++) {
      final s = stars[i];
      if (s != null && s.slots >= 3 && s.wins == s.slots - 2) {
        return contest(i, '王手', '王手阻止');
      }
    }
  }
  for (var i = 0; i < 2; i++) {
    final s = stars[i];
    if (ended && s != null && s.wins == s.slots - 1) return '${team(i)}、$stageに王手！';
  }
  if (!ended) {
    for (var i = 0; i < 2; i++) {
      final side = i == 0 ? 'home' : 'away';
      final streak = int.tryParse('${game['story_streak_$side']}') ?? 0;
      if (!postseason && streak >= 2) return '${subject(i)}${streak + 1}連勝なるか？';
      if (!postseason && streak <= -2) return '${subject(i)}${-streak}連敗ストップなるか？';
    }
    for (var i = 0; i < 2; i++) {
      if (subject(i).contains('エースの')) return '${subject(i)}勝利なるか？';
    }
  }
  if (team(0).isEmpty || team(1).isEmpty) return '';
  return ended ? '${team(0)}対${team(1)}、熱戦の結果をチェック！'
      : 'ホームの${team(0)}に挑む${team(1)}、勝利なるか？';
}
