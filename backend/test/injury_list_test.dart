import 'package:test/test.dart';

import '../app/InjuryList.dart';

void main() {
  test('復帰予定は不明・今期絶望・全治期間に揃える', () {
    expect(InjuryList.periodLabel('不明'), '不明');
    expect(InjuryList.periodLabel('今季絶望・全治6～8ヶ月'), '今期絶望');
    expect(InjuryList.periodLabel('全治4週間程度'), '全治4週間');
    expect(InjuryList.periodLabel('全治6～8週間程度'), '全治6〜8週間');
    expect(InjuryList.periodLabel('長期見込'), '長期見込');
    expect(InjuryList.periodLabel(''), '不明');
  });

  test('故障者表から球団・選手・ポジション・期間を取る', () {
    const html = '''
      <table>
        <tr><td class="team">巨人</td><td class="team"></td></tr>
        <tr>
          <td class="name">■大勢</td>
          <td class="pos">投手</td>
          <td>右肘張り</td>
          <td>不明</td>
        </tr>
        <tr><td class="team">ソフトバンク</td></tr>
        <tr>
          <td class="name">甲斐野　央</td>
          <td class="pos">投手</td>
          <td>右肘</td>
          <td>今季絶望</td>
        </tr>
      </table>
    ''';
    final rows = InjuryList.parseHtml(html);
    expect(rows, hasLength(2));
    expect(rows.first.team, '巨人');
    expect(rows.first.name, '大勢');
    expect(rows.first.position, '投手');
    expect(rows.first.period, '不明');
    expect(rows.last.team, 'ソフトバンク');
    expect(rows.last.name, '甲斐野央');
    expect(rows.last.period, '今期絶望');
  });
}
