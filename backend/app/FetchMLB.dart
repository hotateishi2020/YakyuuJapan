import 'package:html/dom.dart';
import 'package:intl/intl.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import '../tools/DateTimeTool.dart';
import '../tools/Postgres.dart';
import '../tools/StringTool.dart';
import 'AppSql.dart';
import 'BirthPlaceRegistry.dart';
import 'DB/m_player.dart';
import 'DB/m_stadium.dart';
import 'DB/t_game.dart';
import 'DB/t_stats_team.dart';
import 'FetchURL.dart';
import 'OrgLeague.dart';
import 'YahooHtml.dart';
import 'YahooTeamNames.dart';

/// MLB 用スクレイプ。Yahoo HTML の読み方は NPB と共通化しつつ、URL・地区構成だけ差し替える。
class FetchMLB {
  static final _org = OrgKind.mlb;

  /// 地区順位表（最大6表）を読み、ア／ナ各リーグ内の勝率順で総合順位を付ける。
  static Future<Response> fetchStatsTeam(Connection conn) async {
    final document = await YahooHtml.fetchDocument(Uri.parse(_org.standingsUrl));
    final tables = document.querySelectorAll('table.bb-rankTable');
    if (tables.isEmpty) {
      throw Exception('MLB順位表が見つかりませんでした');
    }

    final byLeague = <int, List<t_stats_team>>{3: [], 4: []};
    var tableIndex = 0;
    for (final table in tables) {
      if (tableIndex >= 6) break;
      final leagueId = tableIndex < 3 ? 3 : 4;
      for (final row in table.querySelectorAll('tbody tr')) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 8) continue;
        final rawName = cells[1].text.trim();
        final teamName = YahooTeamNames.normalize(rawName);
        final teamRow = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [teamName]);
        if (teamRow.isEmpty) {
          print('MLB順位: 未知の球団名 "$rawName" → "$teamName"');
          continue;
        }
        final map = teamRow.first.toColumnMap();
        final team = t_stats_team()
          ..year = DateTimeTool.getThisYear()
          ..id_team = map['id'] as int
          ..int_rank = int.tryParse(cells[0].text.trim()) ?? 0
          ..int_game = int.tryParse(cells[2].text.trim()) ?? 0
          ..int_win = int.tryParse(cells[3].text.trim()) ?? 0
          ..int_lose = int.tryParse(cells[4].text.trim()) ?? 0
          ..int_draw = int.tryParse(cells[5].text.trim()) ?? 0
          ..game_behind = cells[7].text.trim();
        // MLB Yahoo 順位表は打率・防御率列が無い／異なる場合がある
        if (cells.length > 13) {
          team.num_avg_batting = double.tryParse('0${cells[13].text.trim()}') ?? 0;
        }
        if (cells.length > 14) {
          team.num_era_total = double.tryParse(cells[14].text.trim()) ?? 0;
        }
        byLeague[leagueId]!.add(team);
        print('MLB順位登録: $teamName (league=$leagueId)');
      }
      tableIndex++;
    }

    final teams = <t_stats_team>[];
    for (final entry in byLeague.entries) {
      final list = entry.value;
      list.sort((a, b) {
        final aw = a.int_win / (a.int_win + a.int_lose == 0 ? 1 : a.int_win + a.int_lose);
        final bw = b.int_win / (b.int_win + b.int_lose == 0 ? 1 : b.int_win + b.int_lose);
        final byPct = bw.compareTo(aw);
        if (byPct != 0) return byPct;
        return a.int_win.compareTo(b.int_win) * -1;
      });
      for (var i = 0; i < list.length; i++) {
        list[i].int_rank = i + 1;
      }
      teams.addAll(list);
    }

    if (teams.isEmpty) {
      throw Exception('MLB順位を1件も取得できませんでした');
    }
    await Postgres.insertMulti(conn, teams);
    return Response.ok('ok');
  }

  /// m_stats_details の MLB URL（リーグ 3/4）を巡回して個人成績を登録。
  static Future<Response> fetchStatsPlayer(Connection conn) async {
    await ensureMlbStatsDetails(conn);
    return FetchURL.fetchStatsPlayerForLeagues(conn, _org.leagueIds);
  }

  /// NPB(league=1) を雛形に MLB の URL・列番号・flg_predict を揃える。
  static Future<void> ensureMlbStatsDetails(Connection conn) async {
    final npb = await conn.execute('''
      SELECT id_stats, flg_predict, url, int_idx_col, id_website,
             int_idx_col_details, int_idx_row_details
      FROM m_stats_details
      WHERE id_league = 1
    ''');
    for (final row in npb) {
      final m = row.toColumnMap();
      final idStats = m['id_stats'] as int;
      final flgPredict = m['flg_predict'] as bool;
      final intIdxCol = m['int_idx_col'] as int;
      final idWebsite = m['id_website'];
      final idxColDetails = m['int_idx_col_details'];
      final idxRowDetails = m['int_idx_row_details'];
      final npbUrl = '${m['url'] ?? ''}';
      for (final leagueId in _org.leagueIds) {
        final kind = leagueId == 3 ? 1001 : 1002;
        final mlbUrl = npbUrl.isEmpty
            ? ''
            : npbUrl
                .replaceAll('/npb/stats/', '/mlb/stats/')
                .replaceAllMapped(RegExp(r'gameKindId=\d+'), (_) => 'gameKindId=$kind');
        final existing = await conn.execute(
          'SELECT id, int_idx_col FROM m_stats_details WHERE id_stats = \$1 AND id_league = \$2 LIMIT 1',
          parameters: [idStats, leagueId],
        );
        if (existing.isEmpty) {
          await conn.execute('''
            INSERT INTO m_stats_details
              (id_stats, id_league, flg_predict, url, int_idx_col, id_website,
               int_idx_col_details, int_idx_row_details, flg_delete)
            VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,false)
          ''', parameters: [
            idStats, leagueId, flgPredict, mlbUrl, intIdxCol, idWebsite,
            idxColDetails, idxRowDetails,
          ]);
        } else {
          await conn.execute('''
            UPDATE m_stats_details SET
              flg_predict = \$3,
              url = \$4,
              int_idx_col = \$5,
              id_website = \$6,
              int_idx_col_details = \$7,
              int_idx_row_details = \$8,
              updat = NOW()
            WHERE id_stats = \$1 AND id_league = \$2
          ''', parameters: [
            idStats, leagueId, flgPredict, mlbUrl, intIdxCol, idWebsite,
            idxColDetails, idxRowDetails,
          ]);
        }
      }
    }
  }

  /// 日程カード＋試合トップから試合情報を登録。ポストシーズンも含める。
  static Future<Response> fetchGames(Connection conn) async {
    final now = DateTime.now();
    final dates = [for (var i = 0; i <= 10; i++) now.add(Duration(days: i))];
    final formatter = DateFormat('yyyy-MM-dd');

    for (final date in dates) {
      final formatted = formatter.format(date);
      print('MLB $formatted の試合を取得します。');
      final url = Uri.parse('${_org.scheduleUrlPrefix}$formatted');
      Document document;
      try {
        document = await YahooHtml.fetchDocument(url);
      } catch (e) {
        print('MLB日程取得失敗: $e');
        continue;
      }

      final cardsRoot = document.querySelector('#gm_card');
      if (cardsRoot == null) {
        print('MLB: この日の試合カードはありません。');
        continue;
      }

      for (final section in cardsRoot.querySelectorAll('section.bb-score')) {
        final sectionTitle = section.querySelector('.bb-score__title')?.text.trim() ?? '';
        for (final card in section.querySelectorAll('li.bb-score__item')) {
          final link = card.querySelector('a.bb-score__content');
          final href = link?.attributes['href']?.trim() ?? '';
          if (href.isEmpty) continue;

          final homeRaw = card.querySelector('.bb-score__homeLogo')?.text.trim() ?? '';
          final awayRaw = card.querySelector('.bb-score__awayLogo')?.text.trim() ?? '';
          final homeName = YahooTeamNames.normalize(homeRaw);
          final awayName = YahooTeamNames.normalize(awayRaw);
          if (homeName.isEmpty || awayName.isEmpty) continue;

          final homeTeam = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [homeName]);
          final awayTeam = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [awayName]);
          if (homeTeam.isEmpty || awayTeam.isEmpty) {
            print('MLB試合: 未知の球団 $homeRaw/$awayRaw');
            continue;
          }
          final idTeamHome = homeTeam.first.toColumnMap()['id'] as int;
          final idTeamAway = awayTeam.first.toColumnMap()['id'] as int;
          final homeLeague = int.tryParse('${homeTeam.first.toColumnMap()['id_league']}') ?? 0;
          final awayLeague = int.tryParse('${awayTeam.first.toColumnMap()['id_league']}') ?? 0;

          final scores = card.querySelectorAll('.bb-score__score');
          var scoreHome = -1;
          var scoreAway = -1;
          if (scores.length >= 3) {
            scoreHome = int.tryParse(scores[0].text.trim()) ?? -1;
            scoreAway = int.tryParse(scores[2].text.trim()) ?? -1;
          }
          final status = card.querySelector('.bb-score__status')?.text.trim() ?? '';
          final venue = card.querySelector('.bb-score__venue')?.text.trim() ?? '';

          var start = gameStartOn(formatted, status);
          start ??= DateTime.tryParse('$formatted 00:00:00');
          if (start == null) continue;

          var idPitcherHome = 0;
          var idPitcherAway = 0;
          var idPitcherWin = 0;
          var idPitcherLose = 0;
          var idPitcherSave = 0;
          var matchState = status;
          var detailScoreHome = scoreHome;
          var detailScoreAway = scoreAway;

          try {
            final detailUrl = url.resolve(href.replaceFirst('index', 'top'));
            final detail = await YahooHtml.fetchDocument(detailUrl);
            final boards = detail.querySelectorAll('#gm_brd');
            if (boards.isNotEmpty) {
              final match = boards.first;
              final info = match.querySelector('#async-gameCard');
              final timeText = (info?.querySelector('time') ?? match.querySelector('time'))?.text.trim() ?? '';
              final parsed = gameStartOn(formatted, timeText);
              if (parsed != null) start = parsed;

              try {
                final detailBlock = match.querySelectorAll('#async-gameDetail').first;
                final scoreSpans = detailBlock.querySelectorAll('div')[1].querySelectorAll('p')[0].querySelectorAll('span');
                if (scoreSpans.length >= 3) {
                  detailScoreHome = int.tryParse(scoreSpans[0].text.trim()) ?? detailScoreHome;
                  detailScoreAway = int.tryParse(scoreSpans[2].text.trim()) ?? detailScoreAway;
                }
                matchState = detailBlock.querySelectorAll('div')[1].querySelectorAll('p')[1].text.trim();
              } catch (_) {}

              try {
                final homePitcher = _starterName(detail, home: true);
                final awayPitcher = _starterName(detail, home: false);
                if (homePitcher.isNotEmpty) {
                  idPitcherHome = await _ensurePlayer(conn, homePitcher, idTeamHome);
                }
                if (awayPitcher.isNotEmpty) {
                  idPitcherAway = await _ensurePlayer(conn, awayPitcher, idTeamAway);
                }
              } catch (e) {
                print('MLB先発投手取得スキップ: $e');
              }

              try {
                for (final player in detail.querySelectorAll('#async-resultPitcher table tbody tr')) {
                  final ths = player.querySelectorAll('th');
                  final tds = player.querySelectorAll('td');
                  if (ths.isEmpty || tds.isEmpty) continue;
                  final result = ths.first.text.trim();
                  final teamSpan = tds.first.querySelector('span')?.text.trim() ?? '';
                  final teamName = YahooTeamNames.normalize(teamSpan);
                  final hrefPlayer = tds.first.querySelector('a')?.attributes['href']?.trim() ?? '';
                  if (hrefPlayer.isEmpty || teamName.isEmpty) continue;
                  final teamResult = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [teamName]);
                  if (teamResult.isEmpty) continue;
                  final idTeam = teamResult.first.toColumnMap()['id'] as int;
                  final playerDoc = await YahooHtml.fetchDocument(detailUrl.resolve(hrefPlayer));
                  final namePlayer = playerDoc.querySelectorAll('ruby.bb-profile__ruby').isEmpty
                      ? ''
                      : playerDoc.querySelectorAll('ruby.bb-profile__ruby').first.text.split('（').first.trim();
                  if (namePlayer.isEmpty) continue;
                  final idPlayer = await _ensurePlayer(conn, namePlayer, idTeam);
                  await BirthPlaceRegistry.applyFromProfile(conn, idPlayer, playerDoc);
                  if (result == '勝利投手') idPitcherWin = idPlayer;
                  if (result == '敗戦投手') idPitcherLose = idPlayer;
                  if (result == 'セーブ') idPitcherSave = idPlayer;
                }
              } catch (_) {}
            }
          } catch (e) {
            print('MLB試合詳細スキップ ($homeName vs $awayName): $e');
          }

          var idStadium = 0;
          final stadiumName = venue.isEmpty ? 'MLB' : venue;
          final stadiumRows = await Postgres.execute(conn, AppSql.selectStadium(), data: ['%$stadiumName%']);
          if (stadiumRows.isEmpty) {
            final stadium = m_stadium()
              ..name_short = stadiumName
              ..id_team = idTeamHome;
            idStadium = await Postgres.insert(conn, stadium);
          } else {
            idStadium = stadiumRows.first.toColumnMap()['id'] as int;
          }

          final exists = await conn.execute(AppSql.selectExistsGame(), parameters: [idTeamHome, idTeamAway, start]);
          final game = t_game()
            ..id_stadium = idStadium
            ..id_team_home = idTeamHome
            ..id_team_away = idTeamAway
            ..id_pitcher_home = idPitcherHome
            ..id_pitcher_away = idPitcherAway
            ..datetime_start = start
            ..score_home = detailScoreHome
            ..score_away = detailScoreAway
            ..state = matchState.isEmpty ? status : matchState
            ..id_pitcher_win = idPitcherWin
            ..id_pitcher_lose = idPitcherLose
            ..id_pitcher_save = idPitcherSave
            ..code_game = _mlbGameCode(sectionTitle, homeLeague, awayLeague);

          if (exists.isEmpty) {
            game.id = await Postgres.insert(conn, game);
            print('MLB試合新規: $homeName vs $awayName');
          } else {
            game.id = exists.first.toColumnMap()['id'] as int;
            await Postgres.update(conn, game);
            print('MLB試合更新: $homeName vs $awayName');
          }
        }
      }
    }
    return Response.ok('ok');
  }

  static String _mlbGameCode(String sectionTitle, int homeLeague, int awayLeague) {
    final title = sectionTitle.replaceAll(RegExp(r'\s+'), '');
    if (title.contains('ワールドシリーズ') || title.contains('WS')) return 'WS';
    if (title.contains('リーグチャンピオン') || title.contains('LCS')) return 'LCS';
    if (title.contains('地区シリーズ') || title.contains('DS')) return 'DS';
    if (title.contains('ワイルドカード') || title.contains('WC')) return 'WC';
    if (homeLeague != 0 && homeLeague == awayLeague) return 'NM';
    return 'EX';
  }

  static String _starterName(Document detail, {required bool home}) {
    final sectionIndex = home ? 0 : 1;
    try {
      return detail
          .querySelectorAll('#strt_mem')
          .first
          .querySelectorAll('section')
          .first
          .querySelectorAll('div')
          .first
          .querySelectorAll('section')[sectionIndex]
          .querySelectorAll('table')
          .first
          .querySelectorAll('tbody')
          .first
          .querySelectorAll('tr')
          .first
          .querySelectorAll('td')[2]
          .querySelectorAll('a')
          .first
          .text
          .trim();
    } catch (_) {
      try {
        return detail
            .querySelectorAll('#strt_pit')
            .first
            .querySelectorAll('div')
            .first
            .querySelectorAll('div')
            .first
            .querySelectorAll('section')[sectionIndex]
            .querySelectorAll('div')[1]
            .querySelectorAll('div')
            .first
            .querySelectorAll('table')
            .first
            .querySelectorAll('tbody')
            .first
            .querySelectorAll('tr')
            .first
            .querySelectorAll('td')[2]
            .querySelectorAll('a')
            .first
            .text
            .trim();
      } catch (_) {
        return '';
      }
    }
  }

  static Future<int> _ensurePlayer(Connection conn, String rawName, int teamId) async {
    final name = StringTool.noSpace(rawName);
    if (name.isEmpty) return 0;
    try {
      final existing = await conn.execute(
        '''
          SELECT id, name_full FROM m_player
          WHERE id_team = \$1::int
            AND (
              name_full = \$2::text
              OR name_last = \$2::text
              OR COALESCE(name_last, '') || COALESCE(name_first, '') = \$2::text
            )
          LIMIT 1
        ''',
        parameters: [teamId, name],
      );
      if (existing.isNotEmpty) {
        final row = existing.first.toColumnMap();
        final id = row['id'] as int;
        if ('${row['name_full'] ?? ''}'.isEmpty) {
          await conn.execute(
            '''
              UPDATE m_player
              SET name_full = \$1::text,
                  updat = NOW()
              WHERE id = \$2::int
            ''',
            parameters: [name, id],
          );
        }
        return id;
      }
    } catch (_) {}
    final player = m_player();
    final parts = rawName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      player.name_last = StringTool.noSpace(parts.first);
      player.name_first = StringTool.noSpace(parts.sublist(1).join());
      player.name_full = player.name_last + player.name_first;
    } else {
      player.name_last = name;
      player.name_first = '';
      player.name_full = name;
    }
    player.id_team = teamId;
    return Postgres.insert(conn, player);
  }
}
