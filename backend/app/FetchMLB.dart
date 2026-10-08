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
import 'DB/m_player_career.dart';
import 'DB/m_stadium.dart';
import 'DB/t_game.dart';
import 'DB/t_game_summary.dart';
import 'DB/t_stats_team.dart';
import 'BoxScore.dart';
import 'FetchURL.dart';
import 'StadiumImages.dart';
import 'GameFetchSchedule.dart';
import 'GameStatsLoad.dart';
import 'OrgLeague.dart';
import 'Value.dart';
import 'YahooHtml.dart';
import 'YahooTeamNames.dart';
import 'PlayerName.dart';

/// MLB 用スクレイプ。Yahoo HTML の読み方は NPB と共通化しつつ、URL・地区構成だけ差し替える。
class FetchMLB {
  static const _org = OrgKind.mlb;

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
        final rankCell = cells[0].text.trim();
        final gbCell = cells[7].text.trim();
        final clinched = rankCell == '優勝' || gbCell == '優勝' || gbCell.toUpperCase() == 'W';
        final team = t_stats_team()
          ..year = DateTimeTool.getThisYear()
          ..id_team = map['id'] as int
          ..id_league = leagueId
          ..int_rank = clinched ? 1 : (int.tryParse(rankCell) ?? 0)
          ..int_game = int.tryParse(cells[2].text.trim()) ?? 0
          ..int_win = int.tryParse(cells[3].text.trim()) ?? 0
          ..int_lose = int.tryParse(cells[4].text.trim()) ?? 0
          ..int_draw = int.tryParse(cells[5].text.trim()) ?? 0
          // 優勝確定は '優勝' で保持（画面側で MLB は「W」表示）。
          ..game_behind = clinched ? '優勝' : gbCell;
        // Yahoo MLB: 0順位 1球団 2試合 3勝 4敗 5分 6勝率 7勝差
        // 8得点 9失点 10本塁打 11盗塁 12打率 13防御率 14失策
        if (cells.length > 10) {
          team.int_homerun = int.tryParse(cells[10].text.trim()) ?? 0;
        }
        if (cells.length > 11) {
          team.int_sh = int.tryParse(cells[11].text.trim()) ?? 0;
        }
        if (cells.length > 12) {
          team.num_avg_batting = double.tryParse('0${cells[12].text.trim()}') ?? 0;
        }
        if (cells.length > 13) {
          team.num_era_total = double.tryParse(cells[13].text.trim()) ?? 0;
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
    await syncJapanesePlayers(conn);
    final res = await FetchURL.fetchStatsPlayerForLeagues(conn, _org.leagueIds);
    await enrichMlbPlayersForMarks(conn);
    return res;
  }

  /// 🍁🌱🔰用に、個人成績に出ている MLB 選手の生年月日・年度別成績をプロフィールから補完。
  static Future<void> enrichMlbPlayersForMarks(Connection conn) async {
    await harvestMlbPlayerUrlsFromRankings(conn);

    final clubRows = await conn.execute(AppSql.selectTeams());
    final clubs = clubRows
        .map((row) => CareerClub(
              id: row[0] as int,
              league: row[1] as int,
              shortName: '${row[2] ?? ''}',
              fullName: '${row[3] ?? ''}',
              url: '${row[4] ?? ''}',
            ))
        .toList();
    final year = DateTimeTool.getThisYear();
    // 生年月日未登録、または前年MLB年が無い選手を補完。
    final players = await conn.execute(
      '''
        SELECT p.id, p.url, p.date_birth, p.name_full
        FROM m_player p
        WHERE COALESCE(p.flg_delete, FALSE) = FALSE
          AND COALESCE(p.url, '') <> ''
          AND EXISTS (
            SELECT 1 FROM t_stats_player_latest tsp
            WHERE tsp.id_player = p.id AND tsp.id_league IN (3, 4)
          )
          AND (
            p.date_birth IS NULL
            OR NOT EXISTS (
              SELECT 1 FROM m_player_career c
              JOIN m_team t ON t.id = c.id_team AND t.id_league IN (3, 4)
              WHERE c.id_player = p.id
                AND c.int_year < \$1
                AND COALESCE(c.flg_delete, FALSE) = FALSE
            )
          )
        ORDER BY
          CASE WHEN p.date_birth IS NULL THEN 0 ELSE 1 END,
          p.id
        LIMIT 500
      ''',
      parameters: [year],
    );
    var birthN = 0;
    var careerN = 0;
    var okN = 0;
    final total = players.length;
    for (var i = 0; i < players.length; i++) {
      final map = players[i].toColumnMap();
      final playerId = map['id'] as int;
      var url = '${map['url'] ?? ''}'.trim();
      if (url.isEmpty) continue;
      url = url.replaceFirst(RegExp(r'/top/?$'), '/');
      try {
        final doc = await YahooHtml.fetchDocument(Uri.parse(url));
        if (map['date_birth'] == null) {
          final birth = BirthPlaceRegistry.extractBirthDate(doc);
          if (birth != null) {
            await BirthPlaceRegistry.applyBirthDate(conn, playerId, birth);
            birthN++;
          }
        }
        final added = await upsertYahooMlbYearCareers(conn, playerId, doc, clubs);
        careerN += added;
        if (added > 0) okN++;
        if ((i + 1) % 25 == 0 || i + 1 == total) {
          print('MLB年度別成績: ${i + 1}/$total （累計 $careerN 行）');
        }
      } catch (e) {
        print('MLBマーク補完スキップ (${map['name_full']}): $e');
      }
    }
    print('MLBマーク補完: 生年月日 $birthN 人 / 年度別 $careerN 行 / 成功 $okN 人 / 対象 $total 人');
  }

  /// 個人成績ランキングページから、既存 m_player へプロフィール URL を紐づける（新規作成しない）。
  static Future<int> harvestMlbPlayerUrlsFromRankings(Connection conn) async {
    final pages = await conn.execute('''
      SELECT DISTINCT url
      FROM m_stats_details
      WHERE id_league IN (3, 4)
        AND COALESCE(flg_delete, FALSE) = FALSE
        AND COALESCE(url, '') <> ''
    ''');
    var updated = 0;
    var pageN = 0;
    final seenPages = <String>{};
    final seenPlayers = <String>{};
    for (final row in pages) {
      final pageUrl = '${row.toColumnMap()['url'] ?? ''}'.trim();
      if (pageUrl.isEmpty || !seenPages.add(pageUrl)) continue;
      pageN++;
      try {
        final doc = await YahooHtml.fetchDocument(Uri.parse(pageUrl));
        var pageHit = 0;
        for (final member in doc.querySelectorAll('p.bb-playerTable__member')) {
          final playerA = member.querySelector('a[href*="/mlb/player/"]');
          final href = playerA?.attributes['href']?.trim() ?? '';
          if (href.isEmpty) continue;
          final parsed = FetchURL.parseYahooRankingPlayerCell(member.text);
          if (parsed.player.isEmpty || parsed.team.isEmpty) continue;
          final profileUrl = (href.startsWith('http') ? href : 'https://baseball.yahoo.co.jp$href')
              .replaceFirst(RegExp(r'/top/?$'), '/');
          if (!seenPlayers.add(profileUrl)) continue;
          final name = StringTool.noSpace(parsed.player);
          final team = parsed.team.trim();
          // ランキング「A.ブレグマン」⇔ DB「アレックス・ブレグマン」を姓で結ぶ。
          final result = await conn.execute(
            '''
              UPDATE m_player p
              SET url = \$1::text,
                  updat = NOW()
              FROM m_team t
              WHERE p.id_team = t.id
                AND t.name_shortest = \$2::text
                AND COALESCE(p.flg_delete, FALSE) = FALSE
                AND COALESCE(p.url, '') = ''
                AND (
                  p.name_full = \$3::text
                  OR p.name_last = \$3::text
                  OR COALESCE(p.name_last, '') || COALESCE(p.name_first, '') = \$3::text
                  OR p.name_full LIKE \$3::text || '%'
                  OR \$3::text LIKE p.name_full || '%'
                  OR (
                    COALESCE(p.name_last, '') <> ''
                    AND length(p.name_last) >= 2
                    AND \$3::text LIKE '%' || p.name_last
                  )
                  OR (
                    length(regexp_replace(\$3::text, '^.*?[\\.．]', '')) >= 2
                    AND (
                      p.name_full LIKE '%' || regexp_replace(\$3::text, '^.*?[\\.．]', '')
                      OR regexp_replace(p.name_full, '^.*・', '')
                           = regexp_replace(\$3::text, '^.*?[\\.．]', '')
                      OR p.name_last = regexp_replace(\$3::text, '^.*?[\\.．]', '')
                    )
                  )
                  OR (
                    position('・' in p.name_full) > 0
                    AND length(regexp_replace(p.name_full, '^.*・', '')) >= 2
                    AND (
                      \$3::text LIKE '%' || regexp_replace(p.name_full, '^.*・', '')
                      OR regexp_replace(\$3::text, '^.*?[\\.．]', '')
                           = regexp_replace(p.name_full, '^.*・', '')
                    )
                  )
                )
            ''',
            parameters: [profileUrl, team, name],
          );
          if (result.affectedRows > 0) {
            updated += result.affectedRows;
            pageHit += result.affectedRows;
          }
        }
        print('MLBランキングURL: $pageN/${pages.length} +$pageHit ($pageUrl)');
      } catch (e) {
        print('MLBランキングURL取得スキップ ($pageUrl): $e');
      }
    }
    print('MLBランキングURL紐づけ: ${seenPages.length} ページ / URL更新 $updated 人 / ユニーク選手 ${seenPlayers.length}');
    return updated;
  }

  /// Yahoo「MLB日本人選手」一覧から国籍（日本）・URL・正式名・年度別成績を補完する。
  /// 試合速報由来の短縮名（松井 / 吉田 / 今井 など）でも球団一致＋姓一致で紐づける。
  static Future<int> syncJapanesePlayers(Connection conn) async {
    final listUrl = Uri.parse('https://baseball.yahoo.co.jp/mlb/japanese/players/');
    final doc = await YahooHtml.fetchDocument(listUrl);
    final clubRows = await conn.execute(AppSql.selectTeams());
    final clubs = clubRows
        .map((row) => CareerClub(
              id: row[0] as int,
              league: row[1] as int,
              shortName: '${row[2] ?? ''}',
              fullName: '${row[3] ?? ''}',
              url: '${row[4] ?? ''}',
            ))
        .toList();
    var updated = 0;
    var careers = 0;
    for (final item in doc.querySelectorAll('li.bb-japanesePlayer__item')) {
      final href = item.querySelector('a')?.attributes['href']?.trim() ?? '';
      final rawName = item.querySelector('.bb-japanesePlayer__name')?.text.trim() ?? '';
      final rawTeam = item.querySelector('.bb-japanesePlayer__team')?.text.trim() ?? '';
      final name = StringTool.noSpace(rawName);
      final teamName = YahooTeamNames.normalize(rawTeam);
      if (name.isEmpty || teamName.isEmpty || href.isEmpty) continue;

      final teamRows = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [teamName]);
      if (teamRows.isEmpty) {
        print('MLB日本人: 未知の球団 "$rawTeam" → "$teamName" ($name)');
        continue;
      }
      final teamId = teamRows.first.toColumnMap()['id'] as int;
      final profileUrl = href.startsWith('http') ? href : listUrl.resolve(href).toString();
      // /top 付きでもプロフィール本文は取れるが、出身地は index 相当を優先
      final profileIndex = profileUrl.replaceFirst(RegExp(r'/top/?$'), '/');

      final players = await conn.execute(
        '''
          SELECT id, name_full, id_country, url
          FROM m_player
          WHERE id_team = \$1::int
            AND COALESCE(flg_delete, FALSE) = FALSE
            AND (
              name_full = \$2::text
              OR name_last = \$2::text
              OR COALESCE(name_last, '') || COALESCE(name_first, '') = \$2::text
              OR \$2::text LIKE name_full || '%'
              OR name_full LIKE \$2::text || '%'
            )
          ORDER BY
            CASE
              WHEN name_full = \$2::text THEN 0
              WHEN COALESCE(name_last, '') || COALESCE(name_first, '') = \$2::text THEN 1
              WHEN \$2::text LIKE name_full || '%' THEN 2
              ELSE 3
            END,
            length(COALESCE(name_full, '')) DESC
          LIMIT 3
        ''',
        parameters: [teamId, name],
      );

      var playerId = 0;
      if (players.isEmpty) {
        playerId = await _ensurePlayer(conn, rawName, teamId);
      } else {
        playerId = players.first.toColumnMap()['id'] as int;
        final current = '${players.first.toColumnMap()['name_full'] ?? ''}'.trim();
        if (current.isEmpty || (name.length > current.length && name.startsWith(current))) {
          final parts = rawName.trim().split(RegExp(r'\s+'));
          final last = StringTool.noSpace(parts.isNotEmpty ? parts.first : name);
          final first = StringTool.noSpace(parts.length >= 2 ? parts.sublist(1).join() : '');
          await conn.execute(
            '''
              UPDATE m_player
              SET name_full = \$1::text,
                  name_last = \$2::text,
                  name_first = \$3::text,
                  updat = NOW()
              WHERE id = \$4::int
            ''',
            parameters: [name, last, first, playerId],
          );
        }
      }
      if (playerId <= 0) continue;

      await conn.execute(
        '''
          UPDATE m_player
          SET url = CASE WHEN COALESCE(url, '') = '' THEN \$1::text ELSE url END,
              updat = NOW()
          WHERE id = \$2::int
        ''',
        parameters: [profileIndex, playerId],
      );

      try {
        final profileDoc = await YahooHtml.fetchDocument(Uri.parse(profileIndex));
        final birthPlace = BirthPlaceRegistry.extractFromProfile(profileDoc) ?? BirthPlaceRegistry.japanName;
        await BirthPlaceRegistry.applyToPlayer(conn, playerId, birthPlace);
        await BirthPlaceRegistry.applyBirthDate(conn, playerId, BirthPlaceRegistry.extractBirthDate(profileDoc));
        final added = await upsertYahooMlbYearCareers(conn, playerId, profileDoc, clubs);
        careers += added;
        if (added > 0) print('MLB年度別成績: $name +$added行');
      } catch (e) {
        await BirthPlaceRegistry.applyToPlayer(conn, playerId, BirthPlaceRegistry.japanName);
        print('MLB日本人プロフィール取得スキップ ($name): $e');
      }
      updated++;
      print('MLB日本人補完: $name @ $teamName');
    }
    print('MLB日本人補完: $updated件 / 年度別成績新規: $careers行');
    return updated;
  }

  /// Yahoo MLB 選手ページの `#year_b` / `#year_p` から年度別所属を m_player_career へ入れる。
  /// ✨・🔰判定のため、MLB年の打数・投球回も残す。
  static Future<int> upsertYahooMlbYearCareers(
    Connection conn,
    int playerId,
    Document doc,
    List<CareerClub> clubs,
  ) async {
    final byKey = <String, m_player_career>{};

    void takeTable(String tableId, {required bool batting}) {
      final table = doc.querySelector('#$tableId');
      if (table == null) return;
      for (final tr in table.querySelectorAll('tbody tr')) {
        final yearText = tr.querySelector('.bb-playerStatsTable__dataLabel')?.text.trim() ?? '';
        final year = int.tryParse(yearText.replaceAll(RegExp(r'\s'), '')) ?? 0;
        if (year < 1900 || year > 2100) continue;
        final teamRaw = tr.querySelector('.bb-playerStatsTable__data--team')?.text.trim() ?? '';
        // チーム列が空でもセル配列の2番目に球団名がある（MLB年は <a> 表記）。
        final cells = tr.querySelectorAll('td.bb-playerStatsTable__data');
        final teamFromCell = cells.length > 1 ? cells[1].text.trim() : '';
        final teamSource = teamRaw.isNotEmpty
            ? teamRaw
            : (teamFromCell.isNotEmpty ? teamFromCell : '');
        final teamLabel = YahooTeamNames.normalize(teamSource.replaceAll(RegExp(r'\s'), ''));
        final teamId = FetchURL.matchCareerClubId(
              teamLabel.isEmpty ? teamSource : teamLabel,
              clubs,
              preferMlb: true,
            ) ??
            FetchURL.matchCareerClubId(teamSource, clubs, preferMlb: true);
        // マイナー等は m_team に無いのでスキップ（MLB/NPB 球団のみ登録）
        if (teamId == null) continue;
        final key = '$year|$teamId';
        final row = byKey.putIfAbsent(key, () {
          final created = m_player_career()
            ..id_player = playerId
            ..int_year = year
            ..id_team = teamId;
          return created;
        });
        // year_b: 打率,試合,打席,打数… / year_p: 防御率,登板,先発,…,投球回(15)
        // cells[0]=年度 cells[1]=チーム 以降が成績
        if (batting && cells.length >= 6) {
          row.double_average_batting = _yahooStatDouble(cells, 2);
          row.int_games = _yahooStatInt(cells, 3);
          row.int_appearance = _yahooStatInt(cells, 4);
          row.int_batting = _yahooStatInt(cells, 5);
        } else if (!batting && cells.length >= 16) {
          // year_p: 防御率,登板,先発,…,QS,勝,敗,…,投球回, …,奪三振
          row.double_average_earned_runs = _yahooStatDouble(cells, 2);
          row.int_pitching = _yahooStatInt(cells, 3);
          row.int_games = _yahooStatInt(cells, 4);
          row.int_win = _yahooStatInt(cells, 9);
          row.int_lose = _yahooStatInt(cells, 10);
          row.double_inning = _yahooStatDouble(cells, 15);
          row.int_strike_out_pitcher = _yahooStatInt(cells, 20);
          if (row.int_strike_out_pitcher <= 0) {
            // 列構成差のフォールバック（与死球の次が奪三振の旧レイアウト）
            row.int_strike_out_pitcher = _yahooStatInt(cells, 19);
          }
        }
      }
    }

    takeTable('year_b', batting: true);
    takeTable('year_p', batting: false);
    if (byKey.isEmpty) return 0;

    var upserted = 0;
    for (final row in byKey.values) {
      final existing = await conn.execute(
        '''
          SELECT id FROM m_player_career
          WHERE id_player = \$1::int
            AND int_year = \$2::int
            AND id_team = \$3::int
            AND COALESCE(flg_delete, FALSE) = FALSE
          LIMIT 1
        ''',
        parameters: [row.id_player, row.int_year, row.id_team],
      );
      if (existing.isEmpty) {
        await Postgres.insert(conn, row);
        upserted++;
        continue;
      }
      await conn.execute(
        '''
          UPDATE m_player_career
          SET int_games = GREATEST(COALESCE(int_games, 0), \$1::int),
              int_appearance = GREATEST(COALESCE(int_appearance, 0), \$2::int),
              int_batting = GREATEST(COALESCE(int_batting, 0), \$3::int),
              int_pitching = GREATEST(COALESCE(int_pitching, 0), \$4::int),
              double_inning = GREATEST(COALESCE(double_inning, 0), \$5::float8),
              int_win = GREATEST(COALESCE(int_win, 0), \$6::int),
              int_lose = GREATEST(COALESCE(int_lose, 0), \$7::int),
              int_strike_out_pitcher = GREATEST(COALESCE(int_strike_out_pitcher, 0), \$8::int),
              double_average_batting = CASE
                WHEN \$9::float8 > 0 THEN \$9::float8 ELSE COALESCE(double_average_batting, 0) END,
              double_average_earned_runs = CASE
                WHEN \$10::float8 > 0 THEN \$10::float8 ELSE COALESCE(double_average_earned_runs, 0) END,
              updat = NOW()
          WHERE id = \$11::int
        ''',
        parameters: [
          row.int_games,
          row.int_appearance,
          row.int_batting,
          row.int_pitching,
          row.double_inning,
          row.int_win,
          row.int_lose,
          row.int_strike_out_pitcher,
          row.double_average_batting,
          row.double_average_earned_runs,
          existing.first.toColumnMap()['id'],
        ],
      );
      upserted++;
    }
    return upserted;
  }

  static int _yahooStatInt(List<Element> cells, int index) {
    if (index >= cells.length) return 0;
    final text = cells[index].text.trim().replaceAll(',', '');
    if (text.isEmpty || text == '-') return 0;
    return int.tryParse(text) ?? 0;
  }

  static double _yahooStatDouble(List<Element> cells, int index) {
    if (index >= cells.length) return 0;
    final text = cells[index].text.trim().replaceAll(',', '');
    if (text.isEmpty || text == '-') return 0;
    return double.tryParse(text) ?? 0;
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

  /// 今日→昨日→先の日程→古い日。進行中の更新を後回しにしない。
  static List<DateTime> scheduleDates(DateTime now, {bool includeFuture = true, bool todayOnly = false}) {
    if (todayOnly) return [DateTime(now.year, now.month, now.day)];
    final offsets = [for (var i = -3; i <= 10; i++) i];
    offsets.sort((a, b) {
      int rank(int offset) {
        if (offset == 0) return 0;
        if (offset == -1) return 1;
        if (offset > 0) return 10 + offset;
        return 20 + offset.abs();
      }
      return rank(a).compareTo(rank(b));
    });
    return [
      for (final offset in offsets)
        if (includeFuture || offset <= 0) now.add(Duration(days: offset)),
    ];
  }

  /// 途中までの試合更新を読み取り側へ見せる。長時間の1トランザクションに閉じ込めない。
  static Future<void> _publishProgress(Connection conn) async {
    try {
      await Postgres.commit(conn);
    } catch (_) {}
    try {
      await Postgres.begin(conn);
    } catch (_) {}
  }

  static Future<({int id, String state, bool loaded})?> _gameOnDate(
    Connection conn,
    int idTeamHome,
    int idTeamAway,
    String date,
  ) async {
    final rows = await conn.execute(
      '''
        SELECT
          g.id,
          COALESCE(g.state, '') AS state,
          COALESCE(g.flg_stats_loaded, FALSE) AS loaded
        FROM t_game g
        WHERE g.id_team_home = \$1::int
          AND g.id_team_away = \$2::int
          AND g.datetime_start::date = \$3::date
          AND COALESCE(g.flg_delete, FALSE) = FALSE
        ORDER BY CASE WHEN g.id < 2000 THEN 0 ELSE 1 END, g.datetime_start
        LIMIT 1
      ''',
      parameters: [idTeamHome, idTeamAway, date],
    );
    if (rows.isEmpty) return null;
    final map = rows.first.toColumnMap();
    return (
      id: map['id'] as int,
      state: '${map['state'] ?? ''}',
      loaded: map['loaded'] == true,
    );
  }

  /// 今日の分だけ取り直し。全部読み終わっていたら次の 10 秒ループを止める。
  static Future<bool> refreshToday() async {
    var keep = true;
    await Postgres.withConnection((conn) async {
      await FetchURL.ensureGameDetailsVelo(conn);
      await FetchURL.ensureAppColumns(conn);
      try {
        await Postgres.begin(conn);
      } catch (_) {}
      await fetchGames(conn, todayOnly: true);
      try {
        await Postgres.commit(conn);
      } catch (_) {}
      final key = DateFormat('yyyy-MM-dd').format(DateTime.now());
      keep = !await GameStatsLoad.isDateFullyLoaded(conn, key, _org.leagueIds);
    });
    return keep;
  }

  /// 日程カード＋試合トップから試合情報を登録。ポストシーズンも含める。
  static Future<Response> fetchGames(Connection conn, {bool todayOnly = false}) async {
    await FetchURL.ensureGameDetailsVelo(conn);
    await FetchURL.ensureAppColumns(conn);
    final now = DateTime.now();
    final includeFuture = !todayOnly && GameFetchSchedule.takeFuture('mlb', now);
    if (!todayOnly && !includeFuture) print('MLB明日以降は${GameFetchSchedule.futureInterval.inMinutes}分以内のためスキップ');
    final dates = scheduleDates(now, includeFuture: includeFuture, todayOnly: todayOnly);
    final formatter = DateFormat('yyyy-MM-dd');
    final todayKey = formatter.format(now);
    final clubs = await _careerClubs(conn);

    for (final date in dates) {
      final formatted = formatter.format(date);
      final isToday = formatted == todayKey;
      var lockedToday = false;
      if (isToday && !todayOnly) {
        if (GameFetchSchedule.isTodayBusy('mlb')) {
          print('MLB $formatted は取得中のためスキップ');
          continue;
        }
        GameFetchSchedule.markTodayBusy('mlb', true);
        lockedToday = true;
      }
      try {
      if (await GameStatsLoad.skipPastSchedule(
        conn,
        org: 'mlb',
        date: date,
        now: now,
        leagueIds: _org.leagueIds,
      )) {
        print('MLB $formatted は成績済のためスキップ');
        continue;
      }
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
        if (GameFetchSchedule.isPastDay(date, now)) {
          await GameStatsLoad.rememberPastDateIfSettled(
            conn,
            org: 'mlb',
            date: formatted,
            leagueIds: _org.leagueIds,
            emptySchedule: true,
          );
        }
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

          final cardLive = status.contains('試合中') || RegExp(r'\d+\s*回').hasMatch(status);
          final known = await _gameOnDate(conn, idTeamHome, idTeamAway, formatted);
          if (!GameStatsLoad.needsRefresh(live: cardLive, loaded: known?.loaded == true)) {
            print('MLB試合スキップ(成績済): $homeName vs $awayName');
            continue;
          }

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
                final homePitcher = _starterLink(detail, home: true);
                final awayPitcher = _starterLink(detail, home: false);
                if (homePitcher.name.isNotEmpty) {
                  idPitcherHome = await _ensurePlayer(conn, homePitcher.name, idTeamHome);
                  await _syncStarterSeasonStats(
                    conn,
                    playerId: idPitcherHome,
                    detailUrl: detailUrl,
                    profileHref: homePitcher.href,
                    clubs: clubs,
                  );
                }
                if (awayPitcher.name.isNotEmpty) {
                  idPitcherAway = await _ensurePlayer(conn, awayPitcher.name, idTeamAway);
                  await _syncStarterSeasonStats(
                    conn,
                    playerId: idPitcherAway,
                    detailUrl: detailUrl,
                    profileHref: awayPitcher.href,
                    clubs: clubs,
                  );
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
                  final anchor = tds.first.querySelector('a');
                  final hrefPlayer = anchor?.attributes['href']?.trim() ?? '';
                  var namePlayer = StringTool.noSpace(anchor?.text ?? '');
                  if ((namePlayer.isEmpty && hrefPlayer.isEmpty) || teamName.isEmpty) continue;
                  final teamResult = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [teamName]);
                  if (teamResult.isEmpty) continue;
                  final idTeam = teamResult.first.toColumnMap()['id'] as int;
                  if (namePlayer.isEmpty && hrefPlayer.isNotEmpty) {
                    final playerDoc = await YahooHtml.fetchDocument(detailUrl.resolve(hrefPlayer));
                    namePlayer = playerDoc.querySelectorAll('ruby.bb-profile__ruby').isEmpty
                        ? ''
                        : playerDoc.querySelectorAll('ruby.bb-profile__ruby').first.text.split('（').first.trim();
                    if (namePlayer.isEmpty) continue;
                    final idPlayer = await _ensurePlayer(conn, namePlayer, idTeam);
                    await BirthPlaceRegistry.applyFromProfile(conn, idPlayer, playerDoc);
                    if (result == '勝利投手') idPitcherWin = idPlayer;
                    if (result == '敗戦投手') idPitcherLose = idPlayer;
                    if (result == 'セーブ') idPitcherSave = idPlayer;
                    continue;
                  }
                  if (namePlayer.isEmpty) continue;
                  final idPlayer = await _ensurePlayer(conn, namePlayer, idTeam);
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
            final paths = StadiumImages.lookup(stadiumName);
            final stadium = m_stadium()
              ..name_short = stadiumName
              ..id_team = idTeamHome
              ..path_image_inside = paths.inside
              ..path_image_outside = paths.outside;
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

          if (exists.isNotEmpty) {
            game.id = exists.first.toColumnMap()['id'] as int;
            await Postgres.update(conn, game);
            print('MLB試合更新: $homeName vs $awayName');
          } else if (known != null) {
            game.id = known.id;
            await Postgres.update(conn, game);
            print('MLB試合更新: $homeName vs $awayName');
          } else {
            game.id = await Postgres.insert(conn, game);
            print('MLB試合新規: $homeName vs $awayName');
          }

          final live = matchState.contains('試合中') || RegExp(r'\d+\s*回').hasMatch(matchState);
          final finished = matchState.contains('試合終了');
          final started = live || finished || matchState.contains('終了');
          final scrapeStats = started && formatted.compareTo(todayKey) <= 0;
          if (scrapeStats && href.isNotEmpty && game.id > 0) {
            try {
              final statsUrl = url.resolve(FetchURL.gamePageHref(href, 'stats'));
              await _saveGameBoxSummary(conn, statsUrl, game.id, idTeamHome, idTeamAway);
            } catch (e, st) {
              print('MLB出場成績スキップ ($homeName vs $awayName): $e');
              print(st);
            }
            try {
              await FetchURL.refreshGameDetails(
                conn,
                url,
                href,
                game.id,
                idTeamHome,
                idTeamAway,
                idPitcherHome,
                idPitcherAway,
                saveMaxVelo: finished,
              );
            } catch (e, st) {
              print('MLB打席・テキスト速報スキップ ($homeName vs $awayName): $e');
              print(st);
            }
            await GameStatsLoad.markIfComplete(conn, game.id, finished: finished);
          }
          if (live || formatted == todayKey) {
            await _publishProgress(conn);
          }
        }
      }
      if (GameFetchSchedule.isPastDay(date, now)) {
        await GameStatsLoad.rememberPastDateIfSettled(
          conn,
          org: 'mlb',
          date: formatted,
          leagueIds: _org.leagueIds,
        );
      }
      } finally {
        if (lockedToday) {
          GameFetchSchedule.markTodayBusy('mlb', false);
          GameFetchSchedule.scheduleTodayAgain('mlb', refreshToday);
        }
      }
    }
    return Response.ok('ok');
  }

  /// Yahoo MLB 出場成績から t_game_summary を入れ直す。
  static Future<void> _saveGameBoxSummary(
    Connection conn,
    Uri statsUrl,
    int gameId,
    int idTeamHome,
    int idTeamAway,
  ) async {
    final doc = await YahooHtml.fetchDocument(statsUrl);
    final groups = batterStatsGroups(doc, idTeamAway, idTeamHome);
    if (groups.every((group) => group.rows.isEmpty)) return;

    final list = <t_game_summary>[];
    for (final group in groups) {
    var teamId = group.teamId;
    var switched = false;
    final battingTracker = BoxBattingOrderTracker();
    for (final row in group.rows) {
      if (row.querySelectorAll('th').isNotEmpty) {
        if (group.switchOnTh && !switched) {
          teamId = idTeamHome;
          switched = true;
          battingTracker.reset();
        }
        continue;
      }
      final cells = row.querySelectorAll('td');
      if (cells.length < 14) continue;
      final name = StringTool.noSpace(cells[1].text);
      if (name.isEmpty) continue;
      final battingSlot = battingTracker.take(cells.first.text);
      final playerId = await _ensurePlayer(conn, cells[1].text.trim(), teamId);
      if (playerId <= 0) continue;
      final summary = t_game_summary()
        ..id_game = gameId
        ..id_player = playerId
        ..int_batting = int.tryParse(cells[3].text.trim()) ?? 0
        ..int_hit1 = int.tryParse(cells[5].text.trim()) ?? 0
        ..int_rbi = int.tryParse(cells[6].text.trim()) ?? 0
        ..int_fourball = int.tryParse(cells[8].text.trim()) ?? 0
        ..int_dead_batting = int.tryParse(cells[9].text.trim()) ?? 0
        ..int_sacrifice = int.tryParse(cells[10].text.trim()) ?? 0
        ..int_steal_base = int.tryParse(cells[11].text.trim()) ?? 0
        ..int_error = int.tryParse(cells[12].text.trim()) ?? 0
        ..int_homerun = int.tryParse(cells[13].text.trim()) ?? 0
        ..int_batting_order = battingSlot.originalStarter ? battingSlot.order : 0
        ..code_position_from = boxBadgePosition(cells.first.text);
      list.add(summary);
    }
    }

    var pitcherTeam = idTeamAway;
    for (final section in doc.querySelectorAll('#async-gamePitcherStats section')) {
      final rows = section.querySelectorAll('table tbody tr');
      if (rows.isEmpty) {
        pitcherTeam = idTeamHome;
        continue;
      }
      final heads = section.querySelectorAll('table thead th').map((cell) => cell.text.trim()).toList();
      String cellOf(Element row, String header) {
        final index = heads.indexOf(header);
        final cells = row.querySelectorAll('td');
        if (index < 0 || index >= cells.length) return '';
        return cells[index].text.trim();
      }

      for (final row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 2) continue;
        final resultText = cells.first.text.trim();
        var pitcherName = cellOf(row, '選手名');
        if (pitcherName.isEmpty) pitcherName = cells[1].text.trim();
        final playerId = await _ensurePlayer(conn, pitcherName, pitcherTeam);
        if (playerId <= 0) continue;

        var summary = t_game_summary();
        for (var i = 0; i < list.length; i++) {
          if (list[i].id_player == playerId) {
            summary = list.removeAt(i);
            break;
          }
        }
        if (resultText.contains('勝')) {
          summary.code_result_pitcher = Value.CodeGameResultPitcher.WIN;
        } else if (resultText.contains('敗')) {
          summary.code_result_pitcher = Value.CodeGameResultPitcher.LOSE;
        } else if (resultText.contains('Ｓ') || resultText.contains('セーブ')) {
          summary.code_result_pitcher = Value.CodeGameResultPitcher.SAVE;
        } else if (resultText.contains('H') || resultText.contains('ホールド')) {
          summary.code_result_pitcher = Value.CodeGameResultPitcher.HOLD;
        }
        summary
          ..id_game = gameId
          ..id_player = playerId
          ..double_inning_pitch = double.tryParse(cellOf(row, '投球回')) ?? 0
          ..int_pitch = int.tryParse(cellOf(row, '投球数')) ?? 0
          ..int_hit = int.tryParse(cellOf(row, '被安打')) ?? 0
          ..int_strike_out = int.tryParse(cellOf(row, '奪三振')) ?? 0
          ..int_four = int.tryParse(cellOf(row, '与四球')) ?? 0
          ..int_dead_pitching = int.tryParse(cellOf(row, '与死球')) ?? 0
          ..int_balk = int.tryParse(cellOf(row, 'ボーク')) ?? 0
          ..int_runs = int.tryParse(cellOf(row, '失点')) ?? 0
          ..int_runs_earned = int.tryParse(cellOf(row, '自責点')) ?? 0;
        list.add(summary);
      }
      pitcherTeam = idTeamHome;
    }

    if (list.isEmpty) return;
    await Postgres.execute(conn, AppSql.deleteGameSummary(), data: [gameId]);
    await Postgres.insertMulti(conn, list);
    print('MLB出場成績を登録: game=$gameId (${list.length}人)');
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

  static Future<List<CareerClub>> _careerClubs(Connection conn) async {
    final clubRows = await conn.execute(AppSql.selectTeams());
    return [
      for (final row in clubRows)
        CareerClub(
          id: row[0] as int,
          league: row[1] as int,
          shortName: '${row[2] ?? ''}',
          fullName: '${row[3] ?? ''}',
          url: '${row[4] ?? ''}',
        ),
    ];
  }

  /// 予告先発の今季成績（勝敗・防御率・奪三振・規定到達率）をプロフィールから m_player_career へ入れる。
  static Future<void> _syncStarterSeasonStats(
    Connection conn, {
    required int playerId,
    required Uri detailUrl,
    required String profileHref,
    required List<CareerClub> clubs,
  }) async {
    if (playerId <= 0) return;
    final year = DateTime.now().year;
    try {
      final have = await conn.execute(
        '''
          SELECT 1
          FROM m_player_career
          WHERE id_player = \$1::int
            AND int_year = \$2::int
            AND COALESCE(int_pitching, 0) > 0
          LIMIT 1
        ''',
        parameters: [playerId, year],
      );
      if (have.isNotEmpty) return;
    } catch (_) {}
    Uri? profileUrl;
    if (profileHref.isNotEmpty) {
      profileUrl = detailUrl.resolve(profileHref);
    } else {
      final rows = await conn.execute(
        'SELECT url FROM m_player WHERE id = \$1::int LIMIT 1',
        parameters: [playerId],
      );
      final saved = rows.isEmpty ? '' : '${rows.first.toColumnMap()['url'] ?? ''}'.trim();
      if (saved.isNotEmpty) profileUrl = Uri.parse(saved);
    }
    if (profileUrl == null) return;
    try {
      final doc = await YahooHtml.fetchDocument(profileUrl);
      final n = await upsertYahooMlbYearCareers(conn, playerId, doc, clubs);
      await BirthPlaceRegistry.applyFromProfile(conn, playerId, doc);
      await conn.execute(
        '''
          UPDATE m_player
          SET url = CASE WHEN COALESCE(url, '') = '' THEN \$1::text ELSE url END,
              updat = NOW()
          WHERE id = \$2::int
        ''',
        parameters: [profileUrl.toString(), playerId],
      );
      if (n > 0) print('MLB先発シーズン成績: player=$playerId +$n');
    } catch (e) {
      print('MLB先発シーズン成績スキップ (player=$playerId): $e');
    }
  }

  static ({String name, String href}) _starterLink(Document detail, {required bool home}) {
    final sectionIndex = home ? 0 : 1;
    Element? anchor;
    try {
      anchor = detail
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
          .querySelector('a');
    } catch (_) {
      try {
        anchor = detail
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
            .querySelector('a');
      } catch (_) {
        anchor = null;
      }
    }
    if (anchor == null) return (name: '', href: '');
    return (
      name: anchor.text.trim(),
      href: anchor.attributes['href']?.trim() ?? '',
    );
  }

  static Future<int> _ensurePlayer(Connection conn, String rawName, int teamId) async {
    final name = StringTool.noSpace(rawName);
    if (name.isEmpty) return 0;
    final parsed = parsePlayerName(name);
    try {
      final rows = await conn.execute(
        '''
          SELECT id, name_full, name_last, COALESCE(name_first_initial, '') AS name_first_initial
          FROM m_player
          WHERE id_team = \$1::int
            AND COALESCE(flg_delete, FALSE) = FALSE
        ''',
        parameters: [teamId],
      );
      final candidates = <({int id, String nameFull, String nameLast, String initial})>[];
      for (final row in rows) {
        final map = row.toColumnMap();
        final full = StringTool.noSpace('${map['name_full'] ?? ''}');
        final last = StringTool.noSpace('${map['name_last'] ?? ''}');
        final initial = '${map['name_first_initial'] ?? ''}'.trim().toUpperCase();
        if (!playerNameMatches(query: name, nameFull: full, nameLast: last, storedInitial: initial)) {
          continue;
        }
        candidates.add((
          id: map['id'] as int,
          nameFull: full,
          nameLast: last,
          initial: initial,
        ));
      }
      final picked = pickBestPlayerId(query: name, candidates: candidates);
      if (picked != null) {
        if (parsed.hasInitial) {
          await conn.execute(
            '''
              UPDATE m_player
              SET name_first_initial = CASE
                    WHEN COALESCE(BTRIM(name_first_initial), '') = '' THEN \$1::text
                    ELSE name_first_initial
                  END,
                  updat = NOW()
              WHERE id = \$2::int
            ''',
            parameters: [parsed.initial, picked],
          );
        }
        return picked;
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
    if (parsed.hasInitial) {
      player.name_first_initial = parsed.initial!;
    } else {
      final fromName = extractNameFirstInitial(player.name_full) ?? extractNameFirstInitial(player.name_last);
      if (fromName != null) player.name_first_initial = fromName;
    }
    player.id_team = teamId;
    return Postgres.insert(conn, player);
  }
}
