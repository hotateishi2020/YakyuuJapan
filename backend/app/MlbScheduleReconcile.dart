import 'package:html/dom.dart';
import 'package:postgres/postgres.dart';
import 'YahooTeamNames.dart';

bool cancelledMlbCard(String state) => RegExp('中止|延期|開催なし').hasMatch(state);

/// null means an unrecognised response, never an empty official schedule.
List<Map<String, String>>? mlbScheduleCards(Document document) {
  final root = document.querySelector('#gm_card');
  final items = root?.querySelectorAll('li.bb-score__item') ?? [];
  if (items.isEmpty) {
    return RegExp('試合はありません|試合は予定されていません|試合がありません')
            .hasMatch(document.body?.text ?? '')
        ? []
        : null;
  }
  final cards = <Map<String, String>>[];
  for (final item in items) {
    final home = YahooTeamNames.normalize(
        item.querySelector('.bb-score__homeLogo')?.text.trim() ?? '');
    final away = YahooTeamNames.normalize(
        item.querySelector('.bb-score__awayLogo')?.text.trim() ?? '');
    if (home.isEmpty || away.isEmpty) return null;
    cards.add({
      'home': home,
      'away': away,
      'state':
          '${item.querySelector('.bb-score__link')?.text ?? ''} ${item.querySelector('.bb-score__status')?.text ?? ''}'
    });
  }
  return cards;
}

List<int> obsoleteMlbGameIds(
    List<Map<String, dynamic>> games, List<Map<String, String>> cards) {
  return [
    for (final g in games)
      if (g['has_records'] != true &&
          !RegExp('終了|試合中(?!止)|[0-9]+\\s*回|Final|In Progress', caseSensitive: false)
              .hasMatch('${g['state']}') &&
          !cards.any((c) =>
              c['home'] == YahooTeamNames.normalize('${g['home']}') &&
              c['away'] == YahooTeamNames.normalize('${g['away']}') &&
              !cancelledMlbCard(c['state']!)))
        g['id'] as int
  ];
}

Future<int> reconcileMlbSchedule(
    Connection conn, String day, Document document) async {
  final cards = mlbScheduleCards(document);
  if (cards == null) return 0;
  final rows = (await conn.execute(
          '''SELECT g.id,g.state,h.name_short AS home,a.name_short AS away,
    EXISTS(SELECT 1 FROM t_game_summary s WHERE s.id_game=g.id AND NOT COALESCE(s.flg_delete,false) AND (s.int_batting>0 OR s.int_pitch>0 OR s.double_inning_pitch>0)) AS has_records
    FROM t_game g JOIN m_team h ON h.id=g.id_team_home JOIN m_team a ON a.id=g.id_team_away
    WHERE g.datetime_start::date=\$1::date AND h.id_league IN (3,4) AND a.id_league IN (3,4) AND NOT COALESCE(g.flg_delete,false)''',
          parameters: [day]))
      .map((r) => r.toColumnMap())
      .toList();
  final ids = obsoleteMlbGameIds(rows, cards);
  if (ids.isNotEmpty) {
    await conn.execute(
        'UPDATE t_game SET flg_delete=true,updat=NOW() WHERE id=ANY(\$1::int[])',
        parameters: [ids]);
    print('MLB日程再確認 $day: 中止・予定消滅 ${ids.length}件を表示対象から除外 $ids');
  }
  return ids.length;
}
