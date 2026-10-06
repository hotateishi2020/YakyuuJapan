import 'dart:io';

import 'app/FetchURL.dart';
import 'tools/Postgres.dart';

/// 昨日（および指定日）の MLB 試合の出場成績・テキスト速報・スコアボードを取り直す。
Future<void> main(List<String> args) async {
  final date = args.isNotEmpty ? args.first : '2026-10-06';
  final npbOnly = args.contains('npb-only');
  await Postgres.withConnection((conn) async {
    if (npbOnly) {
      print('MLB skip (npb-only)');
    } else {
    final rows = await Postgres.execute(conn, '''
      SELECT g.id, g.id_team_home, g.id_team_away, g.id_pitcher_home, g.id_pitcher_away,
             home.name_short AS home_name, away.name_short AS away_name
      FROM t_game g
      JOIN m_team home ON home.id = g.id_team_home
      JOIN m_team away ON away.id = g.id_team_away
      WHERE home.id_league IN (3, 4) AND away.id_league IN (3, 4)
        AND g.datetime_start::date = \$1::date
      ORDER BY g.id
    ''', data: [date]);
    print('MLB $date: ${rows.length} games');
    final hrefByMatchup = <String, String>{
      'レイズ|ヤンキース': '/mlb/game/2026100602/index',
      'ガーディアンズ|Wソックス': '/mlb/game/2026100601/index',
      'ガーディアンズ|ホワイトソックス': '/mlb/game/2026100601/index',
    };
    final pageUrl = Uri.parse('https://baseball.yahoo.co.jp/mlb/schedule/?date=$date');
    for (final row in rows) {
      final m = row.toColumnMap();
      final id = m['id'] as int;
      final home = '${m['home_name']}';
      final away = '${m['away_name']}';
      final href = hrefByMatchup['$home|$away'];
      if (href == null) {
        print('skip $id $away @ $home (href unknown)');
        continue;
      }
      print('refresh $id $away @ $home $href');
      await FetchURL.refreshGameDetails(
        conn,
        pageUrl,
        href,
        id,
        m['id_team_home'] as int,
        m['id_team_away'] as int,
        m['id_pitcher_home'] as int? ?? 0,
        m['id_pitcher_away'] as int? ?? 0,
      );
    }
    }
    final npbHref = <String, String>{
      '阪神|広島': '/npb/game/2021051133/index',
      'ロッテ|西武': '/npb/game/2021051120/index',
    };
    final npbRows = await Postgres.execute(conn, '''
      SELECT g.id, g.id_team_home, g.id_team_away, g.id_pitcher_home, g.id_pitcher_away,
             home.name_short AS home_name, away.name_short AS away_name
      FROM t_game g
      JOIN m_team home ON home.id = g.id_team_home
      JOIN m_team away ON away.id = g.id_team_away
      WHERE home.id_league IN (1, 2) AND away.id_league IN (1, 2)
        AND g.datetime_start::date = \$1::date
        AND g.state LIKE '%終了%'
      ORDER BY g.id
    ''', data: [date]);
    final npbPage = Uri.parse('https://baseball.yahoo.co.jp/npb/schedule/?date=$date');
    for (final row in npbRows) {
      final m = row.toColumnMap();
      final home = '${m['home_name']}';
      final away = '${m['away_name']}';
      final href = npbHref['$home|$away'];
      if (href == null) {
        print('skip NPB ${m['id']} $away @ $home');
        continue;
      }
      print('refresh NPB ${m['id']} $away @ $home $href');
      await FetchURL.refreshGameDetails(
        conn,
        npbPage,
        href,
        m['id'] as int,
        m['id_team_home'] as int,
        m['id_team_away'] as int,
        m['id_pitcher_home'] as int? ?? 0,
        m['id_pitcher_away'] as int? ?? 0,
      );
    }
  });
  exit(0);
}
