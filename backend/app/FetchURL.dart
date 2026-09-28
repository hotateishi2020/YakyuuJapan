import 'package:http/http.dart' as http;

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'AppSql.dart';
import '../tools/Postgres.dart';
import '../tools/StringTool.dart';
import '../tools/DateTimeTool.dart';
import '../tools/DBModel.dart';
import 'DB/m_player.dart';
import 'DB/t_game_details.dart';
import 'DB/t_game_summary.dart';
import 'DB/t_stats_player.dart';
import 'DB/t_stats_player_latest.dart';
import 'DB/t_game.dart';
import 'DB/m_stadium.dart';
import 'DB/t_stats_team.dart';
import 'package:intl/intl.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'Value.dart';

class FetchURL {
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
      var cnt = 0;

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

  static Future<Response> fetchGamesNPB(Connection conn) async {
    var list_date = [];
    var now = DateTime.now();
    list_date.add(now); //今日
    list_date.add(now.add(const Duration(days: 1))); //明日

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

      final result = <Map<String, dynamic>>[];

      try {
        final document = parse(_decodeHtml(res));
        final leagues = document.querySelectorAll('#gm_card')[0].querySelectorAll('section');

        var cnt = 0;

        for (var league in leagues) {
          DateTime datetime_gamestart = DateTime.now();

          var cards = league.querySelectorAll('ul')[0].querySelectorAll('li');

          for (var card in cards) {
            var id_stadium = 0;
            var id_team_home = 0;
            var id_team_away = 0;
            var id_pitcher_home = 0;
            var id_pitcher_away = 0;
            var score_home = -1;
            var score_away = -1;
            var match_state = '';
            var id_pitcher_win = 0;
            var id_pitcher_lose = 0;
            var id_pitcher_save = 0;
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
              final match = doc_detail.querySelectorAll('#gm_brd')[0];
              final name_stadium = match.querySelectorAll('div')[0].querySelectorAll('p')[0].nodes.last.text!.replaceAll(RegExp(r'\s+'), '');
              final time_gamestart = match.querySelectorAll('div')[0].querySelectorAll('p')[0].querySelectorAll('time')[0].text.trim();
              final gamestart = formatted + " " + time_gamestart + ":00";
              datetime_gamestart = DateTime.tryParse(gamestart)!;

              final a = match.querySelectorAll('#async-gameDetail')[0];
              final b = a..querySelectorAll('div')[0];
              final c = b.querySelectorAll('a')[0];
              final d = c.querySelectorAll('span')[1];
              print(d.text.trim());
              final team_home = match.querySelectorAll('#async-gameDetail')[0].querySelectorAll('div')[0].querySelectorAll('a')[0].querySelectorAll('span')[1].text.trim();
              final team_away = match.querySelectorAll('#async-gameDetail')[0].querySelectorAll('div')[2].querySelectorAll('a')[0].querySelectorAll('span')[1].text.trim();

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

                  var name_team = name_team_block[0].text?.trim() ?? '';

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
                  final id_player_result = result_player.first.toColumnMap()['id'];

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

              final results_team_away = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [team_away]);

              id_team_away = results_team_away.first.toColumnMap()['id'];

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

            if (result_game.isEmpty) {
              //DBに同じ日付、同じ組み合わせの試合が登録されていない場合、新規登録する
              await Postgres.insert(conn, game);
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
                    throw Exception('試合が開始していないので試合結果のHTMLが存在しません。');
                  }

                  for (var game_summary_pitcher_row in game_summary_pitcher) {
                    var code_result_pitcher = game_summary_pitcher_row.querySelectorAll('td')[0].text.trim();
                    var idx_minus = 0;
                    print("code_result_pitcher:" + code_result_pitcher.length.toString());
                    if (code_result_pitcher.length >= 2) {
                      idx_minus = -1;
                    }
                    var txt_pitcher = game_summary_pitcher_row.querySelectorAll('td')[1 + idx_minus].text.trim();
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
                    } else if (code_result_pitcher.contains('Ｓ')) {
                      game_summary_pitcher.code_result_pitcher = Value.CodeGameResultPitcher.SAVE;
                    } else if (code_result_pitcher.contains('H')) {
                      game_summary_pitcher.code_result_pitcher = Value.CodeGameResultPitcher.HOLD;
                    }

                    game_summary_pitcher.id_game = game.id;
                    game_summary_pitcher.id_player = id_player_result;
                    game_summary_pitcher.double_inning_pitch = double.tryParse(game_summary_pitcher_row.querySelectorAll('td')[3 + idx_minus].text.trim()) ?? 0.0;
                    game_summary_pitcher.int_pitch = int.tryParse(game_summary_pitcher_row.querySelectorAll('td')[4 + idx_minus].text.trim()) ?? 0;
                    game_summary_pitcher.int_hit = int.tryParse(game_summary_pitcher_row.querySelectorAll('td')[6 + idx_minus].text.trim()) ?? 0;
                    game_summary_pitcher.int_strike_out = int.tryParse(game_summary_pitcher_row.querySelectorAll('td')[8 + idx_minus].text.trim()) ?? 0;
                    game_summary_pitcher.int_four = int.tryParse(game_summary_pitcher_row.querySelectorAll('td')[9 + idx_minus].text.trim()) ?? 0;
                    game_summary_pitcher.int_dead_pitching = int.tryParse(game_summary_pitcher_row.querySelectorAll('td')[10 + idx_minus].text.trim()) ?? 0;
                    game_summary_pitcher.int_balk = int.tryParse(game_summary_pitcher_row.querySelectorAll('td')[11 + idx_minus].text.trim()) ?? 0;
                    game_summary_pitcher.int_runs = int.tryParse(game_summary_pitcher_row.querySelectorAll('td')[12 + idx_minus].text.trim()) ?? 0;
                    game_summary_pitcher.int_runs_earned = int.tryParse(game_summary_pitcher_row.querySelectorAll('td')[13 + idx_minus].text.trim()) ?? 0;

                    list_game_summary.add(game_summary_pitcher);
                    // print(game_summary_pitcher.toMap());
                  } //for row
                  id_team_pitcher = id_team_home;
                } //for sections

                await Postgres.execute(conn, AppSql.deleteGameSummary(), data: [game.id]);
                await Postgres.insertMulti(conn, list_game_summary);
                print('打席結果を登録しました。');
                // if (idx_col < 14) {
                //   idx_col++;
                //   continue;
                // }
                // var txt_result = game_summary_away_row.querySelectorAll('td')[idx_col].text.trim();
                // if (txt_result.isEmpty) {
                //   continue;
                // }
                // if (txt_result.contains('安')) {

                // } else if (txt_result.contains('2')) {

                // } else if (txt_result.contains('3')) {

                // } else if (txt_result.contains('本')) {

                // } else if (txt_result.contains('走塁妨害')) {

                // } else if (txt_result.contains('打撃妨害')) {

                // } else if (txt_result.contains('捕逸')) {

                // } else if (txt_result.contains('暴投')) {

                // } else if (txt_result.contains('守備変更')) {

                // } else if (txt_result.contains('代打')) {

                // } else if (txt_result.contains('代走')) {

                // } else if (txt_result.contains('代守')) {

                // } else if (txt_result.contains('守備変更')) {

                // } else if (txt_result.contains('代打')) {

                // }
                // }
                // var url_text = url.resolve(url_href.replaceFirst('index', 'text'));
                // final res_text = await http.get(url_text);
                // if (res_text.statusCode != 200) {
                //   throw Exception('Failed to fetch standings');
                // }
                // final doc_text = parse(_decodeHtml(res_text));
                // var results_batting = doc_text.querySelectorAll('#text_live section');
                // if (results_batting.isEmpty) {
                //   throw Exception('試合が開始していないので打席結果のHTMLが存在しません。');
                // }
                // var cnt_inning = 0;
                // var flg_bottom = false;
                // var list_result_batting = [];
                // var int_score_home = 0;
                // var int_score_away = 0;
                // var id_pitcher_home_temp = id_pitcher_home;
                // var id_pitcher_away_temp = id_pitcher_away;
                // var id_team_batting = id_team_away;

                // for (var ret_bat in results_batting) {
                //   //一行目はスキップ
                //   if (cnt_inning < 1) {
                //     cnt_inning++;
                //     continue;
                //   }

                //   var lines = ret_bat.querySelectorAll('li');
                //   if (lines.isEmpty) {
                //     continue;
                //   }
                //   for (var line in lines) {
                //     var batting_order = line.querySelectorAll('span.bb-liveText__order')[0].text.trim();
                //     var player_name = line.querySelectorAll('a.bb-liveText__player')[0].text.trim();
                //     var base_state = line.querySelectorAll('span.bb-liveText__state')[0].text.trim();
                //     var summaries = line.querySelectorAll('p.bb-liveText__summary');

                //     var game_details = t_game_details();
                //     game_details.id_game = game.id;
                //     game_details.int_inning = cnt_inning;
                //     game_details.flg_bottom = flg_bottom;
                //     game_details.int_score_home = int_score_home;
                //     game_details.int_score_away = int_score_away;
                //     if (flg_bottom == true) {
                //       game_details.id_pitcher = id_pitcher_away_temp;
                //     } else {
                //       game_details.id_pitcher = id_pitcher_home_temp;
                //     }
                //     //取得した選手名から選手IDをDBから取得
                //     final result_player = await Postgres.execute(conn, AppSql.selectPlayerWhereFullNameAndTeamID(), data: [StringTool.noSpace(player_name), id_team_home]);
                //     game_details.id_batter = result_player.first.toColumnMap()['id'];
                //     game_details.int_batting_order = int.tryParse(batting_order.replaceAll('番', '')) ?? 0;

                //     //base_stateからcnt_outをセット
                //     //2文字目までと3文字目以降で文字を切り分ける
                //     var str_out = base_state.substring(0, 2);
                //     var str_base = base_state.substring(2);

                //     //str_outの文字列が無を含んでいたら0, 一を含んでいたら1, 二を含んでいたら2, 三を含んでいたら3
                //     if (str_out.contains('無')) {
                //       game_details.cnt_out = 0;
                //     } else if (str_out.contains('一')) {
                //       game_details.cnt_out = 1;
                //     } else if (str_out.contains('二')) {
                //       game_details.cnt_out = 2;
                //     } else if (str_out.contains('三')) {
                //       game_details.cnt_out = 3;
                //     }
                //     //str_baseの文字列が無を含んでいたら0, 一を含んでいたら1, 二を含んでいたら2, 三を含んでいたら3
                //     if (str_base.contains('一')) {
                //       game_details.flg_runner_first = true;
                //     }
                //     if (str_base.contains('二')) {
                //       game_details.flg_runner_second = true;
                //     }
                //     if (str_base.contains('三')) {
                //       game_details.flg_runner_third = true;
                //     }

                //     var flg_player_change = false;
                //     for (var s in summaries) {
                //       var summary_spans = s.querySelectorAll('span');

                //       if (summary_spans.isNotEmpty) {
                //         //summaryからcode_categoryとcode_resultをセット
                //         var summary_span = summary_spans[0].text.trim();
                //         if (summary_span.contains('安打')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.HIT_SINGLE;
                //           game_details.double_contribution = 1;
                //         } else if (summary_span.contains('二塁打')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.HIT_DOUBLE;
                //           game_details.double_contribution = 2;
                //         } else if (summary_span.contains('三塁打') || summary_span.contains('スリーベース')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.HIT_TRIPLE;
                //           game_details.double_contribution = 3;
                //         } else if (summary_span.contains('本塁打')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.HOME_RUN;
                //           game_details.double_contribution = 4;
                //         } else if (summary_span.contains('四球') || summary_span.contains('フォアボール')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.WALK_BALL;
                //           game_details.double_contribution = 0.8;
                //         } else if (summary_span.contains('死球')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.WALK_DEAD;
                //           game_details.double_contribution = 0.2;
                //         } else if (summary_span.contains('ゴロ')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.OUT_GROUND;
                //           game_details.double_contribution = 0.1;
                //         } else if (summary_span.contains('ダブルプレー')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.OUT_DOUBLE_PLAY;
                //           game_details.double_contribution = -1;
                //         } else if (summary_span.contains('犠打')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.SACRIFICE_BUNT;
                //           game_details.double_contribution = 0.5;
                //         } else if (summary_span.contains('犠飛') || summary_span.contains('犠牲フライ')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.SACRIFICE_FLY;
                //           game_details.double_contribution = 0.5;
                //         } else if (summary_span.contains('フライ')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.OUT_FLY;
                //           game_details.double_contribution = 0.1;
                //         } else if (summary_span.contains('三振')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.STRIKE_OUT;
                //           game_details.double_contribution = 0;
                //         } else if (summary_span.contains('盗塁')) {
                //           game_details.code_category = Value.CodeGameResultCategory.RUNNING_BASE;
                //           game_details.code_result = Value.CodeGameResult.STEAL_BASE_SAFE;
                //           game_details.double_contribution = 1;
                //         } else if (summary_span.contains('盗塁死')) {
                //           game_details.code_category = Value.CodeGameResultCategory.RUNNING_BASE;
                //           game_details.code_result = Value.CodeGameResult.STEAL_BASE_OUT;
                //           game_details.double_contribution = 0;
                //         } else if (summary_span.contains('走塁死')) {
                //           game_details.code_category = Value.CodeGameResultCategory.RUNNING_BASE;
                //           game_details.code_result = Value.CodeGameResult.RUN_DEAD;
                //           game_details.double_contribution = 0;
                //         } else if (summary_span.contains('捕逸')) {
                //           game_details.code_category = Value.CodeGameResultCategory.ERROR;
                //           game_details.code_result = Value.CodeGameResult.PASS_BALL;
                //           game_details.double_contribution = 0;
                //         } else if (summary_span.contains('暴投')) {
                //           game_details.code_category = Value.CodeGameResultCategory.ERROR;
                //           game_details.code_result = Value.CodeGameResult.WILD_PITCH;
                //           game_details.double_contribution = 0;
                //         } else if (summary_span.contains('守備妨害')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.INTERFERENCE_FIELDING;
                //           game_details.double_contribution = 0;
                //         } else if (summary_span.contains('走塁妨害')) {
                //           game_details.code_category = Value.CodeGameResultCategory.ERROR;
                //           game_details.code_result = Value.CodeGameResult.INTERFERENCE_RUNNING;
                //           game_details.double_contribution = 0;
                //         } else if (summary_span.contains('打撃妨害')) {
                //           game_details.code_category = Value.CodeGameResultCategory.ERROR;
                //           game_details.code_result = Value.CodeGameResult.INTERFERENCE_BATTING;
                //           game_details.double_contribution = 0;
                //         } else if (summary_span.contains('失策') || summary_span.contains('エラー') || summary_span.contains('落球')) {
                //           game_details.code_category = Value.CodeGameResultCategory.BATTING;
                //           game_details.code_result = Value.CodeGameResult.ERROR_FIELDING;
                //           game_details.double_contribution = 0;
                //         } else if (summary_span.contains('代打')) {
                //           game_details.code_category = Value.CodeGameResultCategory.CHANGE_PLAYER;
                //           game_details.code_result = Value.CodeGameResult.PINCH_HITTER;
                //           flg_player_change = true;
                //         } else if (summary_span.contains('代走')) {
                //           game_details.code_category = Value.CodeGameResultCategory.CHANGE_PLAYER;
                //           game_details.code_result = Value.CodeGameResult.PINCH_RUNNER;
                //           flg_player_change = true;
                //         } else if (summary_span.contains('代守')) {
                //           game_details.code_category = Value.CodeGameResultCategory.CHANGE_PLAYER;
                //           game_details.code_result = Value.CodeGameResult.PINCH_FIELDER;
                //           flg_player_change = true;
                //         } else if (summary_span.contains('守備変更')) {
                //           game_details.code_category = Value.CodeGameResultCategory.CHANGE_POSITION;
                //           game_details.code_result = Value.CodeGameResult.CHANGE_POSITION;
                //           flg_player_change = true;
                //         } else if (summary_span.contains('投手交代')) {
                //           game_details.code_category = Value.CodeGameResultCategory.CHANGE_PLAYER;
                //           game_details.code_result = Value.CodeGameResult.CHANGE_PITCHER;
                //           flg_player_change = true;
                //         } else if (summary_span.contains('→')) {}
                //       } // if summary_spans.isNotEmpty

                //       if (flg_player_change == true) {
                //         var flg_arrow = false;
                //         if (summary_spans.length > 1) {
                //           //文言でピッチャー交代を表すパターン
                //         } else {
                //           //矢印でピッチャー交代を表すパターン
                //         }
                //         var summary_anchors = s.querySelectorAll('a');

                //         if (summary_anchors.isNotEmpty) {
                //           var flg_enter = false;
                //           for (var summary_a in summary_anchors) {
                //             var player_name = summary_a.text.trim();
                //             //選手名とチームIDを使って選手IDを取得
                //             final result_player = await Postgres.execute(conn, AppSql.selectPlayerWhereFullNameAndTeamID(), data: [StringTool.noSpace(player_name), id_team_batting]);
                //             if (flg_enter == false) {
                //               game_details.id_player_exit = result_player.first.toColumnMap()['id'];
                //               flg_enter = true;
                //             } else {
                //               game_details.id_player_enter = result_player.first.toColumnMap()['id'];
                //             }
                //           }
                //         }
                //       }
                //     } //for summaries
                //     list_result_batting.add(game_details);
                //   } //for battingline
                // } //for inning
              } catch (e, stacktrace) {
                print('打席結果のスクレイピングに失敗しました。');
                print(stacktrace);
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
    } //for 今日・明日
    return Response.ok('ok');
  }

  static Future<Response> fetchNPBPlayers(Connection conn) async {
    final results = await conn.execute(AppSql.selectTeams());
    final teams = results
        .map((row) => {
              'id': row[0],
              'url': row[1],
            })
        .toList();

    List<m_player> players = [];

    for (final team in teams) {
      final url = team['url'] as String;
      final res = await http.get(Uri.parse(url));
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

        player.date_birth = DateTime.tryParse(cols[2]); // 失敗時は null を保持
        player.uniform_number = cols[0];
        player.name_middle = '';
        player.name_full = player.name_last + player.name_first;
        player.height = int.tryParse(cols[3]) ?? 0;
        player.weight = int.tryParse(cols[4]) ?? 0;
        player.id_team = team['id'] as int;

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
      }
    }

    var cnt_rows = await Postgres.execute(conn, AppSql.selectInsertNewPlayersNPB(players));

    print("登録した新選手の数：${cnt_rows.affectedRows.toString()}");
    return Response.ok('ok');
  }

  static Future<Response> fetchStatsPlayerNPB(Connection conn) async {
    // t_stats_player は履歴用に削除せず INSERT のみ。
    // t_stats_player_latest のみ同内容で deleteInsert する。
    final results = await conn.execute(AppSql.selectStatsDetails());
    final stats = Postgres.toMap(results);

    for (final stat in stats) {
      print('statsID:' + stat['id_stats'].toString());
      final url = stat['url'] as String;
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }

      final doc = parse(_decodeHtml(res));
      final tables = doc.querySelectorAll('#js-playerTable');
      if (tables.isEmpty) {
        throw Exception('テーブルが見つかりませんでした');
      }

      final table = tables.first;
      List<t_stats_player> listStats = [];

      for (final tr in table.querySelectorAll('tr')) {
        final tds = tr.querySelectorAll('td');
        if (tds.isEmpty) continue;

        final cols = tds.map((td) => td.text.trim()).toList();

        //同じ球団内に同じ名字の選手が複数在籍していないかチェックする
        final name_team_home = cols[1].split(RegExp(r'[\s　]+'))[1].replaceAll("(", "").replaceAll(")", "");
        var name_player = cols[1].split(RegExp(r'[\s　]+'))[0];
        final result_player = await Postgres.execute(conn, AppSql.selectPlayerWhereFullNameAndTeamIDLike(), data: [StringTool.noSpace(name_player), name_team_home]);

        if (result_player.length > 1) {
          //一つの球団に同じ名字の選手が複数人在籍している場合、さらに選手ページをクリックしてフルネームを取得する
          final url_player = 'https://baseball.yahoo.co.jp/' + (tds[1].querySelectorAll('a')[0].attributes['href']?.trim() ?? '');
          final res_player = await http.get(Uri.parse(url_player));
          if (res_player.statusCode != 200) {
            throw Exception('HTTP ${res_player.statusCode}');
          }
          final doc_player = parse(_decodeHtml(res_player));
          name_player = doc_player.querySelectorAll('ruby.bb-profile__ruby')[0].text.split('（')[0].trim();
        }

        t_stats_player statsPlayer = t_stats_player();
        statsPlayer.id_league = stat['id_league'] as int;
        statsPlayer.id_stats = stat['id_stats'] as int;
        statsPlayer.stats = double.tryParse(cols[stat['int_idx_col'] as int]) ?? 0;
        statsPlayer.int_rank = int.tryParse(cols[0]) ?? 0;
        statsPlayer.playerName = StringTool.noSpace(name_player);
        statsPlayer.teamName = cols[1].split(RegExp(r'[\s　]+'))[1].replaceAll("(", "").replaceAll(")", "");
        listStats.add(statsPlayer);
      } //for選手

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

    if (stats_player_map.isNotEmpty) {
      print(stats_player_map);

      for (final stats_player in stats_player_map) {
        print(stats_player);
        var url = stats_player['url'] as String;

        final res = await http.get(Uri.parse(url));
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }

        final doc = parse(_decodeHtml(res));
        final rows = doc.querySelectorAll('#js-tabDom01 table.bb-playerStatsTable tbody tr');
        if (rows.isEmpty) {
          throw Exception('ランク外選手の詳細が記載されたテーブルが見つかりませんでした');
        }

        var idx_col = stats_player['int_idx_col_details'] as int;
        var idx_row = stats_player['int_idx_row_details'] as int;

        t_stats_player statsPlayer = t_stats_player();
        statsPlayer.id_player = stats_player['id_player'] as int;
        statsPlayer.id_team = stats_player['id_team'] as int;
        statsPlayer.id_league = stats_player['id_league'] as int;
        statsPlayer.id_stats = stats_player['id_stats'] as int;
        statsPlayer.stats = double.tryParse(rows[idx_row].querySelectorAll('td')[idx_col].text.trim()) ?? 0;
        statsPlayer.int_rank = 1000;
        statsPlayer.playerName = stats_player['name_full'] as String;
        statsPlayer.teamName = stats_player['name_shortest'] as String;
        if (stats_player['flg_pitcher'] as bool) {
          //投手の場合は投球回のセルから数値をスクレイピング（例: 12.1 → 12）
          final rawIp = rows[idx_row].querySelectorAll('td')[14].text.trim();
          statsPlayer.cnt_play = double.tryParse(rawIp)?.truncate() ?? int.tryParse(rawIp) ?? 0;
        } else {
          //野手の場合は打席数のセルから数値をスクレイピング
          final rawPa = rows[idx_row].querySelectorAll('td')[2].text.trim();
          statsPlayer.cnt_play = double.tryParse(rawPa)?.truncate() ?? int.tryParse(rawPa) ?? 0;
        }
        if (statsPlayer.cnt_play == 0) {
          print('☠️打席数または投球回をスクレイピングできませんでした。☠️');
        }
        print(statsPlayer.toMap());
        listStatsPlayerNoRank.add(statsPlayer);
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
}
