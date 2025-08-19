import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'dart:convert';

class FetchURL {

  static const targetUrl = 'https://npb.jp/bis/teams/rst_h.html';

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

  static Future<void> scrapeAndInsert() async {
  // 1) 取得（npb.jp は通常 UTF-8。文字化けする場合は bytes から decode を工夫）
  final res = await http.get(Uri.parse(targetUrl));
  if (res.statusCode != 200) {
    throw Exception('HTTP ${res.statusCode}');
  }

  // Encodingの自動判別が必要な場合は res.bodyBytes を使い、UTF-8前提なら以下でOK
  final doc = parse(utf8.decode(res.bodyBytes));

  // 2) テーブルを探索（サイト構造に依存。必要に応じてセレクタ調整）
  // 例: 最初の <table> のデータ行を拾う
  final tables = doc.querySelectorAll('table.rosterlisttbl');
  if (tables.isEmpty) {
    throw Exception('テーブルが見つかりませんでした');
  }

  // どのテーブルか分かっているなら、class や caption で絞り込むのがベター
  // final table = doc.querySelector('table.someClass') ?? tables.first;
  final table = tables.first;

  // 3) 行パース（thead をスキップ、th だけの行は除外）
  // final rows = <TeamRow>[];
  for (final tr in table.querySelectorAll('tr')) {
    final tds = tr.querySelectorAll('td');
    if (tds.isEmpty) continue; // ヘッダ行などはスキップ

    // 1列目を label、それ以降を配列で保持
    final cols = tds.map((td) => td.text.trim()).toList();

    print(cols);

    // 例: 空行や「合計」などを除外したい場合はここでフィルタ
    // if (label.isEmpty) continue;

    // rows.add(TeamRow(label: label, cols: cols));
  }

  // if (rows.isEmpty) {
  //   throw Exception('データ行が抽出できませんでした。セレクタを見直してください。');
  // }

  // // 4) DBへ一括INSERT
  // await AppDatabase.insertRows(rows);
}

}