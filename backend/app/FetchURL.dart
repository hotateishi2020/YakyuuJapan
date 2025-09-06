import 'package:http/http.dart' as http;

import 'package:html/parser.dart' show parse;
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'AppSql.dart';
import '../tools/Postgres.dart';
import '../tools/StringTool.dart';
import '../tools/DateTimeTool.dart';
import 'DB/m_player.dart';
import 'DB/t_stats_player.dart';
import 'DB/t_game.dart';
import 'DB/m_stadium.dart';
import 'DB/t_stats_team.dart';
import 'package:intl/intl.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

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
          team.year = DateTimeTool.getThisYear();
          team.id_team = r_team.first.toColumnMap()['id'];
          team.int_rank = int.tryParse(cells[0].text.trim()) ?? 0;
          team.int_game = int.tryParse(cells[2].text.trim()) ?? 0;
          team.int_win = int.tryParse(cells[3].text.trim()) ?? 0;
          team.int_lose = int.tryParse(cells[4].text.trim()) ?? 0;
          team.int_draw = int.tryParse(cells[5].text.trim()) ?? 0;
          team.game_behind = cells[7].text.trim();
          team.int_rbi = int.tryParse(cells[9].text.trim()) ?? 0;
          team.int_homerun = int.tryParse(cells[11].text.trim()) ?? 0;
          team.int_sh = int.tryParse(cells[12].text.trim()) ?? 0;
          team.num_avg_batting = double.tryParse("0" + cells[13].text.trim()) ?? 0;
          team.num_era_total = double.tryParse(cells[14].text.trim()) ?? 0;
          teams.add(team);
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
      final url_pitching = Uri.parse(urls_pitching[i]);
      final res_pitching = await http.get(url_pitching);

      if (res_pitching.statusCode != 200) {
        throw Exception('Failed to fetch standings');
      }

      final htmlPitching = _decodeHtml(res_pitching);
      final document = parse(htmlPitching);
      final divs = document.querySelectorAll('body div.container div.main div.table-responsive');
      final rows = divs[2].querySelectorAll('table tbody tr');

      for (final tr in rows) {
        final ths = tr.querySelectorAll('th');
        final tds = tr.querySelectorAll('td');
        if (ths.isEmpty || tds.length < 3) {
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
        var r_team = await Postgres.execute(conn, AppSql.selectTeamsWhereNameShortest(), data: [team_name]);
        if (r_team.isEmpty) {
          // チーム名が一致しないケースはスキップ
          print('データが見つかりませんでした。');
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
        if (cnt < 2) {
          cnt++;
          continue;
        }

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
          print('データが見つかりませんでした。');
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
    list_date.add(DateTime.now()); //今日
    list_date.add(DateTime.now().add(const Duration(days: 1))); //明日

    for (var date in list_date) {
      print(date.toString() + "の試合を取得します。");
      var urlString = 'https://baseball.yahoo.co.jp/npb/schedule/?date=';
      final formatter = DateFormat('yyyy-MM-dd');
      final formatted = formatter.format(date);
      final url = Uri.parse(urlString + formatted);
      final res = await http.get(url);

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

            try {
              if (card.querySelectorAll('a').isEmpty) {
                continue;
              }
              var url_href = card.querySelectorAll('a')[0].attributes['href']?.trim() ?? '';

              var url_detail = url.resolve(url_href.replaceFirst('index', 'top'));

              final res_detail = await http.get(url_detail);

              if (res_detail.statusCode != 200) {
                throw Exception('Failed to fetch standings');
              }

              final doc_detail = parse(_decodeHtml(res_detail));
              final match = doc_detail.querySelectorAll('#gm_brd')[0].querySelectorAll('div')[0];
              final name_stadium = match.querySelectorAll('div')[0].querySelectorAll('p')[0].nodes.last.text!.replaceAll(RegExp(r'\s+'), '');
              final time_gamestart = match.querySelectorAll('div')[0].querySelectorAll('p')[0].querySelectorAll('time')[0].text.trim();
              final gamestart = formatted + " " + time_gamestart + ":00";
              datetime_gamestart = DateTime.tryParse(gamestart)!;
              final team_home = match.querySelectorAll('#async-gameDetail')[0].querySelectorAll('div')[0].querySelectorAll('p a')[0].text.trim();
              final team_away = match.querySelectorAll('#async-gameDetail')[0].querySelectorAll('div')[2].querySelectorAll('p a')[0].text.trim();

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

                  var result = player.querySelectorAll('th')[0].text?.trim() ?? '';
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
              } catch (e, stacktrace) {
                print('試合が終了していないので活躍選手を取得できませんでした。');
              }

              final result_team_home = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [team_home]);

              id_team_home = result_team_home.first.toColumnMap()['id'];

              final results_team_away = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [team_away]);

              id_team_away = results_team_away.first.toColumnMap()['id'];

              if (flg_no_pitcher == false) {
                //先発投手が発表されている場合
                final result_pitcher_home = await conn.execute(AppSql.selectPlayerWhereFullNameAndTeamID(), parameters: [StringTool.noSpace(pitcher_home), id_team_home]);
                id_pitcher_home = result_pitcher_home.first.toColumnMap()['id'];

                final result_pitcher_away = await conn.execute(AppSql.selectPlayerWhereFullNameAndTeamID(), parameters: [StringTool.noSpace(pitcher_away), id_team_away]);
                id_pitcher_away = result_pitcher_away.first.toColumnMap()['id'];
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

            // print(game.toMap());
            print('');

            if (result_game.isEmpty) {
              //DBに同じ日付、同じ組み合わせの試合が登録されていない場合、新規登録する
              await Postgres.insert(conn, game);
            } else {
              //DBに同じ日付、同じ組み合わせの試合が登録されている場合は更新する
              game.id = result_game.first.toColumnMap()['id'];
              await Postgres.update(conn, game);
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

  static Future<void> fetchNPBPlayers(Connection conn) async {
    final results = await conn.execute(AppSql.selectTeams());
    final teams = results
        .map((row) => {
              'id': row[0],
              'url': row[1],
            })
        .toList();

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

        await Postgres.insert(conn, player);
      }
    }
  }

  static Future<Response> fetchStatsPlayerNPB(Connection conn) async {
    // 前回のデータを削除
    await conn.execute(AppSql.deleteStatsPlayer(), parameters: [DateTimeTool.getThisYear()]);

    final results = await conn.execute(AppSql.selectStatsDetails());
    final stats = results
        .map((row) => {
              'id_stats': row[0],
              'id_league': row[1],
              'url': row[2],
              'int_idx_col': row[3],
            })
        .toList();

    for (final stat in stats) {
      print(1);
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
        print(2);
        final tds = tr.querySelectorAll('td');
        if (tds.isEmpty) continue;

        final cols = tds.map((td) => td.text.trim()).toList();

        t_stats_player statsPlayer = t_stats_player();
        statsPlayer.id_league = stat['id_league'] as int;
        statsPlayer.id_stats = stat['id_stats'] as int;
        statsPlayer.stats = double.tryParse(cols[stat['int_idx_col'] as int]) ?? 0;
        statsPlayer.int_rank = int.tryParse(cols[0]) ?? 0;
        statsPlayer.playerName = cols[1].split(RegExp(r'[\s　]+'))[0];
        statsPlayer.teamName = cols[1].split(RegExp(r'[\s　]+'))[1].replaceAll("(", "").replaceAll(")", "");
        listStats.add(statsPlayer);
      }
      var sql = AppSql.selectInsertStatsPlayer(listStats);
      print(sql);
      var cnt_rows = await Postgres.execute(conn, sql);
      print("実行行数" + cnt_rows.toString());
    } //for stat
    return Response.ok('ok');
  }
}
