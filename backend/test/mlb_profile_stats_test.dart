import 'package:html/parser.dart';
import 'package:test/test.dart';
import '../app/MlbProfileStats.dart';

void main() {
  String table(List<String> headers, List<String> values) => '<table class="bb-playerStatsTable"><tr>${headers.map((h) => '<th>$h</th>').join()}</tr><tr>${values.map((v) => '<td>$v</td>').join()}</tr></table>';
  test('二刀流でも打者表の打率と打席を読み、防御率を混ぜない', () {
    final doc = parse('<div id="js-tabDom01">${table(['防御率','投球回'],['1.79','85.2'])}${table(['打率','試合','打席','本塁打'],['.275','139','618','30'])}${table(['打率','打席'],['.280','137'])}</div>');
    final batting = mlbProfileStats(doc, pitching: false);
    expect(batting['打率'], .275);
    expect(batting['打席'], 618);
    expect(batting['本塁打'], 30);
    expect(mlbProfileStats(doc, pitching: true)['防御率'], 1.79);
  });
  test('WHIPが次の見出し行や全角でも取得する', () {
    final doc = parse('<div id="js-tabDom01"><table class="bb-playerStatsTable">'
      '<tr><th>防御率</th><th>投球回</th></tr><tr><td>5.37</td><td>154.1</td></tr>'
      '<tr><th>被安打</th><th>与四球</th><th>ＷＨＩＰ</th></tr>'
      '<tr><td>167</td><td>36</td><td>1.32</td></tr></table></div>');
    expect(mlbProfileStats(doc, pitching: true)['WHIP'], 1.32);
  });
  test('WHIP欠損時は被安打と与四球と正確なアウト数から補完する', () {
    for (final innings in ['1.1', '0', '1.3']) {
      final doc = parse('<div id="js-tabDom01">${table(['防御率','投球回','被安打','与四球','与死球'],['0',innings,'1','1','9'])}</div>');
      expect(mlbProfileStats(doc, pitching: true)['WHIP'], innings == '1.1' ? 1.5 : isNull);
    }
    final doc = parse('<div id="js-tabDom01">${table(['防御率','投球回','被安打'],['0','10','1'])}</div>');
    expect(mlbProfileStats(doc, pitching: true)['WHIP'], isNull);
  });
  test('投手表しかなければ打撃成績を作らない', () {
    final doc = parse('<div id="js-tabDom01">${table(['防御率','投球回'],['5.37','160'])}</div>');
    expect(mlbProfileStats(doc, pitching: false), isEmpty);
  });
}
