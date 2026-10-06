import 'package:html/parser.dart';
import 'package:test/test.dart';

import '../app/LiveText.dart';

void main() {
  test('km/h and mph convert to stored km/h', () {
    expect(LiveText.kmhFromSpeedText('155km/h'), 155);
    expect(LiveText.kmhFromSpeedText('142km/h'), 142);
    expect(LiveText.kmhFromSpeedText('98mph'), 158);
    expect(LiveText.kmhFromSpeedText('100mph'), 161);
    expect(LiveText.kmhFromSpeedText('12km/h'), isNull);
  });

  test('一球速報の打席ページから投手名と最速を取る', () {
    final doc = parse('''
      <div>
        <table id="gm_rslt">
          <tr>
            <th colspan="2">投手</th>
            <th colspan="2">打者</th>
          </tr>
          <tr>
            <td class="bb-splitsTable__data--text"><a>柳 裕也</a></td>
            <td>右</td>
            <td class="bb-splitsTable__data--text"><a>中野 拓夢</a></td>
            <td>左</td>
          </tr>
        </table>
        <table>
          <tr>
            <td class="bb-splitsTable__data--speed">125km/h</td>
          </tr>
          <tr>
            <td class="bb-splitsTable__data--speed">157km/h</td>
          </tr>
          <tr>
            <td class="bb-splitsTable__data--speed">142km/h</td>
          </tr>
        </table>
        <dd class="next" title="次へ"><a href="?index=0610200" index="0610200">次へ</a></dd>
        <a href="/npb/game/1/score?index=0110100">1</a>
        <a href="/npb/game/1/score?index=0710000">7</a>
      </div>
    ''');
    final found = LiveText.maxKmhOnScorePage(doc);
    expect(found?.pitcher, '柳 裕也');
    expect(found?.kmh, 157);
    expect(LiveText.nextScoreIndex(doc), '0610200');
    expect(LiveText.scorePlateIndexes(doc), contains('0110100'));
    expect(LiveText.scorePlateIndexes(doc), isNot(contains('0710000')));
  });
}
