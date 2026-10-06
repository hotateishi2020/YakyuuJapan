import 'package:http/http.dart' as http;

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'AppSql.dart';
import '../tools/Postgres.dart';
import '../tools/StringTool.dart';
import '../tools/DateTimeTool.dart';
import '../tools/DBModel.dart';
import 'DB/m_player.dart';
import 'DB/m_player_career.dart';
import 'DB/t_game_details.dart';
import 'BoxScore.dart';
import 'LiveText.dart';
import 'DB/t_game_summary.dart';
import 'DB/t_stats_player.dart';
import 'DB/t_stats_player_latest.dart';
import 'DB/t_game.dart';
import 'DB/m_stadium.dart';
import 'DB/t_stats_team.dart';
import 'package:intl/intl.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'BirthPlaceRegistry.dart';
import 'Postseason.dart';
import 'Value.dart';
import 'YahooTeamNames.dart';
import 'YahooHtml.dart';
import 'PlayerName.dart';

/// 「18:00」や「18：00」を、その日の開始時刻にする。読めなければ null。
DateTime? gameStartOn(String date, String raw) {
  final match = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{2})').firstMatch(raw);
  if (match == null) return null;
  final hour = match.group(1)!.padLeft(2, '0');
  final minute = match.group(2)!;
  return DateTime.tryParse('$date $hour:$minute:00');
}

class FetchURL {
  static String decodeHtmlResponse(http.Response res) => _decodeHtml(res);

  /// Yahoo 試合URLの index/top/stats/text を目的ページへ揃える（NPB・MLB共通）。
  static String gamePageHref(String href, String kind) {
    var path = href.trim();
    for (final from in const ['index', 'top', 'stats', 'text', 'score']) {
      if (path.contains(from)) {
        path = path.replaceFirst(from, kind);
        break;
      }
    }
    return path;
  }

  static bool _veloColumnReady = false;

  static Future<void> ensureGameDetailsVelo([Connection? conn]) async {
    if (_veloColumnReady) return;
    Future<void> run(Connection c) async {
      await c.execute('ALTER TABLE t_game_details ADD COLUMN IF NOT EXISTS int_velo integer');
      _veloColumnReady = true;
    }

    if (conn != null) {
      await run(conn);
      return;
    }
    await Postgres.withConnection(run);
  }

  // Detect encoding (header/meta) and decode bytes accordingly (UTF-8 preferred)
  static String _decodeHtml(http.Response res) {
    final bytes = res.bodyBytes;
    String? charset;
    final ct = res.headers['content-type'] ?? res.headers['Content-Type'];
    if (ct != null) {
      final m = RegExp(r'charset=([A-Za-z0-9_\-]+)', caseSensitive: false).firstMatch(ct);
      if (m != null) charset = m.group(1)?.toLowerCase();
    }
    charset ??= _detectCharsetFromMeta(bytes);

    // Prefer UTF-8; otherwise fall back to latin1 to avoid exceptions
    if (charset == null || charset.contains('utf')) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    // latin1 fallback (header/meta missing or unexpected values)
    return latin1.decode(bytes, allowInvalid: true);
  }

  static String? _detectCharsetFromMeta(Uint8List bytes) {
    final headLen = min(bytes.length, 4096);
    final head = latin1.decode(bytes.sublist(0, headLen), allowInvalid: true);
    final m = RegExp(r'charset\s*=\s*([A-Za-z0-9_\-]+)', caseSensitive: false).firstMatch(head);
    return m?.group(1)?.toLowerCase();
  }

  /// 試合トップの本塁打欄から、選手名 → 今季号数のリストを取り出す。
  static Map<String, List<int>> _parseHomerunTotalsFromTop(Document doc) {
    final totals = <String, List<int>>{};
    final section = doc.querySelector('#async-homerun') ?? doc.querySelector('#homerun');
    if (section == null) return totals;

    for (final td in section.querySelectorAll('td')) {
      final players = td.querySelectorAll('a.bb-gameTable__player');
      if (players.isEmpty) continue;

      var rest = StringTool.noSpace(td.text);
      for (var i = 0; i < players.length; i++) {
        final name = StringTool.noSpace(players[i].text.trim());
        if (name.isEmpty) continue;

        final start = rest.indexOf(name);
        var chunk = rest;
        if (start >= 0) {
          chunk = rest.substring(start + name.length);
          if (i + 1 < players.length) {
            final nextName = StringTool.noSpace(players[i + 1].text.trim());
            if (nextName.isNotEmpty) {
              final nextAt = chunk.indexOf(nextName);
              if (nextAt >= 0) {
                rest = chunk.substring(nextAt);
                chunk = chunk.substring(0, nextAt);
              }
            }
          }
        }

        final nums = <int>[
          for (final m in RegExp(r'(\d+)号').allMatches(chunk))
            if (int.tryParse(m.group(1) ?? '') != null) int.parse(m.group(1)!),
        ];
        if (nums.isNotEmpty) {
          totals.putIfAbsent(name, () => []).addAll(nums);
        }
      }
    }
    return totals;
  }

  /// 出場成績の打者名に、トップページで取った号数を "11, 12" 形式で結びつける。
  static String _homerunTotalForBatter(String batterName, int homerCount, Map<String, List<int>> totals) {
    if (homerCount <= 0 || totals.isEmpty) return '';
    final key = StringTool.noSpace(batterName);
    if (key.isEmpty) return '';

    final exact = totals[key];
    if (exact != null && exact.isNotEmpty) {
      return exact.join(', ');
    }

    String? best;
    var bestLen = 0;
    for (final name in totals.keys) {
      if (name.isEmpty) continue;
      final matched = key.startsWith(name) || name.startsWith(key);
      if (!matched) continue;
      if (name.length > bestLen) {
        bestLen = name.length;
        best = name;
      }
    }
    final nums = best == null ? null : totals[best];
    if (nums == null || nums.isEmpty) return '';
    return nums.join(', ');
  }

  /// 最終試合の翌日以降、来シーズン開幕日の前日までは公式戦の定期取得を止める。
  static Future<bool> isOfficialSeasonBreak(Connection conn) async {
    final rows = await conn.execute(
      AppSql.selectOfficialSeasonBreak(),
      parameters: [
        Value.SystemCode.Code.ADMIN,
        Value.SystemCode.Key.DATE_FINAL_GAME,
        Value.SystemCode.Key.DATE_OPEN_GAME,
      ],
    );
    if (rows.isEmpty) return false;
    final value = rows.first.toColumnMap()['flg_break'];
    if (value == true) return true;
    final text = '$value'.trim().toLowerCase();
    return text == 'true' || text == 't';
  }

  static Future<Response> fetchStatsTeamNPB(Connection conn) async {
    final url = Uri.parse('https://baseball.yahoo.co.jp/npb/standings/');
    final res = await http.get(url);

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch standings');
    }

    final html = _decodeHtml(res);
    final document = parse(html);
    final html_tables = document.querySelectorAll('table.bb-rankTable');
    var cnt = 0;
    List<t_stats_team> teams = [];

    for (final html_table in html_tables) {
      if (cnt == 2) {
        break;
      }

      final html_teams = html_table.querySelectorAll('tbody tr');

      for (final html_team in html_teams) {
        final cells = html_team.querySelectorAll('td');
        if (cells.length >= 3) {
          var team_name = cells[1].text.trim();
          var r_team = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [team_name]);
          if (r_team.isEmpty) continue;
          var team = t_stats_team();
          team.id_league = cnt + 1;
          if (cells[0].text.trim() == '優勝') {
            team.int_rank = 1;
            team.game_behind = '優勝';
          } else {
            team.int_rank = int.tryParse(cells[0].text.trim()) ?? 0;
            team.game_behind = cells[7].text.trim();
          }

          team.year = DateTimeTool.getThisYear();
          team.id_team = r_team.first.toColumnMap()['id'];
          team.int_game = int.tryParse(cells[2].text.trim()) ?? 0;
          team.int_win = int.tryParse(cells[3].text.trim()) ?? 0;
          team.int_lose = int.tryParse(cells[4].text.trim()) ?? 0;
          team.int_draw = int.tryParse(cells[5].text.trim()) ?? 0;
          team.int_rbi = int.tryParse(cells[9].text.trim()) ?? 0;
          team.int_homerun = int.tryParse(cells[11].text.trim()) ?? 0;
          team.int_sh = int.tryParse(cells[12].text.trim()) ?? 0;
          team.num_avg_batting = double.tryParse("0" + cells[13].text.trim()) ?? 0;
          team.num_era_total = double.tryParse(cells[14].text.trim()) ?? 0;
          teams.add(team);
          print(team_name + 'の基本情報を登録します。');
        }
      } //for html各チーム
      cnt++;
    } //for htmlリーグ

    //先発防御率と中継ぎ防御率
    var urls_pitching = [];
    urls_pitching.add('https://baseballdata.jp/c/#');
    urls_pitching.add('https://baseballdata.jp/p/');
    var urls_defence = [];
    urls_defence.add('https://npb.jp/bis/2025/stats/tmf_c.html');
    urls_defence.add('https://npb.jp/bis/2025/stats/tmf_p.html');

    for (int i = 0; i < 2; i++) {
      //先発防御率・中継ぎ防御率をスクレイピング
      print("🔷先発防御率・中継ぎ防御率をスクレイピングします。");
      final url_pitching = Uri.parse(urls_pitching[i]);
      final res_pitching = await http.get(url_pitching);

      if (res_pitching.statusCode != 200) {
        throw Exception('Failed to fetch standings');
      }

      final htmlPitching = _decodeHtml(res_pitching);
      final document = parse(htmlPitching);
      final divs = document.querySelectorAll('body section.content-panel');
      final rows = divs[2].querySelectorAll('table.pitching-table tbody tr');

      for (final tr in rows) {
        print("🟢先発防御率・中継ぎ防御率をスクレイピングします。");
        final ths = tr.querySelectorAll('th');
        final tds = tr.querySelectorAll('td');
        if (ths.isEmpty || tds.length < 3) {
          print("continue");
          continue;
        }
        var team_name = ths[0].text.trim();
        if (team_name == '阪') {
          team_name = '神';
        } else if (team_name == 'D') {
          team_name = 'デ';
        }
        var pitching_rate_starter = tds[1].text.trim();
        var pitching_rate_reliever = tds[2].text.trim();
        print("先発防御率：" + pitching_rate_starter);
        print("中継ぎ防御率：" + pitching_rate_reliever);
        var r_team = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [team_name]);
        if (r_team.isEmpty) {
          // チーム名が一致しないケースはスキップ
          print('防御率のチーム名' + team_name + 'に該当するデータが見つかりませんでした。');
          continue;
        }
        var idx = Postgres.findIndex(teams, 'id_team', r_team.first.toColumnMap()['id']);
        if (idx < 0 || idx >= teams.length) {
          print('インデックスが見つかりませんでした。');
          continue;
        }
        teams[idx].num_era_starter = double.tryParse(pitching_rate_starter) ?? 0;
        teams[idx].num_era_relief = double.tryParse(pitching_rate_reliever) ?? 0;
      }

      //チーム守備率をスクレイピング
      final url_defence = Uri.parse(urls_defence[i]);
      final res_defence = await http.get(url_defence);

      if (res_defence.statusCode != 200) {
        throw Exception('Failed to fetch standings');
      }

      final htmlDefence = _decodeHtml(res_defence);
      final document_defence = parse(htmlDefence);
      final rows_defence = document_defence.querySelectorAll('table tbody tr');

      for (final tr_defence in rows_defence) {
        // 先頭行（ヘッダーなど）はスキップ
        // if (cnt < 2) {
        //   cnt++;
        //   continue;
        // }

        final tds = tr_defence.querySelectorAll('td');
        if (tds.length < 2) {
          continue;
        }

        var team_name_defence = tds[0].text.trim();
        print("守備率チーム名：" + team_name_defence);
        var defence_rate = tds[1].text.trim();
        var r_team_defence = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [StringTool.noSpace(team_name_defence)]);

        print(team_name_defence);
        print(defence_rate);

        if (r_team_defence.isEmpty) {
          print('守備率のチーム名' + team_name_defence + 'に該当するデータが見つかりませんでした。');
          continue;
        }

        var idx_defence = Postgres.findIndex(teams, 'id_team', r_team_defence.first.toColumnMap()['id']);
        if (idx_defence < 0 || idx_defence >= teams.length) {
          print('インデックスが見つかりませんでした。');
          continue;
        }
        teams[idx_defence].num_avg_fielding = double.tryParse(defence_rate) ?? 0;
      }
    }

    await Postgres.insertMulti(conn, teams);
    return Response.ok('ok');
  }

  static bool _withinRecentDays(DateTime date, DateTime now, {int days = 2}) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(today.subtract(Duration(days: days))) && !day.isAfter(today);
  }

  /// CS・日本シリーズなど、日程カードから既存試合の打席・球速を取り直す。
  static Future<void> refreshRecentPostseasonDetails(Connection conn) async {
    await ensureGameDetailsVelo(conn);
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd');
    for (var i = -2; i <= 0; i++) {
      final date = now.add(Duration(days: i));
      final formatted = formatter.format(date);
      final url = Uri.parse('https://baseball.yahoo.co.jp/npb/schedule/?date=$formatted');
      try {
        final document = await YahooHtml.fetchDocument(url);
        final root = document.querySelector('#gm_card');
        if (root == null) continue;
        for (final section in root.querySelectorAll('section')) {
          final title = section.querySelector('.bb-score__title')?.text.trim() ?? '';
          if (!isPostseasonHeading(title)) continue;
          await _refreshStartedCards(conn, url, section, formatted);
        }
      } catch (e) {
        print('ポストシーズン一球速報の再取得に失敗しました ($formatted): $e');
      }
    }
  }

  static Future<void> _refreshStartedCards(
    Connection conn,
    Uri pageUrl,
    Element section,
    String date,
  ) async {
    final cards = section.querySelectorAll('li.bb-score__item');
    final items = cards.isNotEmpty ? cards : section.querySelectorAll('li');
    for (final card in items) {
      final href = card.querySelector('a')?.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;
      final state = (card.querySelector('.bb-score__link')?.text.trim() ??
              card.querySelector('.bb-score__status')?.text.trim() ??
              '')
          .trim();
      final started = state.contains('試合終了') || state.contains('回') || state.contains('終了');
      if (!started) continue;
      final homeName = YahooTeamNames.normalize(card.querySelector('.bb-score__homeLogo')?.text.trim() ?? '');
      final awayName = YahooTeamNames.normalize(card.querySelector('.bb-score__awayLogo')?.text.trim() ?? '');
      if (homeName.isEmpty || awayName.isEmpty) continue;
      final homeTeam = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [homeName]);
      final awayTeam = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [awayName]);
      if (homeTeam.isEmpty || awayTeam.isEmpty) continue;
      final idHome = homeTeam.first.toColumnMap()['id'] as int;
      final idAway = awayTeam.first.toColumnMap()['id'] as int;
      final existing = await Postgres.execute(conn, AppSql.selectGameOnDate(), data: [idHome, idAway, date]);
      if (existing.isEmpty) continue;
      final gameId = existing.first.toColumnMap()['id'] as int;
      final haveVelo = await Postgres.execute(
        conn,
        'SELECT 1 FROM t_game_details WHERE id_game = \$1 AND COALESCE(int_velo, 0) > 0 LIMIT 1',
        data: [gameId],
      );
      if (haveVelo.isNotEmpty && !state.contains('回')) continue;
      try {
        await refreshGameDetails(conn, pageUrl, href, gameId, idHome, idAway, 0, 0);
      } catch (e) {
        print('試合詳細の再取得に失敗しました ($awayName vs $homeName): $e');
      }
    }
  }

  static Future<Response> fetchGamesNPB(Connection conn) async {
    await ensureGameDetailsVelo(conn);
    final now = DateTime.now();
    final list_date = [
      for (var i = -2; i <= 10; i++) now.add(Duration(days: i)),
    ];

    for (var date in list_date) {
      print(date.toString() + "の試合を取得します。");
      var urlString = 'https://baseball.yahoo.co.jp/npb/schedule/?date=';
      final formatter = DateFormat('yyyy-MM-dd');
      final formatted = formatter.format(date);
      final url = Uri.parse(urlString + formatted);
      final res = await http.get(url);
      print(urlString + formatted);

      if (res.statusCode != 200) {
        throw Exception('Failed to fetch standings');
      }

      try {
        final document = parse(_decodeHtml(res));
        final cardsRoot = document.querySelector('#gm_card');
        if (cardsRoot == null) {
          print('この日の試合カードはありません。');
          continue;
        }
        final leagues = cardsRoot.querySelectorAll('section');

        for (var league in leagues) {
          final sectionTitle = league.querySelector('.bb-score__title')?.text.trim() ?? '';
          if (isPostseasonHeading(sectionTitle)) {
            if (_withinRecentDays(date, now)) {
              await _refreshStartedCards(conn, url, league, formatted);
            }
            continue;
          }
          DateTime datetime_gamestart = DateTime.now();

          final lists = league.querySelectorAll('ul');
          if (lists.isEmpty) {
            continue;
          }
          var cards = lists[0].querySelectorAll('li');

          for (var card in cards) {
            var id_stadium = 0;
            var id_team_home = 0;
            var id_team_away = 0;
            var id_pitcher_home = 0;
            var id_pitcher_away = 0;
            var score_home = -1;
            var score_away = -1;
            var match_state = '';
            var name_team_home = '';
            var name_team_away = '';
            var id_pitcher_win = 0;
            var id_pitcher_lose = 0;
            var id_pitcher_save = 0;
            var homeLeague = 0;
            var awayLeague = 0;
            var homerun_totals = <String, List<int>>{};

            if (card.querySelectorAll('a').isEmpty) {
              continue;
            }
            var url_href = card.querySelectorAll('a')[0].attributes['href']?.trim() ?? '';

            try {
              var url_detail = url.resolve(url_href.replaceFirst('index', 'top'));

              final res_detail = await http.get(url_detail);

              if (res_detail.statusCode != 200) {
                throw Exception('Failed to fetch standings');
              }

              final doc_detail = parse(_decodeHtml(res_detail));
              final boards = doc_detail.querySelectorAll('#gm_brd');
              if (boards.isEmpty) {
                print('試合情報がないためスキップします。');
                continue;
              }
              final match = boards[0];
              final info = match.querySelector('#async-gameCard');
              final timeNode = info?.querySelector('time') ?? match.querySelector('time');
              final timeText = timeNode?.text.trim() ?? '';
              var parsedStart = gameStartOn(formatted, timeText);
              final stadiumSource = info ?? timeNode?.parent;
              final stadiumText = stadiumSource?.nodes.last.text?.replaceAll(RegExp(r'\s+'), '') ?? '';
              final name_stadium = stadiumText;

              final teamLinks = match.querySelector('#async-gameDetail')?.querySelectorAll('a') ?? [];
              if (teamLinks.length < 2) {
                print('対戦カードが未定のためスキップします。');
                continue;
              }

              final a = match.querySelectorAll('#async-gameDetail')[0];
              final b = a..querySelectorAll('div')[0];
              final c = b.querySelectorAll('a')[0];
              final d = c.querySelectorAll('span')[1];
              print(d.text.trim());
              final team_home = match.querySelectorAll('#async-gameDetail')[0].querySelectorAll('div')[0].querySelectorAll('a')[0].querySelectorAll('span')[1].text.trim();
              final team_away = match.querySelectorAll('#async-gameDetail')[0].querySelectorAll('div')[2].querySelectorAll('a')[0].querySelectorAll('span')[1].text.trim();
              name_team_home = team_home;
              name_team_away = team_away;

              try {
                score_home = int.tryParse(
                      match.querySelectorAll('#async-gameDetail')[0].querySelectorAll('div')[1].querySelectorAll('p')[0].querySelectorAll('span')[0].text.trim(),
                    ) ??
                    -1;
                score_away = int.tryParse(match.querySelectorAll('#async-gameDetail')[0].querySelectorAll('div')[1].querySelectorAll('p')[0].querySelectorAll('span')[2].text.trim()) ?? -1;
                match_state = match.querySelectorAll('#async-gameDetail')[0].querySelectorAll('div')[1].querySelectorAll('p')[1].text.trim();
              } catch (e) {
                print('試合前なのでスコアのスクレイピングは行いませんでした。');
              }

              String pitcher_home = '';
              String pitcher_away = '';
              var flg_no_pitcher = false;

              try {
                pitcher_home = doc_detail.querySelectorAll('#strt_mem')[0].querySelectorAll('section')[0].querySelectorAll('div')[0].querySelectorAll('section')[0].querySelectorAll('table')[0].querySelectorAll('tbody')[0].querySelectorAll('tr')[0].querySelectorAll('td')[2].querySelectorAll('a')[0].text.trim();

                pitcher_away = doc_detail.querySelectorAll('#strt_mem')[0].querySelectorAll('section')[0].querySelectorAll('div')[0].querySelectorAll('section')[1].querySelectorAll('table')[0].querySelectorAll('tbody')[0].querySelectorAll('tr')[0].querySelectorAll('td')[2].querySelectorAll('a')[0].text.trim();

                print("試合中もしくは試合後の先発投手を取得しました。");
              } catch (e) {
                try {
                  pitcher_home = doc_detail.querySelectorAll('#strt_pit')[0].querySelectorAll('div')[0].querySelectorAll('div')[0].querySelectorAll('section')[0].querySelectorAll('div')[1].querySelectorAll('div')[0].querySelectorAll('table')[0].querySelectorAll('tbody')[0].querySelectorAll('tr')[0].querySelectorAll('td')[2].querySelectorAll('a')[0].text.trim();

                  pitcher_away = doc_detail.querySelectorAll('#strt_pit')[0].querySelectorAll('div')[0].querySelectorAll('div')[0].querySelectorAll('section')[1].querySelectorAll('div')[1].querySelectorAll('div')[0].querySelectorAll('table')[0].querySelectorAll('tbody')[0].querySelectorAll('tr')[0].querySelectorAll('td')[2].querySelectorAll('a')[0].text.trim();

                  print('試合前なので予告先発投手を取得しました。');
                } catch (e) {
                  print('予告先発投手が発表されていないので詳細のスクレイピングは行いませんでした。');
                  flg_no_pitcher = true;
                }
              }

              //勝利投手、敗戦投手、セーブ投手を取得
              try {
                var players_result = doc_detail.querySelectorAll('#async-resultPitcher table tbody tr');
                if (players_result.isEmpty) {
                  throw Exception('試合が終了していないので活躍投手のHTMLが存在しません。');
                }
                for (var player in players_result) {
                  var name_team_block = player.querySelectorAll('td')[0].querySelectorAll('span');

                  if (name_team_block.isEmpty) {
                    continue;
                  }

                  var name_team = name_team_block[0].text.trim();

                  print(name_team);

                  var result = player.querySelectorAll('th')[0].text.trim();
                  var href_player = player.querySelectorAll('td')[0].querySelectorAll('a')[0].attributes['href']?.trim() ?? '';

                  var url_player = url.resolve(href_player);

                  final res_player = await http.get(url_player);

                  if (res_player.statusCode != 200) {
                    throw Exception('Failed to fetch standings');
                  }

                  final doc_player = parse(_decodeHtml(res_player));
                  final name_player = doc_player.querySelectorAll('ruby.bb-profile__ruby')[0].text.split('（')[0].trim();
                  print(StringTool.noSpace(name_player));
                  final team_result = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [name_team]);

                  final id_team_result = team_result.first.toColumnMap()['id'];
                  final result_player = await Postgres.execute(conn, AppSql.selectPlayerWhereFullNameAndTeamID(), data: [StringTool.noSpace(name_player), id_team_result]);
                  final id_player_result = result_player.first.toColumnMap()['id'] as int;
                  await BirthPlaceRegistry.applyFromProfile(conn, id_player_result, doc_player);

                  if (result == '勝利投手') {
                    id_pitcher_win = id_player_result;
                    print("勝利投手を取得しました。");
                  } else if (result == '敗戦投手') {
                    id_pitcher_lose = id_player_result;
                    print("敗戦投手を取得しました。");
                  } else if (result == 'セーブ') {
                    id_pitcher_save = id_player_result;
                    print("セーブ投手を取得しました。");
                  }
                  print('');
                } //for players_result
              } catch (e) {
                print('試合が終了していないので活躍選手を取得できませんでした。');
              }

              try {
                homerun_totals = _parseHomerunTotalsFromTop(doc_detail);
                if (homerun_totals.isNotEmpty) {
                  print('本塁打号数を取得しました: $homerun_totals');
                }
              } catch (e) {
                print('本塁打号数を取得できませんでした。');
              }

              final result_team_home = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [team_home]);

              id_team_home = result_team_home.first.toColumnMap()['id'];
              homeLeague = int.tryParse('${result_team_home.first.toColumnMap()['id_league']}') ?? 0;

              final results_team_away = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [team_away]);

              id_team_away = results_team_away.first.toColumnMap()['id'];
              awayLeague = int.tryParse('${results_team_away.first.toColumnMap()['id_league']}') ?? 0;

              if (parsedStart == null) {
                final stored = await Postgres.execute(conn, AppSql.selectGameOnDate(), data: [id_team_home, id_team_away, formatted]);
                if (stored.isEmpty) {
                  print('開始時刻が未定のためスキップします。');
                  continue;
                }
                final rawStart = stored.first.toColumnMap()['datetime_start'];
                parsedStart = rawStart is DateTime ? rawStart : DateTime.tryParse('$rawStart');
                if (parsedStart == null) {
                  print('開始時刻が未定のためスキップします。');
                  continue;
                }
                print('ページに開始時刻がないため、登録済みの開始時刻を使います。');
              }
              datetime_gamestart = parsedStart;

              if (flg_no_pitcher == false) {
                //先発投手が発表されている場合
                try {
                  final result_pitcher_home = await conn.execute(AppSql.selectPlayerWhereFullNameAndTeamID(), parameters: [StringTool.noSpace(pitcher_home), id_team_home]);
                  id_pitcher_home = result_pitcher_home.first.toColumnMap()['id'];
                } catch (e) {
                  final player = m_player();
                  if (pitcher_home.split(' ').length == 2) {
                    player.name_last = pitcher_home.split(' ')[0];
                    player.name_first = pitcher_home.split(' ')[1];
                    player.name_full = player.name_last + player.name_first;
                  } else {
                    player.name_last = pitcher_home;
                    player.name_full = pitcher_home;
                  }
                  print(player.toMap());
                  player.id_team = id_team_home;
                  id_pitcher_home = await Postgres.insert(conn, player);

                  print('未登録の選手が先発予定投手になっていたので選手情報を登録しました。');
                }
                try {
                  final result_pitcher_away = await conn.execute(AppSql.selectPlayerWhereFullNameAndTeamID(), parameters: [StringTool.noSpace(pitcher_away), id_team_away]);
                  id_pitcher_away = result_pitcher_away.first.toColumnMap()['id'];
                } catch (e) {
                  final player = m_player();
                  if (pitcher_away.split(' ').length == 2) {
                    player.name_last = pitcher_away.split(' ')[0];
                    player.name_first = pitcher_away.split(' ')[1];
                    player.name_full = player.name_last + player.name_first;
                  } else {
                    player.name_last = pitcher_away;
                    player.name_full = pitcher_away;
                  }
                  print(player.toMap());
                  player.id_team = id_team_away;

                  id_pitcher_away = await Postgres.insert(conn, player);
                  print('未登録の選手が先発予定投手になっていたので選手情報を登録しました。');
                }
              }

              final result_stadium = await Postgres.execute(conn, AppSql.selectStadium(), data: ['%$name_stadium%']);

              if (result_stadium.isEmpty) {
                //DBに存在しないスタジアムの場合は新規登録する。
                var stadium = m_stadium();
                stadium.name_short = name_stadium;
                stadium.id_team = id_team_home;
                id_stadium = await Postgres.insert(conn, stadium);
              } else {
                //DBに存在するスタジアムの場合
                id_stadium = result_stadium.first.toColumnMap()['id'];
              }
            } catch (e, stacktrace) {
              print(e);
              print(stacktrace);
              print('予想外のバグが発生しました。');
              continue;
            }
            final result_game = await conn.execute(AppSql.selectExistsGame(), parameters: [id_team_home, id_team_away, datetime_gamestart]);

            final game = t_game();
            game.id_stadium = id_stadium;
            game.id_team_home = id_team_home;
            game.id_team_away = id_team_away;
            game.id_pitcher_home = id_pitcher_home;
            game.id_pitcher_away = id_pitcher_away;
            game.datetime_start = datetime_gamestart;
            game.score_home = score_home;
            game.score_away = score_away;
            game.state = match_state;
            game.id_pitcher_win = id_pitcher_win;
            game.id_pitcher_lose = id_pitcher_lose;
            game.id_pitcher_save = id_pitcher_save;
            game.code_game = regularGameCode(sectionTitle, homeLeague, awayLeague);

            // チームID|選手名 → 出場成績の打席結果（中安、左２など）を打順どおり
            final boxPlays = <String, List<String>>{};
            var boxPlates = <BoxPlate>[];
            if (result_game.isEmpty) {
              //DBに同じ日付、同じ組み合わせの試合が登録されていない場合、新規登録する
              game.id = await Postgres.insert(conn, game);
            } else {
              //DBに同じ日付、同じ組み合わせの試合が登録されている場合は更新する
              game.id = result_game.first.toColumnMap()['id'];
              await Postgres.update(conn, game);

              if (date != now) {
                continue;
              }
              //打席結果を取得
              print('打席結果を取得します。');
              try {
                // js-scoreBord--3 table tbody tr 14列目以降
                var url_stats = url.resolve(url_href.replaceFirst('index', 'stats'));
                print(url_stats);
                final res_stats = await http.get(url_stats);
                if (res_stats.statusCode != 200) {
                  throw Exception('Failed to fetch standings');
                }
                final doc_stats = parse(_decodeHtml(res_stats));
                boxPlays.addAll(_boxScorePlays(doc_stats, id_team_away, id_team_home));
                boxPlates = parseBoxPlates(doc_stats, id_team_away, id_team_home);
                var list_game_summary = <t_game_summary>[];

                var game_summary_away_batting = doc_stats.querySelectorAll('#async-gameBatterStats .bb-blowResultsTable table tbody tr');
                if (game_summary_away_batting.isEmpty) {
                  throw Exception('試合が開始していないので試合結果のHTMLが存在しません。');
                }

                // var idx_col = 0;
                var id_team = id_team_away;
                for (var game_summary_away_row in game_summary_away_batting) {
                  //もしrow直下にthがある場合はスキップ
                  if (game_summary_away_row.querySelectorAll('th').isNotEmpty) {
                    id_team = id_team_home;
                    continue;
                  }
                  var txt_batter = game_summary_away_row.querySelectorAll('td')[1].text.trim();
                  print("打者名：" + txt_batter);
                  final result_player = await Postgres.execute(conn, AppSql.selectPlayerWhereFullNameAndTeamID(), data: [StringTool.noSpace(txt_batter), id_team]);
                  if (result_player.isEmpty) {
                    print('未登録の選手が打者になっていたのでスキップします。');
                    continue;
                  }
                  final id_player_result = result_player.first.toColumnMap()['id'];

                  var game_summary = t_game_summary();
                  game_summary.id_game = game.id;
                  game_summary.id_player = id_player_result;
                  game_summary.int_batting = int.tryParse(game_summary_away_row.querySelectorAll('td')[3].text.trim()) ?? 0;
                  game_summary.int_homerun = int.tryParse(game_summary_away_row.querySelectorAll('td')[13].text.trim()) ?? 0;
                  game_summary.int_hit1 = int.tryParse(game_summary_away_row.querySelectorAll('td')[5].text.trim()) ?? 0;
                  game_summary.int_fourball = int.tryParse(game_summary_away_row.querySelectorAll('td')[8].text.trim()) ?? 0;
                  game_summary.int_dead_batting = int.tryParse(game_summary_away_row.querySelectorAll('td')[9].text.trim()) ?? 0;
                  game_summary.int_sacrifice = int.tryParse(game_summary_away_row.querySelectorAll('td')[10].text.trim()) ?? 0;
                  game_summary.int_rbi = int.tryParse(game_summary_away_row.querySelectorAll('td')[6].text.trim()) ?? 0;
                  game_summary.int_steal_base = int.tryParse(game_summary_away_row.querySelectorAll('td')[11].text.trim()) ?? 0;
                  game_summary.int_error = int.tryParse(game_summary_away_row.querySelectorAll('td')[12].text.trim()) ?? 0;
                  game_summary.txt_homerun_total = _homerunTotalForBatter(txt_batter, game_summary.int_homerun, homerun_totals);
                  list_game_summary.add(game_summary);
                  // print(game_summary.toMap());
                }

                //async-gamePitcherStats section table tbody tr
                print('投手成績を取得します。');
                var sections = doc_stats.querySelectorAll('#async-gamePitcherStats section');

                var id_team_pitcher = id_team_away;
                for (var section in sections) {
                  var game_summary_pitcher = section.querySelectorAll('table tbody tr');
                  if (game_summary_pitcher.isEmpty) {
                    id_team_pitcher = id_team_home;
                    continue;
                  }

                  final pitcherHeads = section.querySelectorAll('table thead th').map((cell) => cell.text.trim()).toList();
                  String cellOf(Element row, String header) {
                    final index = pitcherHeads.indexOf(header);
                    final cells = row.querySelectorAll('td');
                    if (index < 0 || index >= cells.length) return '';
                    return cells[index].text.trim();
                  }

                  for (var game_summary_pitcher_row in game_summary_pitcher) {
                    final cells = game_summary_pitcher_row.querySelectorAll('td');
                    if (cells.length < 2) continue;
                    var code_result_pitcher = cells.first.text.trim();
                    var txt_pitcher = cellOf(game_summary_pitcher_row, '選手名');
                    if (txt_pitcher.isEmpty) txt_pitcher = cells[1].text.trim();
                    print("投手名：" + txt_pitcher);
                    final result_player = await Postgres.execute(conn, AppSql.selectPlayerWhereFullNameAndTeamID(), data: [StringTool.noSpace(txt_pitcher), id_team_pitcher]);
                    if (result_player.isEmpty) {
                      print('未登録の選手が投手になっていたのでスキップします。');
                      continue;
                    }
                    final id_player_result = result_player.first.toColumnMap()['id'];

                    var game_summary_pitcher = t_game_summary();
                    for (var game_summary in list_game_summary) {
                      if (game_summary.id_player == id_player_result) {
                        game_summary_pitcher = game_summary;
                        list_game_summary.remove(game_summary);
                        break;
                      }
                    }

                    if (code_result_pitcher.contains('勝')) {
                      game_summary_pitcher.code_result_pitcher = Value.CodeGameResultPitcher.WIN;
                    } else if (code_result_pitcher.contains('敗')) {
                      game_summary_pitcher.code_result_pitcher = Value.CodeGameResultPitcher.LOSE;
                    } else if (code_result_pitcher.contains('Ｓ') || code_result_pitcher.contains('セーブ')) {
                      game_summary_pitcher.code_result_pitcher = Value.CodeGameResultPitcher.SAVE;
                    } else if (code_result_pitcher.contains('H') || code_result_pitcher.contains('ホールド')) {
                      game_summary_pitcher.code_result_pitcher = Value.CodeGameResultPitcher.HOLD;
                    }

                    game_summary_pitcher.id_game = game.id;
                    game_summary_pitcher.id_player = id_player_result;
                    game_summary_pitcher.double_inning_pitch = double.tryParse(cellOf(game_summary_pitcher_row, '投球回')) ?? 0.0;
                    game_summary_pitcher.int_pitch = int.tryParse(cellOf(game_summary_pitcher_row, '投球数')) ?? 0;
                    game_summary_pitcher.int_hit = int.tryParse(cellOf(game_summary_pitcher_row, '被安打')) ?? 0;
                    game_summary_pitcher.int_strike_out = int.tryParse(cellOf(game_summary_pitcher_row, '奪三振')) ?? 0;
                    game_summary_pitcher.int_four = int.tryParse(cellOf(game_summary_pitcher_row, '与四球')) ?? 0;
                    game_summary_pitcher.int_dead_pitching = int.tryParse(cellOf(game_summary_pitcher_row, '与死球')) ?? 0;
                    game_summary_pitcher.int_balk = int.tryParse(cellOf(game_summary_pitcher_row, 'ボーク')) ?? 0;
                    game_summary_pitcher.int_runs = int.tryParse(cellOf(game_summary_pitcher_row, '失点')) ?? 0;
                    game_summary_pitcher.int_runs_earned = int.tryParse(cellOf(game_summary_pitcher_row, '自責点')) ?? 0;

                    list_game_summary.add(game_summary_pitcher);
                  } //for row
                  id_team_pitcher = id_team_home;
                } //for sections

                await Postgres.execute(conn, AppSql.deleteGameSummary(), data: [game.id]);
                final lineScore = _parseLineScore(doc_stats, name_team_home, name_team_away);
                if (lineScore != null) {
                  for (final summary in list_game_summary) {
                    summary.txt_scores_home = lineScore.scoresHome;
                    summary.txt_scores_away = lineScore.scoresAway;
                    summary.int_runs_home = lineScore.runsHome;
                    summary.int_runs_away = lineScore.runsAway;
                    summary.int_error_home = lineScore.errorsHome;
                    summary.int_error_away = lineScore.errorsAway;
                    summary.int_hit_home = lineScore.hitsHome;
                    summary.int_hit_away = lineScore.hitsAway;
                  }
                }
                await Postgres.insertMulti(conn, list_game_summary);
                print('打席結果を登録しました。');
              } catch (e, stacktrace) {
                print('打席結果のスクレイピングに失敗しました。');
                print(stacktrace);
              }
            }
            if (_withinRecentDays(date, now) && game.id != 0) {
              try {
                await _saveGameLiveText(
                  conn,
                  url,
                  url_href,
                  game.id,
                  id_team_home,
                  id_team_away,
                  id_pitcher_home,
                  id_pitcher_away,
                  boxPlates: boxPlates,
                );
              } catch (e, stacktrace) {
                print('テキスト速報のスクレイピングに失敗しました。');
                print(stacktrace);
              }
              if (boxPlays.isNotEmpty) {
                try {
                  await _fillMissingDirections(conn, game.id, boxPlays);
                } catch (e, stacktrace) {
                  print('出場成績からの打球方向の補完に失敗しました。');
                  print(stacktrace);
                }
              }
            }
          } //for card
        } //for league
      } catch (e, stacktrace) {
        print(e);
        print(stacktrace);
        print('スクレイピングに失敗しました。当日は試合がない場合があります。');
      }
      print('');
      print(date.toString() + "の試合を全て取得しました。");
      print('');
    } //for 今日から10日後
    return Response.ok('ok');
  }

  /// 出場成績を正本に、テキスト速報の補足を足して t_game_details を入れ直す。
  static Future<void> refreshGameDetails(
    Connection conn,
    Uri pageUrl,
    String urlHref,
    int gameId,
    int idTeamHome,
    int idTeamAway,
    int idPitcherHome,
    int idPitcherAway,
  ) async {
    await ensureGameDetailsVelo(conn);
    var plates = <BoxPlate>[];
    final statsUrl = pageUrl.resolve(gamePageHref(urlHref, 'stats'));
    try {
      final doc = await YahooHtml.fetchDocument(statsUrl);
      plates = parseBoxPlates(doc, idTeamAway, idTeamHome);
      await _saveOfficialLineScore(conn, doc, gameId);
    } catch (e) {
      print('出場成績を取得できませんでした: $e');
    }
    await _saveGameLiveText(
      conn,
      pageUrl,
      urlHref,
      gameId,
      idTeamHome,
      idTeamAway,
      idPitcherHome,
      idPitcherAway,
      boxPlates: plates,
    );
  }

  /// スポーツナビ（Yahoo）のテキスト速報を取り直し、t_game_details へ登録する。
  static Future<void> refreshLiveText(
    Connection conn,
    Uri pageUrl,
    String urlHref,
    int gameId,
    int idTeamHome,
    int idTeamAway,
    int idPitcherHome,
    int idPitcherAway,
  ) {
    return _saveGameLiveText(
      conn,
      pageUrl,
      urlHref,
      gameId,
      idTeamHome,
      idTeamAway,
      idPitcherHome,
      idPitcherAway,
    );
  }

  /// 出場成績の打席を入れ直し、テキスト速報からは打点・場面・盗塁・交代だけ足す。
  static Future<void> _writeBoxScoreDetails({
    required Connection conn,
    required int gameId,
    required List<BoxPlate> boxPlates,
    required ParsedLiveText? parsed,
    required int Function(String name, int teamId) playerId,
    required int idTeamHome,
    required int idTeamAway,
    required int idPitcherHome,
    required int idPitcherAway,
    required String homeShortest,
    required String homeShort,
    required String awayShortest,
    required String awayShort,
  }) async {
    final notes = <LivePlateNote>[];
    if (parsed != null) {
      var pitcherHome = idPitcherHome;
      var pitcherAway = idPitcherAway;
      var scoreHome = 0;
      var scoreAway = 0;
      for (final half in parsed.halves) {
        final battingTeam = half.bottom ? idTeamHome : idTeamAway;
        final pitchingTeam = half.bottom ? idTeamAway : idTeamHome;
        for (final plate in half.plates) {
          final enteringHome = scoreHome;
          final enteringAway = scoreAway;
          var plateRuns = 0;
          var runsAssigned = false;
          int? absoluteHome;
          int? absoluteAway;
          var battingResult = '';
          var runs = 0;
          var homerNumber = 0;
          var stateScore = '';
          var goodbye = false;
          var direction = '';
          final extras = <LiveExtra>[];
          for (final event in plate.events) {
            if (livePlateFinishedResults.contains(event.result)) {
              battingResult = event.result;
              homerNumber = event.homerNumber;
              if (event.stateScore.isNotEmpty) stateScore = event.stateScore;
              if (event.goodbye) goodbye = true;
              if (event.direction.isNotEmpty) direction = event.direction;
              if (!runsAssigned && (event.scoreLeft != null || event.linguisticRuns > 0 || event.timely)) {
                final resolved = _resolvedLiveScore(
                  event,
                  homeShortest,
                  homeShort,
                  awayShortest,
                  awayShort,
                  bottom: half.bottom,
                  beforeHome: scoreHome,
                  beforeAway: scoreAway,
                );
                if (resolved != null) {
                  final newHome = resolved.home;
                  final newAway = resolved.away;
                  final delta = half.bottom ? newHome - scoreHome : newAway - scoreAway;
                  runs = delta < 0 ? 0 : delta;
                  absoluteHome = newHome;
                  absoluteAway = newAway;
                  if (stateScore.isEmpty && runs > 0) {
                    stateScore = scoreStateFromTransition(
                      bottom: half.bottom,
                      beforeHome: scoreHome,
                      beforeAway: scoreAway,
                      afterHome: newHome,
                      afterAway: newAway,
                    );
                  }
                } else {
                  runs = event.linguisticRuns;
                }
                final timelyHit = event.timely && (event.result == Value.CodeGameResult.HIT_SINGLE || event.result == Value.CodeGameResult.HIT_DOUBLE || event.result == Value.CodeGameResult.HIT_TRIPLE);
                if (timelyHit && runs < 1) runs = 1;
                runsAssigned = true;
                plateRuns = runs;
              }
            } else if (event.result.isNotEmpty) {
              extras.add(LiveExtra(
                result: event.result,
                category: event.category,
                exitName: event.exitName,
                enterName: event.enterName,
                positionFrom: event.positionFrom,
                positionTo: event.positionTo,
                pitcherChange: event.pitcherChange,
              ));
            }
          }
          notes.add(LivePlateNote(
            inning: half.inning,
            bottom: half.bottom,
            teamId: battingTeam,
            batterName: plate.batterName,
            battingOrder: plate.battingOrder,
            outs: plate.outs,
            runnerFirst: plate.runnerFirst,
            runnerSecond: plate.runnerSecond,
            runnerThird: plate.runnerThird,
            battingResult: battingResult,
            runs: runs,
            homerNumber: homerNumber,
            stateScore: stateScore,
            goodbye: goodbye,
            direction: direction,
            scoreHome: enteringHome,
            scoreAway: enteringAway,
            pitcherId: half.bottom ? pitcherAway : pitcherHome,
            extras: extras,
          ));
          for (final extra in extras) {
            if (!extra.pitcherChange || extra.enterName.isEmpty) continue;
            final entered = playerId(extra.enterName, pitchingTeam);
            if (entered == 0) continue;
            if (half.bottom) {
              pitcherAway = entered;
            } else {
              pitcherHome = entered;
            }
          }
          if (absoluteHome != null && absoluteAway != null) {
            scoreHome = absoluteHome;
            scoreAway = absoluteAway;
          } else if (half.bottom) {
            scoreHome += plateRuns;
          } else {
            scoreAway += plateRuns;
          }
        }
      }
    }

    final placed = attachLiveNotes(boxPlates, notes);
    final details = <t_game_details>[];
    int dist(int order, int start) {
      if (order < 1 || order > 9) return 30;
      return (order - start + 9) % 9;
    }

    var maxInning = 0;
    for (final plate in boxPlates) {
      if (plate.inning > maxInning) maxInning = plate.inning;
    }
    for (final extra in placed) {
      if (extra.inning > maxInning) maxInning = extra.inning;
    }
    final cursor = <bool, int>{false: 1, true: 1};
    final ordered = <({int inning, int half, int outs, int distance, int kind, int seq, t_game_details detail})>[];
    var seq = 0;
    for (var inning = 1; inning <= maxInning; inning++) {
      for (final bottom in [false, true]) {
        final halfPlates = boxPlates.where((plate) => plate.inning == inning && plate.bottom == bottom).toList();
        final start = cursor[bottom]!;
        halfPlates.sort((a, b) {
          final byDist = dist(a.order, start).compareTo(dist(b.order, start));
          if (byDist != 0) return byDist;
          return a.seq.compareTo(b.seq);
        });
        var lastOut = 0;
        for (final plate in halfPlates) {
          if (plate.matched) {
            lastOut = plate.outs;
          } else {
            plate.outs = lastOut;
          }
          final batterId = playerId(plate.name, plate.teamId);
          if (batterId == 0) continue;
          final detail = t_game_details();
          detail.id_game = gameId;
          detail.int_inning = plate.inning;
          detail.flg_bottom = plate.bottom;
          detail.int_batting_order = plate.order;
          detail.id_batter = batterId;
          detail.cnt_out = plate.outs;
          detail.flg_runner_first = plate.runnerFirst;
          detail.flg_runner_second = plate.runnerSecond;
          detail.flg_runner_third = plate.runnerThird;
          detail.code_category = Value.CodeGameResultCategory.BATTING;
          detail.code_result = plate.result;
          detail.double_total_bases = plate.totalBases;
          detail.int_runs = plate.runs;
          detail.cnt_homerun = plate.result == Value.CodeGameResult.HOME_RUN ? plate.homerNumber : 0;
          detail.code_state_score = plate.stateScore;
          detail.flg_goodbye = plate.goodbye;
          detail.code_direction_batting = plate.direction;
          detail.code_position_from = plate.position;
          detail.int_score_home = plate.scoreHome;
          detail.int_score_away = plate.scoreAway;
          detail.id_pitcher = plate.pitcherId;
          ordered.add((inning: inning, half: bottom ? 1 : 0, outs: plate.outs, distance: dist(plate.order, start), kind: 0, seq: seq++, detail: detail));
        }
        if (halfPlates.isNotEmpty) {
          final last = halfPlates.last.order;
          if (last >= 1 && last <= 9) cursor[bottom] = last == 9 ? 1 : last + 1;
        }
        for (final extra in placed.where((row) => row.inning == inning && row.bottom == bottom)) {
          final batterId = playerId(extra.batterName, extra.teamId);
          if (batterId == 0) continue;
          final pitchingTeam = bottom ? idTeamAway : idTeamHome;
          final onBattingSide = extra.extra.result == Value.CodeGameResult.PINCH_HITTER || extra.extra.result == Value.CodeGameResult.PINCH_RUNNER || extra.extra.result == Value.CodeGameResult.STEAL_BASE_SAFE || extra.extra.result == Value.CodeGameResult.STEAL_BASE_OUT;
          final nameTeam = onBattingSide ? extra.teamId : pitchingTeam;
          final detail = t_game_details();
          detail.id_game = gameId;
          detail.int_inning = extra.inning;
          detail.flg_bottom = extra.bottom;
          detail.int_batting_order = extra.order;
          detail.id_batter = batterId;
          detail.cnt_out = extra.outs;
          detail.flg_runner_first = extra.runnerFirst;
          detail.flg_runner_second = extra.runnerSecond;
          detail.flg_runner_third = extra.runnerThird;
          detail.code_category = extra.extra.category;
          detail.code_result = extra.extra.result;
          detail.code_position_from = extra.extra.positionFrom;
          detail.code_position_to = extra.extra.positionTo;
          detail.int_score_home = extra.scoreHome;
          detail.int_score_away = extra.scoreAway;
          detail.id_pitcher = extra.pitcherId;
          if (extra.extra.exitName.isNotEmpty) detail.id_player_exit = playerId(extra.extra.exitName, nameTeam);
          if (extra.extra.enterName.isNotEmpty) detail.id_player_enter = playerId(extra.extra.enterName, nameTeam);
          ordered.add((
            inning: inning,
            half: bottom ? 1 : 0,
            outs: extra.outs,
            distance: dist(extra.order, start),
            kind: 1,
            seq: seq++,
            detail: detail,
          ));
        }
      }
    }
    ordered.sort((a, b) {
      final byInning = a.inning.compareTo(b.inning);
      if (byInning != 0) return byInning;
      final byHalf = a.half.compareTo(b.half);
      if (byHalf != 0) return byHalf;
      final byOut = a.outs.compareTo(b.outs);
      if (byOut != 0) return byOut;
      final byDist = a.distance.compareTo(b.distance);
      if (byDist != 0) return byDist;
      final byKind = a.kind.compareTo(b.kind);
      if (byKind != 0) return byKind;
      return a.seq.compareTo(b.seq);
    });
    for (final row in ordered) {
      details.add(row.detail);
    }
    if (details.isEmpty) return;
    await Postgres.execute(conn, 'BEGIN');
    try {
      await Postgres.execute(conn, AppSql.deleteGameDetails(), data: [gameId]);
      await Postgres.insertMulti(conn, details);
      await Postgres.commit(conn);
    } catch (e) {
      await Postgres.rollback(conn);
      rethrow;
    }
    print('出場成績から${boxPlates.length}打席、速報の補足${placed.length}件を登録しました。');
  }

  /// スポーツナビ（Yahoo）のテキスト速報を t_game_details へ登録する。
  /// 取得済みのイニングは読み飛ばし、進行中の最後の打席だけ取り直して続きから登録する。
  static String _starterPosition(ParsedLiveText parsed, bool bottom, String batterName) {
    final side = parsed.positions[bottom];
    if (side == null || side.isEmpty) return '';
    final name = StringTool.noSpace(batterName);
    for (final entry in side.entries) {
      if (name.startsWith(entry.key) || entry.key.startsWith(name)) return entry.value;
    }
    return '';
  }

  static Future<void> _saveGameLiveText(
    Connection conn,
    Uri pageUrl,
    String urlHref,
    int gameId,
    int idTeamHome,
    int idTeamAway,
    int idPitcherHome,
    int idPitcherAway, {
    List<BoxPlate> boxPlates = const [],
  }) async {
    await ensureGameDetailsVelo(conn);
    final urlText = pageUrl.resolve(gamePageHref(urlHref, 'text'));
    ParsedLiveText? parsedLive;
    try {
      final live = LiveText.parse(await YahooHtml.fetchDocument(urlText));
      if (live.halves.isNotEmpty) parsedLive = live;
    } catch (e) {
      print('テキスト速報を取得できませんでした: $e');
    }
    if (parsedLive == null && boxPlates.isEmpty) return;
    final parsed = parsedLive;

    final storedRows = await Postgres.execute(conn, AppSql.selectGameDetails(), data: [gameId]);
    final stored = <_StoredDetail>[];
    for (final row in storedRows) {
      final map = row.toColumnMap();
      stored.add(_StoredDetail(
        id: _detailInt(map['id']),
        inning: _detailInt(map['int_inning']),
        bottom: _detailBool(map['flg_bottom']),
        order: _detailInt(map['int_batting_order']),
        batter: _detailInt(map['id_batter']),
        outs: _detailInt(map['cnt_out']),
        runnerFirst: _detailBool(map['flg_runner_first']),
        runnerSecond: _detailBool(map['flg_runner_second']),
        runnerThird: _detailBool(map['flg_runner_third']),
        runs: _detailInt(map['int_runs']),
        result: '${map['code_result'] ?? ''}',
        enter: _detailInt(map['id_player_enter']),
      ));
    }

    final plates = <_StoredPlate>[];
    for (final row in stored) {
      if (plates.isNotEmpty && plates.last.sameSituation(row)) {
        plates.last.results.add(row.result);
        continue;
      }
      plates.add(_StoredPlate(row));
    }

    final rosterRows = await Postgres.execute(conn, AppSql.selectPlayersByTeams(), data: [idTeamHome, idTeamAway]);
    final roster = <_RosterName>[];
    for (final row in rosterRows) {
      final map = row.toColumnMap();
      roster.add(_RosterName(
        _detailInt(map['id']),
        _detailInt(map['id_team']),
        StringTool.noSpace('${map['name_full'] ?? ''}'),
        StringTool.noSpace('${map['name_last'] ?? ''}'),
        '${map['name_first_initial'] ?? ''}'.trim().toUpperCase(),
      ));
    }

    final teamRows = await Postgres.execute(conn, AppSql.selectTeamNamesByIds(), data: [idTeamHome, idTeamAway]);
    var homeShortest = '';
    var homeShort = '';
    var awayShortest = '';
    var awayShort = '';
    for (final row in teamRows) {
      final map = row.toColumnMap();
      final id = _detailInt(map['id']);
      if (id == idTeamHome) {
        homeShortest = '${map['name_shortest'] ?? ''}';
        homeShort = '${map['name_short'] ?? ''}';
      } else if (id == idTeamAway) {
        awayShortest = '${map['name_shortest'] ?? ''}';
        awayShort = '${map['name_short'] ?? ''}';
      }
    }

    int playerId(String name, int teamId) {
      final key = StringTool.noSpace(name);
      if (key.isEmpty) return 0;
      final team = roster.where((player) => player.teamId == teamId).toList();
      final exact = team.where((player) => player.name == key || player.nameLast == key).toList();
      if (exact.isNotEmpty) return exact.first.id;

      final candidates = team.where((player) {
        return playerNameMatches(
          query: key,
          nameFull: player.name,
          nameLast: player.nameLast,
          storedInitial: player.initial,
        );
      }).map((player) => (
            id: player.id,
            nameFull: player.name,
            nameLast: player.nameLast,
            initial: player.initial,
          )).toList();

      final picked = pickBestPlayerId(query: key, candidates: candidates);
      if (picked == null) {
        print('選手IDが見つかりません: $name');
        return 0;
      }

      // 略称からフル名へ紐づいたらイニシャルを学習
      final parsed = parsePlayerName(key);
      if (parsed.hasInitial) {
        final row = team.firstWhere((p) => p.id == picked);
        if (row.initial.isEmpty) {
          row.initial = parsed.initial!;
          unawaited(_persistPlayerInitial(conn, picked, parsed.initial!));
        }
      }
      return picked;
    }

    if (boxPlates.isNotEmpty) {
      await _writeBoxScoreDetails(
        conn: conn,
        gameId: gameId,
        boxPlates: boxPlates,
        parsed: parsed,
        playerId: playerId,
        idTeamHome: idTeamHome,
        idTeamAway: idTeamAway,
        idPitcherHome: idPitcherHome,
        idPitcherAway: idPitcherAway,
        homeShortest: homeShortest,
        homeShort: homeShort,
        awayShortest: awayShortest,
        awayShort: awayShort,
      );
      await _saveMaxPitchVelo(
        conn: conn,
        pageUrl: pageUrl,
        urlHref: urlHref,
        gameId: gameId,
        playerId: playerId,
        idTeamHome: idTeamHome,
        idTeamAway: idTeamAway,
      );
      return;
    }
    if (parsed == null) return;

    int ord(int inning, bool bottom) => inning * 2 + (bottom ? 1 : 0);
    final lastOrd = plates.isEmpty ? -1 : ord(plates.last.inning, plates.last.bottom);
    final startAt = <int, int>{};
    final backfill = <int, List<int>>{};
    int? deleteFrom;

    for (final half in parsed.halves) {
      final key = ord(half.inning, half.bottom);
      final storedHere = plates.where((plate) => plate.inning == half.inning && plate.bottom == half.bottom).toList();
      if (plates.isNotEmpty && key < lastOrd) {
        final battingTeam = half.bottom ? idTeamHome : idTeamAway;
        final missing = unmatchedLivePlates(
          plates: half.plates,
          stored: [
            for (final plate in storedHere)
              StoredLivePlate(
                order: plate.order,
                batter: plate.batter,
                outs: plate.outs,
                runnerFirst: plate.runnerFirst,
                runnerSecond: plate.runnerSecond,
                runnerThird: plate.runnerThird,
              ),
          ],
          batterIdOf: (name) => playerId(name, battingTeam),
        );
        if (missing.isNotEmpty) backfill[key] = missing;
        continue;
      }
      if (plates.isEmpty || key > lastOrd) {
        startAt[key] = 0;
        continue;
      }

      if (storedHere.length > half.plates.length) continue;

      final lastFinished = storedHere.isNotEmpty && storedHere.last.results.any(livePlateFinishedResults.contains);
      final laterHalf = parsed.halves.any((other) => ord(other.inning, other.bottom) > key);
      final reopen = storedHere.isNotEmpty && (!lastFinished || (!parsed.finished && !laterHalf));
      if (reopen) {
        startAt[key] = storedHere.length - 1;
        deleteFrom = storedHere.last.firstId;
      } else if (storedHere.length < half.plates.length) {
        startAt[key] = storedHere.length;
      }
    }

    var pitcherHome = idPitcherHome;
    var pitcherAway = idPitcherAway;
    var scoreHome = 0;
    var scoreAway = 0;
    for (final row in stored) {
      if (deleteFrom != null && row.id >= deleteFrom) break;
      if (row.result == Value.CodeGameResult.CHANGE_PITCHER && row.enter != 0) {
        if (row.bottom) {
          pitcherAway = row.enter;
        } else {
          pitcherHome = row.enter;
        }
      }
      if (row.runs > 0) {
        if (row.bottom) {
          scoreHome += row.runs;
        } else {
          scoreAway += row.runs;
        }
      }
    }

    final pending = <t_game_details>[];
    for (final half in parsed.halves) {
      final key = ord(half.inning, half.bottom);
      final indexes = <int>[...?backfill[key]];
      final start = startAt[key];
      if (start != null) {
        for (var index = start; index < half.plates.length; index++) {
          if (!indexes.contains(index)) indexes.add(index);
        }
      }
      if (indexes.isEmpty) continue;
      final battingTeam = half.bottom ? idTeamHome : idTeamAway;

      for (final index in indexes) {
        final plate = half.plates[index];
        final batterId = playerId(plate.batterName, battingTeam);
        var plateRuns = 0;
        var runsAssigned = false;
        int? absoluteHome;
        int? absoluteAway;

        for (final event in plate.events) {
          final pitchingTeam = half.bottom ? idTeamAway : idTeamHome;
          final pitchingId = half.bottom ? pitcherAway : pitcherHome;
          final detail = t_game_details();
          detail.id_game = gameId;
          detail.int_inning = half.inning;
          detail.flg_bottom = half.bottom;
          detail.int_score_home = scoreHome;
          detail.int_score_away = scoreAway;
          detail.id_pitcher = pitchingId;
          detail.id_batter = batterId;
          detail.int_batting_order = plate.battingOrder;
          detail.cnt_out = plate.outs;
          detail.flg_runner_first = plate.runnerFirst;
          detail.flg_runner_second = plate.runnerSecond;
          detail.flg_runner_third = plate.runnerThird;
          detail.code_category = event.category;
          detail.code_result = event.result;
          detail.double_total_bases = event.totalBases;
          detail.cnt_homerun = event.homerNumber;
          detail.code_state_score = event.stateScore;
          detail.flg_goodbye = event.goodbye;
          detail.code_direction_batting = event.direction;
          detail.code_position_from = event.positionFrom;
          detail.code_position_to = event.positionTo;
          if (detail.code_position_from.isEmpty && livePlateFinishedResults.contains(event.result)) {
            detail.code_position_from = _starterPosition(parsed, half.bottom, plate.batterName);
          }

          final onBattingSide = event.result == Value.CodeGameResult.PINCH_HITTER || event.result == Value.CodeGameResult.PINCH_RUNNER || event.result == Value.CodeGameResult.STEAL_BASE_SAFE || event.result == Value.CodeGameResult.STEAL_BASE_OUT;
          final nameTeam = onBattingSide ? battingTeam : pitchingTeam;
          if (event.exitName.isNotEmpty) {
            final exitId = playerId(event.exitName, nameTeam);
            detail.id_player_exit = exitId != 0 ? exitId : (event.pitcherChange ? pitchingId : 0);
          } else if (event.pitcherChange) {
            detail.id_player_exit = pitchingId;
          }
          if (event.enterName.isNotEmpty) {
            detail.id_player_enter = playerId(event.enterName, nameTeam);
          }
          if (event.result == Value.CodeGameResult.EXIT && detail.id_player_exit == 0 && event.exitName.isNotEmpty) {
            final other = nameTeam == battingTeam ? pitchingTeam : battingTeam;
            detail.id_player_exit = playerId(event.exitName, other);
          }

            if (!runsAssigned && (event.scoreLeft != null || event.linguisticRuns > 0 || event.timely)) {
            final resolved = _resolvedLiveScore(
              event,
              homeShortest,
              homeShort,
              awayShortest,
              awayShort,
              bottom: half.bottom,
              beforeHome: scoreHome,
              beforeAway: scoreAway,
            );
            if (resolved != null) {
              final newHome = resolved.home;
              final newAway = resolved.away;
              final delta = half.bottom ? newHome - scoreHome : newAway - scoreAway;
              detail.int_runs = delta < 0 ? 0 : delta;
              absoluteHome = newHome;
              absoluteAway = newAway;
              if (detail.code_state_score.isEmpty && detail.int_runs > 0) {
                detail.code_state_score = scoreStateFromTransition(
                  bottom: half.bottom,
                  beforeHome: scoreHome,
                  beforeAway: scoreAway,
                  afterHome: newHome,
                  afterAway: newAway,
                );
              }
            } else {
              detail.int_runs = event.linguisticRuns;
            }
            plateRuns = detail.int_runs;
            final timelyHit = event.timely && (event.result == Value.CodeGameResult.HIT_SINGLE || event.result == Value.CodeGameResult.HIT_DOUBLE || event.result == Value.CodeGameResult.HIT_TRIPLE);
            if (timelyHit && detail.int_runs < 1) {
              detail.int_runs = 1;
            }
            runsAssigned = true;
          }

          pending.add(detail);
          if (event.pitcherChange && detail.id_player_enter != 0) {
            if (half.bottom) {
              pitcherAway = detail.id_player_enter;
            } else {
              pitcherHome = detail.id_player_enter;
            }
          }
        }

        if (absoluteHome != null && absoluteAway != null) {
          scoreHome = absoluteHome;
          scoreAway = absoluteAway;
        } else if (half.bottom) {
          scoreHome += plateRuns;
        } else {
          scoreAway += plateRuns;
        }
      }
    }

    if (deleteFrom != null) {
      await Postgres.execute(conn, AppSql.deleteGameDetailsFromId(), data: [gameId, deleteFrom]);
    }
    final seenPos = <int>{};
    for (final half in parsed.halves) {
      final battingTeam = half.bottom ? idTeamHome : idTeamAway;
      for (final plate in half.plates) {
        final pos = _starterPosition(parsed, half.bottom, plate.batterName);
        if (pos.isEmpty) continue;
        final id = playerId(plate.batterName, battingTeam);
        if (id == 0 || !seenPos.add(id)) continue;
        await Postgres.execute(
          conn,
          '''
          UPDATE t_game_details
          SET code_position_from = \$3
          WHERE id_game = \$1
            AND id_batter = \$2
            AND COALESCE(BTRIM(code_position_from), '') = ''
            AND code_result NOT IN (
              'CHANGE_PITCHER', 'CHANGE_POSITION', 'PINCH_FIELDER', 'PINCH_HITTER',
              'PINCH_RUNNER', 'EXIT', 'STEAL_BASE_SAFE', 'STEAL_BASE_OUT'
            )
          ''',
          data: [gameId, id, pos],
        );
      }
    }
    if (pending.isEmpty) {
      print('テキスト速報に新しい打席はありません。');
      await _saveMaxPitchVelo(
        conn: conn,
        pageUrl: pageUrl,
        urlHref: urlHref,
        gameId: gameId,
        playerId: playerId,
        idTeamHome: idTeamHome,
        idTeamAway: idTeamAway,
      );
      return;
    }
    await Postgres.insertMulti(conn, pending);
    print('テキスト速報を${pending.length}件登録しました。');
    await _saveMaxPitchVelo(
      conn: conn,
      pageUrl: pageUrl,
      urlHref: urlHref,
      gameId: gameId,
      playerId: playerId,
      idTeamHome: idTeamHome,
      idTeamAway: idTeamAway,
    );
  }

  /// 試合終了後に一球速報から投手ごとの最速球速を t_game_details.int_velo へ書く。
  static Future<void> _saveMaxPitchVelo({
    required Connection conn,
    required Uri pageUrl,
    required String urlHref,
    required int gameId,
    required int Function(String name, int teamId) playerId,
    required int idTeamHome,
    required int idTeamAway,
  }) async {
    if (gameId <= 0 || urlHref.trim().isEmpty) return;
    await ensureGameDetailsVelo(conn);
    final stateRows = await Postgres.execute(conn, 'SELECT state FROM t_game WHERE id = \$1', data: [gameId]);
    if (stateRows.isEmpty) return;
    final state = '${stateRows.first.toColumnMap()['state'] ?? ''}';
    if (!state.contains('試合終了')) return;
    final have = await Postgres.execute(
      conn,
      'SELECT 1 FROM t_game_details WHERE id_game = \$1 AND COALESCE(int_velo, 0) > 0 LIMIT 1',
      data: [gameId],
    );
    if (have.isNotEmpty) return;

    final scoreUrl = pageUrl.resolve(gamePageHref(urlHref, 'score'));
    Document root;
    try {
      root = await YahooHtml.fetchDocument(scoreUrl);
    } catch (e) {
      print('一球速報の取得に失敗しました: $e');
      return;
    }
    final pending = Queue<String>()..addAll(LiveText.scorePlateIndexes(root).toList()..sort());
    if (pending.isEmpty) pending.add('0110100');
    final seen = <String>{};
    final maxByPitcher = <String, int>{};
    var fetched = 0;
    const maxPages = 160;
    const concurrency = 5;

    void absorb(Document doc) {
      final found = LiveText.maxKmhOnScorePage(doc);
      if (found == null) return;
      final key = StringTool.noSpace(found.pitcher);
      if (key.isEmpty) return;
      final current = maxByPitcher[key] ?? 0;
      if (found.kmh > current) maxByPitcher[key] = found.kmh;
    }

    absorb(root);

    while (pending.isNotEmpty && fetched < maxPages) {
      final batch = <String>[];
      while (pending.isNotEmpty && batch.length < concurrency && fetched + batch.length < maxPages) {
        final index = pending.removeFirst();
        if (seen.add(index)) batch.add(index);
      }
      if (batch.isEmpty) break;
      fetched += batch.length;
      if (fetched > concurrency) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      final pages = await Future.wait(batch.map((index) async {
        try {
          return await YahooHtml.fetchDocument(scoreUrl.replace(queryParameters: {'index': index}));
        } catch (e) {
          print('一球速報 index=$index を取得できませんでした: $e');
          return null;
        }
      }));
      for (final doc in pages) {
        if (doc == null) continue;
        absorb(doc);
        final next = LiveText.nextScoreIndex(doc);
        if (next != null && next.isNotEmpty && !seen.contains(next)) pending.add(next);
        for (final extra in LiveText.scorePlateIndexes(doc)) {
          if (!seen.contains(extra)) pending.add(extra);
        }
      }
    }

    if (maxByPitcher.isEmpty) {
      print('一球速報から球速を読めませんでした。');
      return;
    }

    for (final entry in maxByPitcher.entries) {
      var id = playerId(entry.key, idTeamHome);
      if (id == 0) id = playerId(entry.key, idTeamAway);
      if (id == 0) {
        print('最速球速の投手IDが見つかりません: ${entry.key}');
        continue;
      }
      await Postgres.execute(
        conn,
        '''
        UPDATE t_game_details
        SET int_velo = \$3
        WHERE id_game = \$1
          AND id_pitcher = \$2
          AND COALESCE(flg_delete, FALSE) = FALSE
        ''',
        data: [gameId, id, entry.value],
      );
    }
    print('最速球速を${maxByPitcher.length}投手分登録しました。');
  }

  static Future<Response> fetchNPBPlayers(Connection conn) async {
    final results = await conn.execute(AppSql.selectTeams());
    final clubs = results
        .map((row) => CareerClub(
              id: row[0] as int,
              league: row[1] as int,
              shortName: '${row[2] ?? ''}',
              fullName: '${row[3] ?? ''}',
              url: '${row[4] ?? ''}',
            ))
        .toList();

    List<m_player> players = [];
    final details = <_RosterDetail>[];

    for (final club in clubs.where((c) => c.url.isNotEmpty)) {
      final res = await http.get(Uri.parse(club.url));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }

      final doc = parse(_decodeHtml(res));
      final tables = doc.querySelectorAll('table.rosterlisttbl');
      if (tables.isEmpty) {
        throw Exception('テーブルが見つかりませんでした');
      }
      final table = tables.first;

      for (final tr in table.querySelectorAll('tr')) {
        final tds = tr.querySelectorAll('td');
        if (tds.isEmpty) continue;

        final cols = tds.map((td) => td.text.trim()).toList();
        print(cols);

        m_player player = m_player();

        if (cols[1].split("　").length == 2) {
          player.name_last = cols[1].split("　")[0];
          player.name_first = cols[1].split("　")[1];
        } else {
          if (StringTool.isKatakana(cols[1])) {
            player.name_last = cols[1];
          } else {
            player.name_first = cols[1];
          }
        }

        player.date_birth = _rosterBirthDate(cols[2]);
        player.uniform_number = cols[0];
        player.name_middle = '';
        player.name_full = player.name_last + player.name_first;
        player.height = int.tryParse(cols[3]) ?? 0;
        player.weight = int.tryParse(cols[4]) ?? 0;
        player.id_team = club.id;

        if (cols.length > 5) {
          if (cols[5] == '右') {
            player.pitching = 0;
          } else if (cols[5] == '左') {
            player.pitching = 1;
          } else {
            player.pitching = 2;
          }
          if (cols[6] == '右') {
            player.batting = 0;
          } else if (cols[6] == '左') {
            player.batting = 1;
          } else {
            player.batting = 2;
          }
        }
        players.add(player);

        final href = tds[1].querySelector('a')?.attributes['href']?.trim() ?? '';
        if (href.isNotEmpty) {
          details.add(_RosterDetail(player, _npbPlayerUrl(href)));
        }
      }
    }

    var cnt_rows = await Postgres.execute(conn, AppSql.selectInsertNewPlayersNPB(players));

    print("登録した新選手の数：${cnt_rows.affectedRows.toString()}");
    var birthUpdated = 0;
    for (final player in players) {
      if (player.date_birth == null) continue;
      final birth = player.date_birth!;
      final birthText = '${birth.year.toString().padLeft(4, '0')}-'
          '${birth.month.toString().padLeft(2, '0')}-'
          '${birth.day.toString().padLeft(2, '0')}';
      final updated = await conn.execute(
        AppSql.updatePlayerBirthDate(),
        parameters: [player.name_last, player.name_first, player.id_team, birthText],
      );
      birthUpdated += updated.affectedRows;
    }
    print('生年月日を更新した選手の数：$birthUpdated');
    await _insertPlayerCareers(conn, clubs, details);
    return Response.ok('ok');
  }

  /// 名簿の選手詳細から年度別成績を m_player_career へ入れる。
  /// 成績行が既にある選手は取り直さない。新人フラグが true の選手は経歴を見て、
  /// メジャー球団がいれば false にする。
  static Future<void> _insertPlayerCareers(Connection conn, List<CareerClub> clubs, List<_RosterDetail> details) async {
    var inserted = 0;
    var skipped = 0;
    var rookies = 0;
    for (final detail in details) {
      final player = detail.player;
      try {
        final found = await conn.execute(
          AppSql.selectPlayerIdByNameAndTeam(),
          parameters: [player.name_last, player.name_first, player.id_team],
        );
        if (found.isEmpty) {
          print('選手IDが見つかりません: ${player.name_full}');
          continue;
        }
        final idPlayer = found.first[0] as int;
        final exists = await conn.execute(
          AppSql.selectPlayerCareerExists(),
          parameters: [idPlayer],
        );
        final flagged = await conn.execute(
          '''
          SELECT id
          FROM m_player
          WHERE name_last = \$1
            AND name_first = \$2
            AND id_team = \$3
            AND flg_rookie IS TRUE
          ''',
          parameters: [player.name_last, player.name_first, player.id_team],
        );
        if (exists.isNotEmpty && flagged.isEmpty) {
          skipped++;
          continue;
        }

        final res = await http.get(Uri.parse(detail.url)).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) {
          print('選手詳細の取得に失敗: ${detail.url} HTTP ${res.statusCode}');
          continue;
        }
        final page = parseNpbPlayerCareer(parse(_decodeHtml(res)), clubs);
        if (page.hasMlb && flagged.isNotEmpty) {
          for (final row in flagged) {
            await conn.execute(AppSql.updatePlayerNotRookie(), parameters: [row[0]]);
          }
          print('メジャー在籍のため新人解除: ${player.name_full}');
        }
        if (exists.isNotEmpty) {
          skipped++;
          continue;
        }
        for (final row in page.rows) {
          row.id_player = idPlayer;
        }
        if (page.rows.isNotEmpty) {
          await Postgres.insertMulti(conn, page.rows);
          inserted += page.rows.length;
        }
        if (page.isRookie) {
          await conn.execute(AppSql.updatePlayerRookie(), parameters: [idPlayer]);
          rookies++;
          print('新人: ${player.name_full}');
        }
      } catch (e, stacktrace) {
        print('個人成績の登録に失敗: ${player.name_full} ${detail.url}');
        print(e);
        print(stacktrace);
      }
    }
    print('個人成績の登録行数: $inserted / 既存のためスキップ: $skipped / 新人: $rookies');
    final refreshed = await conn.execute(AppSql.updateRookieFlagsFromCareer());
    print('規定超過またはデビュー5年超過で新人解除: ${refreshed.affectedRows}');
  }

  /// 名簿の生年月日。`1988.11.01` と ISO の両方を読む。
  static DateTime? _rosterBirthDate(String raw) {
    final text = raw.trim();
    final iso = DateTime.tryParse(text);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final m = RegExp(r'^(\d{4})[./](\d{1,2})[./](\d{1,2})$').firstMatch(text);
    if (m == null) return null;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  static String _npbPlayerUrl(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) return href;
    if (href.startsWith('//')) return 'https:$href';
    if (href.startsWith('/')) return 'https://npb.jp$href';
    return 'https://npb.jp/$href';
  }

  /// 選手詳細ページの年度別投手・打撃成績と、経歴にメジャー球団が含まれるかを読む。
  static NpbCareerPage parseNpbPlayerCareer(Document doc, List<CareerClub> clubs) {
    final page = NpbCareerPage();
    page.hasMlb = _careerHasMlb(_profileText(doc, '経歴'), clubs);
    page.hasStatsTable = doc.querySelector('#tablefix_b') != null || doc.querySelector('#tablefix_p') != null;

    final byYear = <String, m_player_career>{};
    final battingSeen = <String>{};

    var unmatchedTeams = 0;

    void takeTable(String tableId, int minCells, void Function(m_player_career row, List<Element> cells) apply, bool batting) {
      final table = doc.querySelector('#$tableId');
      if (table == null) return;
      for (final tr in table.querySelectorAll('tr.registerStats')) {
        final cells = tr.children.where((e) => e.localName == 'td').toList();
        if (cells.length < minCells) continue;
        final year = int.tryParse(cells[0].text.replaceAll(RegExp(r'\s'), '')) ?? 0;
        if (year <= 0) continue;
        final teamLabel = cells[1].text.replaceAll(RegExp(r'\s'), '');
        final teamId = _matchClubId(teamLabel, clubs);
        if (teamId == null) {
          unmatchedTeams++;
          print('所属球団を特定できません: $year $teamLabel');
          continue;
        }
        final key = '$year|$teamId';
        final row = byYear.putIfAbsent(key, () {
          final created = m_player_career();
          created.int_year = year;
          created.id_team = teamId;
          return created;
        });
        apply(row, cells);
        if (batting) battingSeen.add(key);
      }
    }

    takeTable('tablefix_b', 23, (row, cells) {
      row.int_games = _cellInt(cells[2]);
      row.int_appearance = _cellInt(cells[3]);
      row.int_batting = _cellInt(cells[4]);
      row.int_runs = _cellInt(cells[5]);
      row.int_hit1 = _cellInt(cells[6]);
      row.int_hit2 = _cellInt(cells[7]);
      row.int_hit3 = _cellInt(cells[8]);
      row.int_homerun = _cellInt(cells[9]);
      row.int_total_bases = _cellInt(cells[10]);
      row.int_rbi = _cellInt(cells[11]);
      row.int_steal_base = _cellInt(cells[12]);
      row.int_steal_caught = _cellInt(cells[13]);
      row.int_sacrifice = _cellInt(cells[14]);
      row.int_four_batting = _cellInt(cells[16]);
      row.int_dead_batting = _cellInt(cells[17]);
      row.int_strike_out_batting = _cellInt(cells[18]);
      row.int_double_play = _cellInt(cells[19]);
      row.double_average_batting = _cellDouble(cells[20]);
      row.double_average_slugging = _cellDouble(cells[21]);
      row.double_average_onbase = _cellDouble(cells[22]);
    }, true);

    takeTable('tablefix_p', 24, (row, cells) {
      if (!battingSeen.contains('${row.int_year}|${row.id_team}')) {
        row.int_games = _cellInt(cells[2]);
      }
      row.int_pitching = _cellInt(cells[2]);
      row.int_win = _cellInt(cells[3]);
      row.int_lose = _cellInt(cells[4]);
      row.int_save = _cellInt(cells[5]);
      row.int_hold = _cellInt(cells[6]);
      row.int_hold_point = _cellInt(cells[7]);
      row.int_complete_game = _cellInt(cells[8]);
      row.int_shutout = _cellInt(cells[9]);
      row.int_without_walks = _cellInt(cells[10]);
      row.double_average_win = _cellDouble(cells[11]);
      row.int_batter = _cellInt(cells[12]);
      row.double_inning = _cellDouble(cells[13]);
      row.int_hit_pitcher = _cellInt(cells[14]);
      row.int_homerun_pitcher = _cellInt(cells[15]);
      row.int_four_pitcher = _cellInt(cells[16]);
      row.int_dead_pitcher = _cellInt(cells[17]);
      row.int_strike_out_pitcher = _cellInt(cells[18]);
      row.int_wild_pitch = _cellInt(cells[19]);
      row.int_balk = _cellInt(cells[20]);
      row.int_runs_allowed = _cellInt(cells[21]);
      row.int_earned_runds = _cellInt(cells[22]);
      row.double_average_earned_runs = _cellDouble(cells[23]);
    }, false);

    page.rows = byYear.values.toList()..sort((a, b) => a.int_year.compareTo(b.int_year));
    page.isRookie = page.hasStatsTable && unmatchedTeams == 0 && !page.hasMlb && _withinRookieWindow(page.rows);
    return page;
  }

  static String _profileText(Document doc, String label) {
    for (final tr in doc.querySelectorAll('tr')) {
      final th = tr.querySelector('th');
      if (th == null || th.text.trim() != label) continue;
      final td = tr.querySelector('td');
      if (td != null) return td.text.trim();
    }
    return '';
  }

  /// 経歴の所属遍歴に、m_team.id_league が 3 または 4 の球団が含まれるか。
  static bool _careerHasMlb(String career, List<CareerClub> clubs) {
    final tokens = career.split(RegExp(r'\s*[-－–—]\s*')).map((s) => s.trim()).where((s) => s.isNotEmpty);
    final npb = clubs.where((c) => c.league == 1 || c.league == 2);
    final mlb = clubs.where((c) => c.league == 3 || c.league == 4);
    for (final token in tokens) {
      final name = token.replaceAll('・', '').replaceAll(RegExp(r'\s'), '');
      final npbHit = npb.any((c) => c.shortName.length >= 2 && name.contains(c.shortName));
      if (npbHit) continue;
      final mlbHit = mlb.any((c) {
        if (c.shortName.length >= 2 && name.contains(c.shortName)) return true;
        final full = c.fullName.replaceAll('・', '').replaceAll(RegExp(r'\s'), '');
        return name.length >= 2 && full.contains(name);
      });
      if (mlbHit) return true;
    }
    return false;
  }

  static int? matchCareerClubId(
    String raw,
    List<CareerClub> clubs, {
    bool preferMlb = false,
  }) =>
      _matchClubId(raw, clubs, preferMlb: preferMlb);

  static int? _matchClubId(
    String raw,
    List<CareerClub> clubs, {
    bool preferMlb = false,
  }) {
    final name = raw.replaceAll(RegExp(r'[\s　]'), '').replaceAll('・', '');
    if (name.isEmpty) return null;
    int? bestId;
    var bestScore = 0;
    for (final club in clubs) {
      final short = club.shortName.replaceAll('・', '');
      final full = club.fullName.replaceAll(RegExp(r'[\s　]'), '').replaceAll('・', '');
      var score = 0;
      if (short.length >= 2 && name.contains(short)) score = short.length * 10;
      if (name.length >= 2 && full.contains(name)) score = max(score, name.length * 10 + 1);
      if (score == 0) continue;
      final leagueBonus = preferMlb
          ? ((club.league == 3 || club.league == 4) ? 1 : 0)
          : ((club.league == 1 || club.league == 2) ? 1 : 0);
      final total = score * 10 + leagueBonus;
      if (total > bestScore) {
        bestScore = total;
        bestId = club.id;
      }
    }
    return bestId;
  }

  /// 初年度から5年のあいだだけ新人候補。期間を過ぎていれば対象外。
  /// 期間内は、今季より前の通算打席が60以内、かつ通算投球回が30以内。
  /// 基準に達したシーズンも新人王の有資格なので、今季の成績は通算に含めない。
  static bool _withinRookieWindow(List<m_player_career> rows) {
    final years = rows.map((r) => r.int_year).where((y) => y > 0);
    if (years.isEmpty) return true;
    final first = years.reduce(min);
    final last = first + 4;
    final thisYear = DateTimeTool.getThisYear();
    if (thisYear > last) return false;
    var pa = 0;
    var thirds = 0;
    for (final row in rows) {
      if (row.int_year < first || row.int_year > last || row.int_year >= thisYear) continue;
      pa += row.int_appearance;
      thirds += _ipThirds(row.double_inning);
    }
    return pa <= 60 && thirds <= 90;
  }

  /// 186.1 のような野球の投球回を、1/3回単位の整数にする。
  static int _ipThirds(double ip) {
    final whole = ip.truncate();
    final frac = ((ip - whole) * 10).round().clamp(0, 2);
    return whole * 3 + frac;
  }

  static int _cellInt(Element cell) {
    return int.tryParse(cell.text.replaceAll(RegExp(r'\s'), '')) ?? 0;
  }

  static double _cellDouble(Element cell) {
    return double.tryParse(cell.text.replaceAll(RegExp(r'\s'), '')) ?? 0;
  }

  /// 盗塁と盗塁死から成功率（%）。表示は小数1桁。企図が無ければ null。
  static double? stolenBaseSuccessPercent(int steals, int caught) {
    final attempts = steals + caught;
    if (steals < 0 || caught < 0 || attempts <= 0) return null;
    return (steals * 1000 / attempts).round() / 10;
  }

  /// 162.1 は 162回1/3。小数のまま割らない。
  static double baseballInnings(String raw) {
    final v = double.tryParse(raw.trim()) ?? 0;
    if (v <= 0) return 0;
    final whole = v.truncate();
    final thirds = ((v - whole) * 10).round().clamp(0, 2);
    return whole + thirds / 3.0;
  }

  /// 与四球と投球回から BB/9。表示は小数2桁。
  static double? walksPerNine(int walks, String innings) {
    final ip = baseballInnings(innings);
    if (walks < 0 || ip <= 0) return null;
    return (walks * 9 / ip * 100).round() / 100;
  }

  /// 同値は同じ順位。次の順位は人数分飛ばす。
  static void assignCompetitionRanks(List<t_stats_player> rows, {required bool higherIsBetter}) {
    rows.sort((a, b) {
      final cmp = higherIsBetter ? b.stats.compareTo(a.stats) : a.stats.compareTo(b.stats);
      if (cmp != 0) return cmp;
      return b.cnt_play.compareTo(a.cnt_play);
    });
    var rank = 0;
    double? prev;
    for (var i = 0; i < rows.length; i++) {
      if (prev == null || rows[i].stats != prev) {
        rank = i + 1;
        prev = rows[i].stats;
      }
      rows[i].int_rank = rank;
    }
  }

  static Future<Response> fetchStatsPlayerNPB(Connection conn) async {
    return fetchStatsPlayerForLeagues(conn, const [1, 2]);
  }

  /// NPB / MLB 共通。指定リーグの m_stats_details URL を巡回して個人成績を登録する。
  static Future<Response> fetchStatsPlayerForLeagues(Connection conn, List<int> leagueIds) async {
    // t_stats_player は履歴用に削除せず INSERT のみ。
    // t_stats_player_latest のみ同内容で deleteInsert する。
    final results = await conn.execute(AppSql.selectStatsDetails(leagueIds: leagueIds));
    final stats = Postgres.toMap(results);

    for (final stat in stats) {
      final title = '${stat['title'] ?? ''}'.trim();
      print('statsID:' + stat['id_stats'].toString() + ' ' + title);
      var url = '${stat['url'] ?? ''}'.trim();
      if (url.isEmpty) continue;
      // MLB: DB に古い gameKindId=1/2 や誤った /npb/ パスが残っていても補正する。
      final leagueId = int.tryParse('${stat['id_league']}') ?? 0;
      if (leagueId == 3 || leagueId == 4) {
        url = url.replaceAll('/npb/stats/', '/mlb/stats/');
        url = url.replaceAllMapped(RegExp(r'gameKindId=(\d+)'), (match) {
          final id = match.group(1)!;
          if (id == '1') return 'gameKindId=1001';
          if (id == '2') return 'gameKindId=1002';
          return match.group(0)!;
        });
      }
      http.Response res;
      try {
        res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
      } catch (e) {
        print('個人成績URL取得失敗 ($title): $e');
        continue;
      }
      if (res.statusCode != 200) {
        print('個人成績HTTP ${res.statusCode} ($title) $url');
        continue;
      }

      final doc = parse(_decodeHtml(res));
      final tables = doc.querySelectorAll('#js-playerTable');
      if (tables.isEmpty) {
        print('個人成績テーブルなし ($title) $url');
        continue;
      }

      final table = tables.first;
      List<t_stats_player> listStats = [];
      final colIdx = int.tryParse('${stat['int_idx_col']}') ?? 0;
      final isPitcherTable = url.contains('/pitcher');

      for (final tr in table.querySelectorAll('tr')) {
        try {
          final tds = tr.querySelectorAll('td');
          if (tds.isEmpty) continue;

          final cols = tds.map((td) => td.text.trim()).toList();
          if (cols.length < 2) continue;

          final parsed = _parseYahooRankingPlayerCell(cols[1]);
          var name_player = parsed.player;
          final name_team_home = parsed.team;
          if (name_player.isEmpty || name_team_home.isEmpty) continue;

          //同じ球団内に同じ名字の選手が複数在籍していないかチェックする
          final result_player = await Postgres.execute(
            conn,
            AppSql.selectPlayerWhereFullNameAndTeamIDLike(),
            data: [StringTool.noSpace(name_player), name_team_home],
          );

          if (result_player.length > 1) {
            //一つの球団に同じ名字の選手が複数人在籍している場合、さらに選手ページをクリックしてフルネームを取得する
            final href = tds[1].querySelector('a')?.attributes['href']?.trim() ?? '';
            if (href.isNotEmpty) {
              final url_player = href.startsWith('http') ? href : 'https://baseball.yahoo.co.jp$href';
              final res_player = await http.get(Uri.parse(url_player));
              if (res_player.statusCode == 200) {
                final doc_player = parse(_decodeHtml(res_player));
                final ruby = doc_player.querySelector('ruby.bb-profile__ruby')?.text ?? '';
                if (ruby.isNotEmpty) {
                  name_player = ruby.split('（')[0].trim();
                }
              }
            }
          }

          // Yahoo の個人成績表。野手は 4打席 18盗塁 19盗塁死、投手は 3登板 14投球回 19与四球。
          double? value;
          var playCount = 0;
          var appearances = 0;
          var starts = 0;
          var innings = 0.0;
          var wins = 0;
          var strikeouts = 0;
          var era = 0.0;
          int? rank = int.tryParse(cols[0]);
          if (title == '盗塁成功率') {
            final steals = int.tryParse(cols.elementAtOrNull(18) ?? '') ?? -1;
            final caught = int.tryParse(cols.elementAtOrNull(19) ?? '') ?? -1;
            value = stolenBaseSuccessPercent(steals, caught);
            playCount = steals + caught;
            rank = null;
          } else if (title == '与四球率') {
            final walks = int.tryParse(cols.elementAtOrNull(19) ?? '') ?? -1;
            final rawIp = cols.elementAtOrNull(14) ?? '';
            value = walksPerNine(walks, rawIp);
            innings = double.tryParse(rawIp) ?? 0;
            appearances = int.tryParse(cols.elementAtOrNull(3) ?? '') ?? 0;
            playCount = innings > 0 ? innings.truncate() : 0;
            rank = null;
          } else if (colIdx >= 0 && colIdx < cols.length) {
            value = double.tryParse(cols[colIdx]);
            if (isPitcherTable) {
              appearances = int.tryParse(cols.elementAtOrNull(3) ?? '') ?? 0;
              starts = int.tryParse(cols.elementAtOrNull(4) ?? '') ?? 0;
              wins = int.tryParse(cols.elementAtOrNull(8) ?? '') ?? 0;
              innings = double.tryParse(cols.elementAtOrNull(14) ?? '') ?? 0;
              strikeouts = int.tryParse(cols.elementAtOrNull(17) ?? '') ?? 0;
              era = double.tryParse(cols.elementAtOrNull(2) ?? '') ?? 0;
              playCount = innings > 0 ? innings.truncate() : 0;
            } else {
              playCount = int.tryParse(cols.elementAtOrNull(4) ?? '') ?? 0;
            }
          }
          if (value == null) continue;

          t_stats_player statsPlayer = t_stats_player();
          statsPlayer.id_league = stat['id_league'] as int;
          statsPlayer.id_stats = stat['id_stats'] as int;
          statsPlayer.stats = value;
          statsPlayer.cnt_play = playCount;
          statsPlayer.int_rank = rank ?? 0;
          statsPlayer.playerName = StringTool.noSpace(name_player);
          statsPlayer.teamName = name_team_home;
          statsPlayer.seasonAppearances = appearances;
          statsPlayer.seasonStarts = starts;
          statsPlayer.seasonInnings = innings;
          statsPlayer.seasonWins = wins;
          statsPlayer.seasonStrikeouts = strikeouts;
          statsPlayer.seasonEra = era;
          final playerHref = tds[1].querySelector('a[href*="/mlb/player/"]')?.attributes['href']?.trim() ??
              tds[1].querySelector('a')?.attributes['href']?.trim() ??
              '';
          if (playerHref.isNotEmpty) {
            statsPlayer.playerUrl = playerHref.startsWith('http') ? playerHref : 'https://baseball.yahoo.co.jp$playerHref';
          }
          listStats.add(statsPlayer);
        } catch (e) {
          print('個人成績行スキップ ($title): $e');
        }
      } //for選手

      if (title == '盗塁成功率') {
        assignCompetitionRanks(listStats, higherIsBetter: true);
      } else if (title == '与四球率') {
        assignCompetitionRanks(listStats, higherIsBetter: false);
      }
      if (listStats.isEmpty) continue;

      final leagueIdForPlayers = int.tryParse('${stat['id_league']}') ?? 0;
      if (leagueIdForPlayers == 3 || leagueIdForPlayers == 4) {
        for (final row in listStats) {
          await _ensureMlbRankingPlayer(
            conn,
            row.playerName,
            row.teamName,
            playerUrl: row.playerUrl,
          );
        }
      }
      if (isPitcherTable) {
        for (final row in listStats) {
          if (row.seasonAppearances <= 0 && row.seasonInnings <= 0) continue;
          await upsertPitcherSeasonLine(
            conn,
            playerName: row.playerName,
            teamToken: row.teamName,
            appearances: row.seasonAppearances,
            starts: row.seasonStarts,
            innings: row.seasonInnings,
            wins: row.seasonWins,
            strikeouts: row.seasonStrikeouts,
            era: row.seasonEra,
          );
        }
      }

      var sql = AppSql.selectInsertStatsPlayer(listStats);

      var cnt_rows = await Postgres.execute(conn, sql);
      print("個人成績の登録数" + cnt_rows.affectedRows.toString());

      // t_stats_player_latest を同内容で deleteInsert
      await conn.execute(
        AppSql.deleteStatsPlayerLatestByStats(),
        parameters: [stat['id_stats'] as int, stat['id_league'] as int],
      );
      final cnt_latest = await Postgres.execute(
        conn,
        AppSql.selectInsertStatsPlayer(
          listStats,
          tableName: t_stats_player_latest().tableName,
        ),
      );
      print("個人成績latestの登録数" + cnt_latest.affectedRows.toString());
    } //for stat

    //予想者が予想した選手がランク外だった場合は選手個人のサイトをスクレイピングして個人成績を取得する
    List<DBModel> listStatsPlayerNoRank = [];
    final result_stats_player = await Postgres.execute(conn, AppSql.selectStatsPlayerNoRank(), data: [DateTimeTool.getThisYear()]);
    final stats_player_map = Postgres.toMap(result_stats_player);
    final leagueIdSet = leagueIds.toSet();

    if (stats_player_map.isNotEmpty) {
      for (final stats_player in stats_player_map) {
        final rowLeague = int.tryParse('${stats_player['id_league']}') ?? 0;
        if (!leagueIdSet.contains(rowLeague)) continue;
        try {
          print(stats_player);
          var url = '${stats_player['url'] ?? ''}';
          if (url.isEmpty) continue;

          final res = await http.get(Uri.parse(url));
          if (res.statusCode != 200) {
            print('ランク外選手HTTP ${res.statusCode}: $url');
            continue;
          }

          final doc = parse(_decodeHtml(res));
          final rows = doc.querySelectorAll('#js-tabDom01 table.bb-playerStatsTable tbody tr');
          if (rows.isEmpty) {
            print('ランク外選手テーブルなし: $url');
            continue;
          }

          var idx_col = stats_player['int_idx_col_details'] as int;
          var idx_row = stats_player['int_idx_row_details'] as int;
          if (idx_row < 0 || idx_row >= rows.length) continue;
          final detailCols = rows[idx_row].querySelectorAll('td');
          if (idx_col < 0 || idx_col >= detailCols.length) continue;

          t_stats_player statsPlayer = t_stats_player();
          statsPlayer.id_player = stats_player['id_player'] as int;
          statsPlayer.id_team = stats_player['id_team'] as int;
          statsPlayer.id_league = stats_player['id_league'] as int;
          statsPlayer.id_stats = stats_player['id_stats'] as int;
          statsPlayer.stats = double.tryParse(detailCols[idx_col].text.trim()) ?? 0;
          statsPlayer.int_rank = 1000;
          statsPlayer.playerName = '${stats_player['name_full'] ?? ''}';
          statsPlayer.teamName = '${stats_player['name_shortest'] ?? ''}';
          if (stats_player['flg_pitcher'] as bool) {
            //投手の場合は投球回のセルから数値をスクレイピング（例: 12.1 → 12）
            final rawIp = detailCols.length > 14 ? detailCols[14].text.trim() : '';
            statsPlayer.cnt_play = double.tryParse(rawIp)?.truncate() ?? int.tryParse(rawIp) ?? 0;
          } else {
            //野手の場合は打席数のセルから数値をスクレイピング
            final rawPa = detailCols.length > 2 ? detailCols[2].text.trim() : '';
            statsPlayer.cnt_play = double.tryParse(rawPa)?.truncate() ?? int.tryParse(rawPa) ?? 0;
          }
          if (statsPlayer.cnt_play == 0) {
            print('☠️打席数または投球回をスクレイピングできませんでした。☠️');
          }
          print(statsPlayer.toMap());
          listStatsPlayerNoRank.add(statsPlayer);
        } catch (e) {
          print('ランク外選手スキップ: $e');
        }
      }
    }

    if (listStatsPlayerNoRank.isNotEmpty) {
      await Postgres.insertMulti(conn, listStatsPlayerNoRank);

      // t_stats_player_latest を同内容で deleteInsert
      final List<DBModel> listLatest = [];
      for (final model in listStatsPlayerNoRank) {
        final src = model as t_stats_player;
        await conn.execute(
          AppSql.deleteStatsPlayerLatestByPlayer(),
          parameters: [src.id_player, src.id_stats, src.id_league],
        );
        final latest = t_stats_player_latest();
        latest.id_league = src.id_league;
        latest.id_stats = src.id_stats;
        latest.id_player = src.id_player;
        latest.id_team = src.id_team;
        latest.int_rank = src.int_rank;
        latest.stats = src.stats;
        latest.cnt_play = src.cnt_play;
        listLatest.add(latest);
      }
      await Postgres.insertMulti(conn, listLatest);
    }

    return Response.ok('ok');
  }

  /// MLB 個人成績用。略称（NYY 等）または name_short で球団を引き、未登録選手を作る。
  /// [playerUrl] があれば出身地を取り、国・県/州を登録する。
  /// [fetchProfile] が false のときは URL 紐づけのみ（ランキング横断の一括補完用）。
  static Future<void> ensureMlbRankingPlayer(
    Connection conn,
    String playerName,
    String teamToken, {
    String? playerUrl,
    bool fetchProfile = true,
  }) async {
    await _ensureMlbRankingPlayer(
      conn,
      playerName,
      teamToken,
      playerUrl: playerUrl,
      fetchProfile: fetchProfile,
    );
  }

  static Future<void> _ensureMlbRankingPlayer(
    Connection conn,
    String playerName,
    String teamToken, {
    String? playerUrl,
    bool fetchProfile = true,
  }) async {
    final name = StringTool.noSpace(playerName);
    final teamKey = teamToken.trim();
    if (name.isEmpty || teamKey.isEmpty) return;
    Result teamRows = await Postgres.execute(conn, AppSql.selectTeamsWhereNameShortest(), data: [teamKey]);
    if (teamRows.isEmpty) {
      teamRows = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [YahooTeamNames.normalize(teamKey)]);
    }
    if (teamRows.isEmpty) {
      print('MLB個人成績: 未知の球団略称 "$teamKey" ($name)');
      return;
    }
    final teamId = teamRows.first.toColumnMap()['id'] as int;
    final existing = await conn.execute(
      '''
        SELECT id, name_full, id_country, url, date_birth FROM m_player
        WHERE id_team = \$1::int
          AND COALESCE(flg_delete, FALSE) = FALSE
          AND (
            name_full = \$2::text
            OR name_last = \$2::text
            OR COALESCE(name_last, '') || COALESCE(name_first, '') = \$2::text
            OR name_full LIKE \$2::text || '%'
            OR \$2::text LIKE name_full || '%'
            OR (
              COALESCE(name_last, '') <> ''
              AND length(name_last) >= 2
              AND \$2::text LIKE '%' || name_last
            )
            OR (
              length(regexp_replace(\$2::text, '^.*?[\\.．]', '')) >= 2
              AND (
                name_full LIKE '%' || regexp_replace(\$2::text, '^.*?[\\.．]', '')
                OR regexp_replace(name_full, '^.*・', '')
                     = regexp_replace(\$2::text, '^.*?[\\.．]', '')
                OR name_last = regexp_replace(\$2::text, '^.*?[\\.．]', '')
              )
            )
            OR (
              position('・' in name_full) > 0
              AND length(regexp_replace(name_full, '^.*・', '')) >= 2
              AND (
                \$2::text LIKE '%' || regexp_replace(name_full, '^.*・', '')
                OR regexp_replace(\$2::text, '^.*?[\\.．]', '')
                     = regexp_replace(name_full, '^.*・', '')
              )
            )
          )
        ORDER BY
          CASE
            WHEN name_full = \$2::text THEN 0
            WHEN COALESCE(name_last, '') || COALESCE(name_first, '') = \$2::text THEN 1
            WHEN name_last = \$2::text THEN 2
            WHEN name_full LIKE \$2::text || '%' THEN 3
            WHEN \$2::text LIKE name_full || '%' THEN 4
            ELSE 5
          END,
          length(COALESCE(name_full, '')) DESC
        LIMIT 1
      ''',
      parameters: [teamId, name],
    );
    var playerId = 0;
    var needsCountry = true;
    var needsBirth = true;
    var storedUrl = '';
    if (existing.isNotEmpty) {
      final row = existing.first.toColumnMap();
      playerId = row['id'] as int;
      storedUrl = '${row['url'] ?? ''}'.trim();
      final countryRaw = row['id_country'];
      needsCountry = countryRaw == null || '$countryRaw' == '0';
      needsBirth = row['date_birth'] == null;
      final full = '${row['name_full'] ?? ''}';
      if (full.isEmpty) {
        await conn.execute(
          '''
            UPDATE m_player
            SET name_full = \$1::text,
                name_last = COALESCE(NULLIF(name_last, ''), \$1::text),
                updat = NOW()
            WHERE id = \$2::int
          ''',
          parameters: [name, playerId],
        );
      }
    } else {
      final player = m_player()
        ..name_last = name
        ..name_first = ''
        ..name_full = name
        ..id_team = teamId;
      playerId = await Postgres.insert(conn, player);
    }
    if (playerId <= 0) return;

    final url = (playerUrl ?? '').trim();
    if (url.isNotEmpty) {
      storedUrl = storedUrl.isEmpty ? url : storedUrl;
      await conn.execute(
        '''
          UPDATE m_player
          SET url = CASE WHEN COALESCE(url, '') = '' THEN \$1::text ELSE url END,
              updat = NOW()
          WHERE id = \$2::int
        ''',
        parameters: [url, playerId],
      );
    }

    if (!fetchProfile) return;
    if (!needsCountry && !needsBirth) return;
    final profileUrl = (url.isNotEmpty ? url : storedUrl).replaceFirst(RegExp(r'/top/?$'), '/');
    if (profileUrl.isEmpty) return;
    try {
      final res = await http.get(Uri.parse(profileUrl)).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return;
      final doc = parse(_decodeHtml(res));
      if (needsCountry) await BirthPlaceRegistry.applyFromProfile(conn, playerId, doc);
      if (needsBirth) await BirthPlaceRegistry.applyBirthDate(conn, playerId, BirthPlaceRegistry.extractBirthDate(doc));
    } catch (e) {
      print('MLBプロフィール取得スキップ ($name): $e');
    }
  }

  /// 投手ランキング行から得たシーズン成績を m_player_career に反映する。
  static Future<bool> upsertPitcherSeasonLine(
    Connection conn, {
    required String playerName,
    required String teamToken,
    required int appearances,
    int starts = 0,
    required double innings,
    int wins = 0,
    int strikeouts = 0,
    double era = 0,
  }) async {
    final name = StringTool.noSpace(playerName);
    final teamKey = teamToken.trim();
    if (name.isEmpty || teamKey.isEmpty) return false;
    if (appearances <= 0 && innings <= 0) return false;

    Result teamRows = await Postgres.execute(conn, AppSql.selectTeamsWhereNameShortest(), data: [teamKey]);
    if (teamRows.isEmpty) {
      teamRows = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [YahooTeamNames.normalize(teamKey)]);
    }
    if (teamRows.isEmpty) return false;
    final teamId = teamRows.first.toColumnMap()['id'] as int;

    // MLB の "C.シュリトラー" と "キャメロン・シュリトラー" を姓でつなぐ。
    final surname = name.contains('.') ? name.split('.').last.trim() : name;
    final players = await conn.execute(
      '''
        SELECT id FROM m_player
        WHERE id_team = \$1::int
          AND (
            name_full = \$2::text
            OR name_last = \$2::text
            OR COALESCE(name_last, '') || COALESCE(name_first, '') = \$2::text
            OR name_full LIKE '%' || \$2::text || '%'
            OR COALESCE(name_last, '') || COALESCE(name_first, '') LIKE '%' || \$2::text || '%'
            OR (\$3::text <> '' AND (
              name_full LIKE '%' || \$3::text || '%'
              OR name_last LIKE '%' || \$3::text || '%'
              OR name_last = \$3::text
            ))
          )
        ORDER BY
          CASE
            WHEN name_full = \$2::text OR name_last = \$2::text THEN 0
            WHEN \$3::text <> '' AND (name_full LIKE '%' || \$3::text OR name_last = \$3::text) THEN 1
            ELSE 2
          END
        LIMIT 1
      ''',
      parameters: [teamId, name, surname],
    );
    if (players.isEmpty) return false;
    final playerId = players.first.toColumnMap()['id'] as int;
    final year = DateTimeTool.getThisYear();

    final existing = await conn.execute(
      '''
        SELECT id FROM m_player_career
        WHERE id_player = \$1::int
          AND int_year = \$2::int
          AND COALESCE(flg_delete, FALSE) = FALSE
        LIMIT 1
      ''',
      parameters: [playerId, year],
    );
    if (existing.isEmpty) {
      final career = m_player_career()
        ..id_player = playerId
        ..int_year = year
        ..id_team = teamId
        ..int_pitching = appearances
        ..int_games = starts > 0 ? starts : appearances
        ..double_inning = innings
        ..int_win = wins
        ..int_strike_out_pitcher = strikeouts
        ..double_average_earned_runs = era;
      await Postgres.insert(conn, career);
      return true;
    }
    await conn.execute(
      '''
        UPDATE m_player_career
        SET int_pitching = GREATEST(COALESCE(int_pitching, 0), \$1::int),
            double_inning = GREATEST(COALESCE(double_inning, 0), \$2::float8),
            int_win = GREATEST(COALESCE(int_win, 0), \$3::int),
            int_strike_out_pitcher = GREATEST(COALESCE(int_strike_out_pitcher, 0), \$4::int),
            double_average_earned_runs = CASE
              WHEN \$5::float8 > 0 THEN \$5::float8
              ELSE COALESCE(double_average_earned_runs, 0)
            END,
            int_games = GREATEST(COALESCE(int_games, 0), \$6::int),
            id_team = \$7::int,
            updat = NOW()
        WHERE id = \$8::int
      ''',
      parameters: [
        appearances,
        innings,
        wins,
        strikeouts,
        era,
        starts > 0 ? starts : appearances,
        teamId,
        existing.first.toColumnMap()['id'],
      ],
    );
    return true;
  }

  /// Yahoo ランキング表の「選手名 (球団)」セルを NPB/MLB 共通で分解する。
  static ({String player, String team}) parseYahooRankingPlayerCell(String raw) => _parseYahooRankingPlayerCell(raw);

  /// Yahoo ランキング表の「選手名 (球団)」セルを NPB/MLB 共通で分解する。
  static ({String player, String team}) _parseYahooRankingPlayerCell(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return (player: '', team: '');
    final paren = RegExp(r'[\(（]([^\)）]+)[\)）]').firstMatch(text);
    if (paren != null) {
      final team = paren.group(1)?.trim() ?? '';
      final player = text.substring(0, paren.start).trim();
      // NPB は姓名の先頭トークン、MLB は "Y.アルバレス" のような1トークンを優先
      final tokens = player.split(RegExp(r'[\s　]+')).where((e) => e.isNotEmpty).toList();
      final nameToken = tokens.isEmpty ? player : tokens.first;
      return (player: nameToken, team: team);
    }
    final parts = text.split(RegExp(r'[\s　]+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (
        player: parts.first,
        team: parts[1].replaceAll(RegExp(r'[\(（\)）]'), ''),
      );
    }
    return (player: text, team: '');
  }
}

int _detailInt(Object? value) {
  if (value is int) return value;
  if (value is BigInt) return value.toInt();
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

bool _detailBool(Object? value) {
  if (value is bool) return value;
  final text = '${value ?? ''}'.toLowerCase();
  return text == 'true' || text == 't';
}

const _mlbAbbrevAliases = <String, List<String>>{
  'ATL': ['ブレーブス'],
  'MIA': ['マーリンズ'],
  'NYM': ['メッツ'],
  'PHI': ['フィリーズ'],
  'WSH': ['ナショナルズ'],
  'WAS': ['ナショナルズ'],
  'CHC': ['カブス'],
  'CIN': ['レッズ'],
  'MIL': ['ブルワーズ', 'ブリュワーズ'],
  'PIT': ['パイレーツ'],
  'STL': ['カージナルス'],
  'ARI': ['ダイヤモンドバックス', 'Dバックス'],
  'COL': ['ロッキーズ'],
  'LAD': ['ドジャース'],
  'LA': ['ドジャース'],
  'SD': ['パドレス'],
  'SDP': ['パドレス'],
  'SF': ['ジャイアンツ'],
  'BAL': ['オリオールズ'],
  'BOS': ['レッドソックス', 'Rソックス'],
  'NYY': ['ヤンキース'],
  'TB': ['レイズ'],
  'TBR': ['レイズ'],
  'TOR': ['ブルージェイズ'],
  'CWS': ['ホワイトソックス', 'Wソックス'],
  'CHW': ['ホワイトソックス', 'Wソックス'],
  'CLE': ['ガーディアンズ'],
  'DET': ['タイガース'],
  'KC': ['ロイヤルズ'],
  'MIN': ['ツインズ'],
  'HOU': ['アストロズ'],
  'LAA': ['エンゼルス'],
  'OAK': ['アスレチックス'],
  'ATH': ['アスレチックス'],
  'SEA': ['マリナーズ'],
  'TEX': ['レンジャーズ'],
};

bool _mlbAbbrevMatches(String abbrev, String teamName) {
  final key = abbrev.toUpperCase();
  final aliases = _mlbAbbrevAliases[key];
  if (aliases == null) return false;
  final team = StringTool.noSpace(teamName);
  return aliases.any((alias) => team.contains(alias) || alias.contains(team));
}

bool? _liveScoreLeftIsHome(
  ParsedLiveEvent event,
  String homeShortest,
  String homeShort,
  String awayShortest,
  String awayShort,
) {
  bool matches(String name) {
    final left = StringTool.noSpace(event.scoreLeftName);
    final team = StringTool.noSpace(name);
    if (left.isEmpty || team.isEmpty) return false;
    if (left == team || team.startsWith(left) || left.startsWith(team)) return true;
    return _mlbAbbrevMatches(left, team);
  }

  final home = matches(homeShortest) || matches(homeShort);
  final away = matches(awayShortest) || matches(awayShort);
  if (home && !away) return true;
  if (away && !home) return false;
  return null;
}

({int home, int away})? _resolvedLiveScore(
  ParsedLiveEvent event,
  String homeShortest,
  String homeShort,
  String awayShortest,
  String awayShort, {
  required bool bottom,
  required int beforeHome,
  required int beforeAway,
}) {
  final left = event.scoreLeft;
  final right = event.scoreRight;
  if (left == null || right == null) return null;

  final leftIsHome = _liveScoreLeftIsHome(event, homeShortest, homeShort, awayShortest, awayShort);
  if (leftIsHome != null) {
    return leftIsHome ? (home: left, away: right) : (home: right, away: left);
  }

  // MLB 速報のスコアは球団略称（MIL 3-2 CHC 等）で、DB の日本語球団名と
  // 一致しないことがある。攻撃側だけ得点が増え、守備側は変わらない向きを採る。
  final candidates = <({int home, int away})>[
    (home: left, away: right),
    (home: right, away: left),
  ];
  final valid = candidates.where((score) {
    if (bottom) {
      return score.away == beforeAway && score.home >= beforeHome;
    }
    return score.home == beforeHome && score.away >= beforeAway;
  }).toList();
  if (valid.length == 1) return valid.single;
  if (valid.length > 1) {
    valid.sort((a, b) {
      final aRuns = bottom ? a.home - beforeHome : a.away - beforeAway;
      final bRuns = bottom ? b.home - beforeHome : b.away - beforeAway;
      return bRuns.compareTo(aRuns);
    });
    return valid.first;
  }
  return null;
}

class _LineScore {
  String scoresHome = '';
  String scoresAway = '';
  int runsHome = 0;
  int runsAway = 0;
  int hitsHome = 0;
  int hitsAway = 0;
  int errorsHome = 0;
  int errorsAway = 0;
}

bool _sameTeamName(String a, String b) {
  final left = YahooTeamNames.normalize(StringTool.noSpace(a)).toLowerCase();
  final right = YahooTeamNames.normalize(StringTool.noSpace(b)).toLowerCase();
  if (left.isEmpty || right.isEmpty) return false;
  return left == right || left.contains(right) || right.contains(left);
}

/// 出場成績のイニング得点を、保存済みの試合サマリーへそのまま書く。
Future<void> _saveOfficialLineScore(Connection conn, Document doc, int gameId) async {
  final names = await Postgres.execute(
    conn,
    '''
      SELECT
        home.name_short AS name_home,
        home.name_shortest AS name_home_shortest,
        away.name_short AS name_away,
        away.name_shortest AS name_away_shortest
      FROM t_game g
      JOIN m_team home ON home.id = g.id_team_home
      JOIN m_team away ON away.id = g.id_team_away
      WHERE g.id = \$1
    ''',
    data: [gameId],
  );
  if (names.isEmpty) return;
  final row = names.first.toColumnMap();
  final homeShort = '${row['name_home'] ?? ''}';
  final awayShort = '${row['name_away'] ?? ''}';
  final homeShortest = '${row['name_home_shortest'] ?? ''}';
  final awayShortest = '${row['name_away_shortest'] ?? ''}';
  // MLB は略称表記が多いので short / shortest の順で照合する
  final line = _parseLineScore(doc, homeShort, awayShort) ??
      _parseLineScore(doc, homeShortest, awayShortest) ??
      _parseLineScore(doc, homeShortest.isNotEmpty ? homeShortest : homeShort, awayShortest.isNotEmpty ? awayShortest : awayShort) ??
      _parseLineScore(doc, '__home__', '__away__');
  if (line == null) return;
  await Postgres.execute(
    conn,
    '''
      UPDATE t_game_summary
      SET txt_scores_home = \$1,
          txt_scores_away = \$2,
          int_runs_home = \$3,
          int_runs_away = \$4,
          int_hit_home = \$5,
          int_hit_away = \$6,
          int_error_home = \$7,
          int_error_away = \$8
      WHERE id_game = \$9
    ''',
    data: [
      line.scoresHome,
      line.scoresAway,
      line.runsHome,
      line.runsAway,
      line.hitsHome,
      line.hitsAway,
      line.errorsHome,
      line.errorsAway,
      gameId,
    ],
  );
}

/// 出場成績ページのイニング得点表。未実施の回は空欄なので除き、カンマ区切りにする。
_LineScore? _parseLineScore(Document doc, String homeName, String awayName) {
  final table = doc.querySelector('#ing_brd');
  if (table == null) return null;
  final heads = table.querySelectorAll('thead th').map((cell) => cell.text.trim()).toList();
  final totalAt = heads.indexOf('計');
  if (totalAt < 2) return null;
  final lines = <({String name, List<String> innings, int runs, int hits, int errors})>[];
  for (final row in table.querySelectorAll('tbody tr')) {
    final cells = row.querySelectorAll('td').map((cell) => cell.text.trim()).toList();
    if (cells.length <= totalAt + 2) continue;
    final innings = <String>[];
    for (var i = 1; i < totalAt && i < cells.length; i++) {
      final text = cells[i].trim();
      final walkoff = RegExp(r'^(\d+)\s*[xX×]$').firstMatch(text);
      if (walkoff != null) {
        innings.add('${walkoff.group(1)}x');
        continue;
      }
      if (text == 'X' || text == 'x' || text == '×') {
        innings.add('X');
        continue;
      }
      final n = int.tryParse(text);
      innings.add(n != null ? '$n' : '0');
    }
    lines.add((
      name: cells.first,
      innings: innings,
      runs: int.tryParse(cells[totalAt]) ?? 0,
      hits: int.tryParse(cells[totalAt + 1]) ?? 0,
      errors: int.tryParse(cells[totalAt + 2]) ?? 0,
    ));
  }
  if (lines.length < 2) return null;

  var home = -1;
  var away = -1;
  for (var i = 0; i < lines.length; i++) {
    if (home < 0 && _sameTeamName(lines[i].name, homeName)) home = i;
    if (away < 0 && _sameTeamName(lines[i].name, awayName)) away = i;
  }
  if (home < 0 && away < 0) {
    away = 0;
    home = 1;
  } else if (home < 0) {
    home = away == 0 ? 1 : 0;
  } else if (away < 0) {
    away = home == 0 ? 1 : 0;
  }
  if (home == away) return null;

  final score = _LineScore();
  score.scoresHome = lines[home].innings.join(',');
  score.scoresAway = lines[away].innings.join(',');
  score.runsHome = lines[home].runs;
  score.runsAway = lines[away].runs;
  score.hitsHome = lines[home].hits;
  score.hitsAway = lines[away].hits;
  score.errorsHome = lines[home].errors;
  score.errorsAway = lines[away].errors;
  if (score.scoresHome.isEmpty && score.scoresAway.isEmpty) return null;
  return score;
}

/// 出場成績のイニング欄。チームIDと選手名（空白なし）をキーに、打席結果を打順で持つ。
Map<String, List<String>> _boxScorePlays(Document doc, int idTeamAway, int idTeamHome) {
  final plays = <String, List<String>>{};
  for (final group in batterStatsGroups(doc, idTeamAway, idTeamHome)) {
    var teamId = group.teamId;
    var switched = false;
    for (final row in group.rows) {
      if (row.querySelector('th') != null) {
        if (group.switchOnTh && !switched) {
          teamId = idTeamHome;
          switched = true;
        }
        continue;
      }
      final tds = row.querySelectorAll('td');
      if (tds.length < 2) continue;
      final name = StringTool.noSpace(tds[1].text);
      if (name.isEmpty) continue;
      final list = plays.putIfAbsent('$teamId|$name', () => <String>[]);
      for (final cell in row.querySelectorAll('td.bb-statsTable__data--inning')) {
        final details = cell.querySelectorAll('.bb-statsTable__dataDetail');
        if (details.isEmpty) {
          final text = cell.text.trim();
          if (text.isNotEmpty) list.add(text);
          continue;
        }
        for (final detail in details) {
          final text = detail.text.trim();
          if (text.isNotEmpty) list.add(text);
        }
      }
    }
  }
  return plays;
}

class _PlateDir {
  final String plateKey;
  final String result;
  String direction;
  final List<int> emptyIds;

  _PlateDir(this.result, this.direction, int id, bool empty, this.plateKey) : emptyIds = empty ? [id] : [];
}

bool _isBoxPlate(String result) {
  final r = Value.CodeGameResult;
  return result == r.HIT_SINGLE || result == r.HIT_DOUBLE || result == r.HIT_TRIPLE || result == r.HOME_RUN || result == r.OUT_FLY || result == r.OUT_GROUND || result == r.OUT_POP_UP || result == r.OUT_DOUBLE_PLAY || result == r.OUT_LINE_DRIVE || result == r.SACRIFICE_BUNT || result == r.SACRIFICE_FLY || result == r.SQUEEZE || result == r.STRIKE_OUT || result == r.WALK_BALL || result == r.WALK_DEAD || result == r.WALK_ERROR || result == r.ERROR_FIELDING || result == r.INTERFERENCE_BATTING || result == r.FIELDERS_CHOICE;
}

/// 出場成績の表記（左２、中安、二ゴロ）が、テキスト速報で付いた結果コードと同じ打席か。
bool _boxMatches(String cell, String result) {
  final text = cell.replaceAll(RegExp(r'\s+'), '');
  bool has(String token) => text.contains(token);
  final r = Value.CodeGameResult;
  if (result == r.HIT_DOUBLE) return has('２') || has('2');
  if (result == r.HIT_TRIPLE) return has('３') || has('3');
  if (result == r.HOME_RUN) return has('本');
  if (result == r.HIT_SINGLE) {
    return has('安') && !has('２') && !has('2') && !has('３') && !has('3') && !has('本');
  }
  if (result == r.OUT_POP_UP) return has('邪') || has('ポ');
  if (result == r.OUT_LINE_DRIVE) return has('直') || has('ライナー');
  if (result == r.OUT_GROUND || result == r.OUT_DOUBLE_PLAY) return has('ゴ') || has('併');
  if (result == r.SACRIFICE_FLY) return has('犠飛') || (has('飛') && has('犠'));
  if (result == r.OUT_FLY) return has('飛') && !has('邪') && !has('犠');
  if (result == r.STRIKE_OUT) return has('三振');
  if (result == r.WALK_BALL) return has('四球') || has('敬遠');
  if (result == r.WALK_DEAD) return has('死球');
  if (result == r.SACRIFICE_BUNT || result == r.SQUEEZE) return has('犠打') || has('バント');
  if (result == r.WALK_ERROR || result == r.ERROR_FIELDING) return has('失') || has('エラー');
  if (result == r.INTERFERENCE_BATTING) return has('打妨') || has('打撃妨害');
  if (result == r.FIELDERS_CHOICE) return has('野選');
  return false;
}

/// 左・中・右・一・二・三・遊・投・捕を code_direction_batting の値にする。方向が無い結果は空。
String _directionFromBox(String cell) {
  final text = cell.replaceAll(RegExp(r'\s+'), '');
  final p = Value.CodePosition;
  if (text.startsWith('左中')) return p.LF;
  if (text.startsWith('右中')) return p.RF;
  if (text.startsWith('左')) return p.LF;
  if (text.startsWith('中')) return p.CF;
  if (text.startsWith('右')) return p.RF;
  if (text.startsWith('遊')) return p.SS;
  if (text.startsWith('投')) return p.P;
  if (text.startsWith('捕')) return p.C;
  if (text.startsWith('一')) return p.FIRST;
  if (text.startsWith('二')) return p.SECOND;
  if (text.startsWith('三')) return p.THIRD;
  return '';
}

/// テキスト速報で打球方向が空の打席へ、出場成績の同じ打席の方向を書く。既にある方向は上書きしない。
Future<void> _fillMissingDirections(Connection conn, int idGame, Map<String, List<String>> boxPlays) async {
  final rows = await Postgres.execute(conn, AppSql.selectGameBatterPlays(), data: [idGame]);
  final groups = <String, List<_PlateDir>>{};
  for (final row in rows) {
    final map = row.toColumnMap();
    final result = '${map['code_result'] ?? ''}';
    if (!_isBoxPlate(result)) continue;
    final key = '${map['id_team']}|${StringTool.noSpace('${map['name_full'] ?? ''}')}';
    final id = _detailInt(map['id']);
    final direction = '${map['code_direction_batting'] ?? ''}'.trim();
    final plateKey = '${map['int_inning']}|${map['flg_bottom']}|${map['int_batting_order']}|${map['cnt_out']}|'
        '${map['flg_runner_first']}|${map['flg_runner_second']}|${map['flg_runner_third']}|$result';
    final list = groups.putIfAbsent(key, () => <_PlateDir>[]);
    if (list.isNotEmpty && list.last.plateKey == plateKey) {
      if (direction.isNotEmpty) {
        list.last.direction = direction;
      } else {
        list.last.emptyIds.add(id);
      }
    } else {
      list.add(_PlateDir(result, direction, id, direction.isEmpty, plateKey));
    }
  }

  var filled = 0;
  for (final entry in groups.entries) {
    final box = boxPlays[entry.key];
    if (box == null || box.isEmpty) continue;
    final live = entry.value;
    var bi = 0;
    for (var i = 0; i < live.length; i++) {
      final plate = live[i];
      if (bi >= box.length) break;
      var matched = -1;
      if (_boxMatches(box[bi], plate.result)) {
        matched = bi;
      } else if (bi + 1 < box.length && _boxMatches(box[bi + 1], plate.result) && (i + 1 >= live.length || !_boxMatches(box[bi], live[i + 1].result))) {
        matched = bi + 1;
      } else if (i + 1 < live.length && _boxMatches(box[bi], live[i + 1].result)) {
        continue;
      } else {
        continue;
      }
      bi = matched + 1;
      final fromBox = _directionFromBox(box[matched]);
      final use = plate.direction.isNotEmpty ? plate.direction : fromBox;
      if (use.isEmpty) continue;
      for (final id in plate.emptyIds) {
        await Postgres.execute(conn, AppSql.updateGameDetailDirection(), data: [id, use]);
        filled++;
      }
    }
  }
  if (filled > 0) {
    print('出場成績から打球方向を$filled件補いました。');
  }
}

class _StoredDetail {
  final int id;
  final int inning;
  final bool bottom;
  final int order;
  final int batter;
  final int outs;
  final bool runnerFirst;
  final bool runnerSecond;
  final bool runnerThird;
  final int runs;
  final String result;
  final int enter;

  _StoredDetail({
    required this.id,
    required this.inning,
    required this.bottom,
    required this.order,
    required this.batter,
    required this.outs,
    required this.runnerFirst,
    required this.runnerSecond,
    required this.runnerThird,
    required this.runs,
    required this.result,
    required this.enter,
  });
}

class _StoredPlate {
  final int inning;
  final bool bottom;
  final int order;
  final int batter;
  final int outs;
  final bool runnerFirst;
  final bool runnerSecond;
  final bool runnerThird;
  final int firstId;
  final List<String> results = [];

  _StoredPlate(_StoredDetail row)
      : inning = row.inning,
        bottom = row.bottom,
        order = row.order,
        batter = row.batter,
        outs = row.outs,
        runnerFirst = row.runnerFirst,
        runnerSecond = row.runnerSecond,
        runnerThird = row.runnerThird,
        firstId = row.id {
    results.add(row.result);
  }

  bool sameSituation(_StoredDetail row) {
    return inning == row.inning && bottom == row.bottom && order == row.order && batter == row.batter && outs == row.outs && runnerFirst == row.runnerFirst && runnerSecond == row.runnerSecond && runnerThird == row.runnerThird;
  }
}

class _RosterName {
  final int id;
  final int teamId;
  final String name;
  final String nameLast;
  String initial;

  _RosterName(this.id, this.teamId, this.name, [this.nameLast = '', this.initial = '']);
}

Future<void> _persistPlayerInitial(Connection conn, int playerId, String initial) async {
  final value = initial.trim().toUpperCase();
  if (playerId <= 0 || value.isEmpty) return;
  try {
    await conn.execute(
      '''
        UPDATE m_player
        SET name_first_initial = \$1::text,
            updat = NOW()
        WHERE id = \$2::int
          AND COALESCE(BTRIM(name_first_initial), '') = ''
      ''',
      parameters: [value, playerId],
    );
  } catch (e) {
    print('name_first_initial 更新スキップ (player=$playerId): $e');
  }
}

class CareerClub {
  final int id;
  final int league;
  final String shortName;
  final String fullName;
  final String url;

  CareerClub({
    required this.id,
    required this.league,
    required this.shortName,
    required this.fullName,
    this.url = '',
  });
}

class NpbCareerPage {
  List<m_player_career> rows = [];
  bool hasMlb = false;
  bool hasStatsTable = false;
  bool isRookie = false;
}

class _RosterDetail {
  final m_player player;
  final String url;
  _RosterDetail(this.player, this.url);
}
