import 'package:html/parser.dart';
import 'package:test/test.dart';
import '../app/FetchURL.dart';

void main() {
  test('投手勝率の列は全角空白を含む見出しから選び暴投と混同しない', () {
    final table = parse('<table><thead><tr><th>選手名</th><th>暴　投</th><th><a>勝　率</a></th></tr></thead></table>').querySelector('table')!;
    expect(yahooRankingColumn(table, '勝率'), 2);
    expect(yahooRankingColumn(table, '防御率'), -1);
  });
}
