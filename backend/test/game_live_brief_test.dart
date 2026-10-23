import 'package:html/parser.dart';
import 'package:test/test.dart';
import '../app/GameLiveBrief.dart';

void main() {
  test('バッテリーの最後の投手を読み、捕手と打撃成績を含めない', () {
    final doc = parse('''
      <section id="battery"><table>
        <tr><th>広島</th><td><a>森</a>、<a>菊地</a> - <a>石原</a></td></tr>
        <tr><th>阪神</th><td><a>大竹</a>、<a>岩崎</a> - <a>伏見</a>、<a>梅野</a></td></tr>
      </table></section>
      <section id="homerun"><table>
        <tr><th>広島</th><td><a>末包</a> 12号(2回表2ラン)、13号(5回表ソロ)</td></tr>
        <tr><th>阪神</th><td></td></tr>
      </table></section>
      <section id="async-gameBatterStats"><table><tr><td>3打数2安打</td></tr></table></section>
    ''');
    expect(parseGameLiveBrief(doc, home: '阪神', away: '広島'), {
      'name_current_pitcher_home': '岩崎',
      'name_current_pitcher_away': '菊地',
      'name_homerun_home': '',
      'name_homerun_away': '末包 12号(2回表2ラン)、13号(5回表ソロ)',
    });
  });
  test('未公開の欄で取得済み情報を消さず、不明なチームを割り当てない', () {
    expect(parseGameLiveBrief(parse('<section id="battery"><table><tr><th>不明</th><td>投手 - 捕手</td></tr></table></section>'), home: '阪神', away: '広島'), isEmpty);
    expect(parseGameLiveBrief(parse('<section id="strt_mem">予告投手</section>'), home: '阪神', away: '広島'), isEmpty);
  });
}
