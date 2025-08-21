import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'dart:convert';
import 'package:koko/tools/Sql.dart';
import 'package:koko/tools/Postgres.dart';
import 'package:koko/tools/StringTool.dart';
import 'package:koko/DB/m_player.dart';
import 'package:koko/DB/t_stats_player.dart';

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

  static Future<void> fetchNPBPlayers() async {
    final conn = await Postgres.openConnection(); // ✅ 毎回新しい接続
    final results = await conn.query(Sql.selectTeams());
    final teams = results
        .map((row) => {
              'id': row[0],
              'url': row[1],
            })
        .toList();

    try {
      await Postgres.begin(conn);

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
          player.id_team = team['id'];

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

      await Postgres.commit(conn);
      print("✅ トランザクション成功 → COMMIT されました");
    } catch (e) {
      await Postgres.rollback(conn);
      print("❌ ロールバックされました: $e");
    } finally {
      await conn.close();
    }
  }

  static Future<void> fetchNPBStatsDetails() async {
    final conn = await Postgres.openConnection(); // ✅ 毎回新しい接続
    print(0);
    final results = await conn.query(Sql.selectStatsDetails());
    print(0);
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
          statsPlayer.id_league = stat['id_league'];
          statsPlayer.id_stats = stat['id_stats'];
          statsPlayer.stats = double.tryParse(cols[stat['int_idx_col']]) ?? 0;
          statsPlayer.playerName = cols[1].split(RegExp(r'[\s　]+'))[0];
          statsPlayer.teamName = cols[1]
              .split(RegExp(r'[\s　]+'))[1]
              .replaceAll("(", "")
              .replaceAll(")", "");
          listStats.add(statsPlayer);
        }
        var (sql, map) = Sql.selectInsertPlayerStats(listStats);
        print(4);
        var cnt_rows = await Postgres.execute(conn, sql, map);
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
