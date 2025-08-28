import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'dart:convert';
import 'AppSql.dart';
import 'Postgres.dart';
import 'StringTool.dart';
import '../DB/m_player.dart';
import '../DB/t_stats_player.dart';
import '../DB/t_game.dart';
import '../DB/m_stadium.dart';
import 'package:intl/intl.dart';
import 'package:postgres/postgres.dart';

class FetchURL {
  static Future<List<Map<String, dynamic>>> fetchNPBStandings() async {
    final url = Uri.parse('https://baseball.yahoo.co.jp/npb/standings/');
    final res = await http.get(url);

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch standings');
    }

    final document = parse(res.body);
    final cards = document.querySelectorAll('table.bb-rankTable');
    final result = <Map<String, dynamic>>[];
    var cnt = 0;

    for (final card in cards) {
      final teams = <Map<String, String>>[];
      final rows = card.querySelectorAll('tbody tr');

      if (cnt == 2) {
        break;
      }

      for (final row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.length >= 3) {
          teams.add({
            'rank': cells[0].text.trim(),
            'team': cells[1].text.trim(),
            'win_loss': cells[2].text.trim(),
          });
        }
      }
      result.add({
        'league': cnt == 0 ? 'セ・リーグ' : 'パ・リーグ',
        'teams': teams,
      });
      cnt++;
    }
    return result;
  }

  static Future<List<Map<String, dynamic>>> fetchTodayPitcherNPB(
      Connection conn) async {
    var urlString = 'https://baseball.yahoo.co.jp/npb/schedule/?date=';
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd');
    final formatted = formatter.format(now);
    final url = Uri.parse(urlString + formatted);
    final res = await http.get(url);

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch standings');
    }

    final document = parse(res.body);
    final leagues =
        document.querySelectorAll('#gm_card')[0].querySelectorAll('section');

    final result = <Map<String, dynamic>>[];
    var cnt = 0;

    await Postgres.transactionCommit(conn, () async {
      for (var league in leagues) {
        print(league);

        var id_stadium = 0;
        var id_team_home = 0;
        var id_team_away = 0;
        var id_pitcher_home = 0;
        var id_pitcher_away = 0;
        var score_home = -1;
        var score_away = -1;
        DateTime datetime_gamestart = DateTime.now();

        var cards = league.querySelectorAll('ul')[0].querySelectorAll('li');
        print(cards.length);
        for (var card in cards) {
          try {
            print(card);
            print(card.querySelectorAll('a').length);
            if (card.querySelectorAll('a').isEmpty) {
              continue;
            }
            var url_href =
                card.querySelectorAll('a')[0].attributes['href']?.trim() ?? '';
            var url_detail = url.resolve(url_href.replaceFirst('index', 'top'));

            final res_detail = await http.get(url_detail);

            if (res_detail.statusCode != 200) {
              throw Exception('Failed to fetch standings');
            }

            final document = parse(res_detail.body);
            final match = document
                .querySelectorAll('#gm_brd')[0]
                .querySelectorAll('div')[0];

            final name_stadium = match
                .querySelectorAll('div')[0]
                .querySelectorAll('p')[0]
                .nodes
                .last
                .text!
                .replaceAll(RegExp(r'\s+'), '');

            final time_gamestart = match
                .querySelectorAll('div')[0]
                .querySelectorAll('p')[0]
                .querySelectorAll('time')[0]
                .text
                .trim();

            final gamestart = formatted + " " + time_gamestart + ":00";
            datetime_gamestart = DateTime.tryParse(gamestart)!;

            final team_home = match
                .querySelectorAll('#async-gameDetail')[0]
                .querySelectorAll('div')[0]
                .querySelectorAll('p a')[0]
                .text
                .trim();

            final team_away = match
                .querySelectorAll('#async-gameDetail')[0]
                .querySelectorAll('div')[2]
                .querySelectorAll('p a')[0]
                .text
                .trim();

            var flg_before = true;

            try {
              score_home = int.tryParse(
                    match
                        .querySelectorAll('#async-gameDetail')[0]
                        .querySelectorAll('div')[1]
                        .querySelectorAll('p')[0]
                        .querySelectorAll('span')[0]
                        .text
                        .trim(),
                  ) ??
                  -1;

              score_away = int.tryParse(match
                      .querySelectorAll('#async-gameDetail')[0]
                      .querySelectorAll('div')[1]
                      .querySelectorAll('p')[0]
                      .querySelectorAll('span')[2]
                      .text
                      .trim()) ??
                  -1;
            } catch (e) {
              print('試合前なのでスコアのスクレイピングには失敗しました。');
            } finally {
              flg_before = true;
            }

            String pitcher_home = '';
            String pitcher_away = '';

            if (flg_before = false) {
              pitcher_home = document
                  .querySelectorAll('#strt_mem')[0]
                  .querySelectorAll('section')[0]
                  .querySelectorAll('div')[0]
                  .querySelectorAll('section')[0]
                  .querySelectorAll('table')[0]
                  .querySelectorAll('tbody')[0]
                  .querySelectorAll('tr')[0]
                  .querySelectorAll('td')[2]
                  .querySelectorAll('a')[0]
                  .text
                  .trim();

              pitcher_away = document
                  .querySelectorAll('#strt_mem')[0]
                  .querySelectorAll('section')[0]
                  .querySelectorAll('div')[0]
                  .querySelectorAll('section')[1]
                  .querySelectorAll('table')[0]
                  .querySelectorAll('tbody')[0]
                  .querySelectorAll('tr')[0]
                  .querySelectorAll('td')[2]
                  .querySelectorAll('a')[0]
                  .text
                  .trim();
            } else {
              pitcher_home = document
                  .querySelectorAll('#strt_pit')[0]
                  .querySelectorAll('div')[0]
                  .querySelectorAll('div')[0]
                  .querySelectorAll('section')[0]
                  .querySelectorAll('div')[1]
                  .querySelectorAll('div')[0]
                  .querySelectorAll('table')[0]
                  .querySelectorAll('tbody')[0]
                  .querySelectorAll('tr')[0]
                  .querySelectorAll('td')[2]
                  .querySelectorAll('a')[0]
                  .text
                  .trim();

              pitcher_away = document
                  .querySelectorAll('#strt_pit')[0]
                  .querySelectorAll('div')[0]
                  .querySelectorAll('div')[0]
                  .querySelectorAll('section')[1]
                  .querySelectorAll('div')[1]
                  .querySelectorAll('div')[0]
                  .querySelectorAll('table')[0]
                  .querySelectorAll('tbody')[0]
                  .querySelectorAll('tr')[0]
                  .querySelectorAll('td')[2]
                  .querySelectorAll('a')[0]
                  .text
                  .trim();
            }

            print(team_home);

            final result_team_home = await Postgres.select(
                conn, AppSql.selectTeamsTodayGame(), team_home);

            id_team_home = result_team_home.first.toColumnMap()['id'];

            print(team_away);

            final results_team_away = await Postgres.select(
                conn, AppSql.selectTeamsTodayGame(), team_away);

            id_team_away = results_team_away.first.toColumnMap()['id'];

            print(pitcher_home);

            final result_pitcher_home = await conn.execute(
                AppSql.selectTodayPitcher(),
                parameters: [StringTool.noSpace(pitcher_home), id_team_home]);
            id_pitcher_home = result_pitcher_home.first.toColumnMap()['id'];

            print(pitcher_away);

            final result_pitcher_away = await conn.execute(
                AppSql.selectTodayPitcher(),
                parameters: [StringTool.noSpace(pitcher_away), id_team_away]);
            id_pitcher_away = result_pitcher_away.first.toColumnMap()['id'];

            print(name_stadium);

            final result_stadium = await Postgres.select(
                conn, AppSql.selectStadium(), '%$name_stadium%');

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
          final result_game = await conn.execute(AppSql.selectExistsGame(),
              parameters: [id_team_home, id_team_away, datetime_gamestart]);

          final game = t_game();
          game.id_stadium = id_stadium;
          game.id_team_home = id_team_home;
          game.id_team_away = id_team_away;
          game.id_pitcher_home = id_pitcher_home;
          game.id_pitcher_away = id_pitcher_away;
          game.datetime_start = datetime_gamestart;
          game.score_home = score_home;
          game.score_away = score_away;

          if (result_game.isEmpty) {
            //DBに同じ日付、同じ組み合わせの試合が登録されていない場合、新規登録する
            await Postgres.insert(conn, game);
          } else {
            //DBに同じ日付、同じ組み合わせの試合が登録されている場合は更新する
            await Postgres.update(conn, game);
          }
        } //for card
      } //for league
    }); // TransactionCommit

    print('== 予告先発投手スクレイピング完了 ==');
    return result;
  }

  static Future<void> fetchNPBPlayers() async {
    final conn = await Postgres.openConnection(); // ✅ 毎回新しい接続
    final results = await conn.execute(AppSql.selectTeams());
    final teams = results
        .map((row) => {
              'id': row[0],
              'url': row[1],
            })
        .toList();

    await Postgres.transactionCommit(conn, () async {
      for (final team in teams) {
        final url = team['url'] as String;
        final res = await http.get(Uri.parse(url));
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }

        final doc = parse(utf8.decode(res.bodyBytes));
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
    }); //transactionCommit
  }

  static Future<void> fetchNPBStatsDetails() async {
    final conn = await Postgres.openConnection(); // ✅ 毎回新しい接続
    final results = await conn.execute(AppSql.selectStatsDetails());
    final stats = results
        .map((row) => {
              'id_stats': row[0],
              'id_league': row[1],
              'url': row[2],
              'int_idx_col': row[3],
            })
        .toList();
    try {
      await Postgres.begin(conn);
      print(results);
      print("✅ トランザクション開始されました");

      for (final stat in stats) {
        print(1);
        final url = stat['url'] as String;
        final res = await http.get(Uri.parse(url));
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }

        final doc = parse(utf8.decode(res.bodyBytes));
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
          statsPlayer.stats =
              double.tryParse(cols[stat['int_idx_col'] as int]) ?? 0;
          statsPlayer.playerName = cols[1].split(RegExp(r'[\s　]+'))[0];
          statsPlayer.teamName = cols[1]
              .split(RegExp(r'[\s　]+'))[1]
              .replaceAll("(", "")
              .replaceAll(")", "");
          listStats.add(statsPlayer);
        }
        var sql = AppSql.selectInsertPlayerStats(listStats);
        var cnt_rows = await Postgres.execute(conn, sql);
        print("実行行数" + cnt_rows.toString());
      }

      await Postgres.commit(conn);
      print("✅ トランザクション成功 → COMMIT されました");
    } catch (e) {
      await Postgres.rollback(conn);
      print("❌ ロールバックされました: $e");
    } finally {
      await conn.close();
    }
  }
}
