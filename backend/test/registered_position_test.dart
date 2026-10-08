import 'package:test/test.dart';

import '../app/RegisteredPosition.dart';

void main() {
  test('NPB名簿は見出しのポジションを選手に付ける', () {
    const html = '''
      <table class="rosterlisttbl">
        <tr><th>No.</th><th>監督</th><th>生年月日</th></tr>
        <tr><td>90</td><td>小久保　裕紀</td><td>1971.10.08</td></tr>
        <tr><th>No.</th><th>投手</th><th>生年月日</th></tr>
        <tr><td>18</td><td>上沢　直之</td><td>1994.02.06</td></tr>
        <tr><th>No.</th><th>捕手</th></tr>
        <tr><td>12</td><td>甲斐　拓也</td></tr>
      </table>
      <table class="rosterlisttbl">
        <tr><th>No.</th><th>外野手</th></tr>
        <tr><td>99</td><td>育成　選手</td></tr>
        <tr><th>No.</th><th>捕手</th></tr>
        <tr><td>12</td><td>甲斐　拓也</td></tr>
      </table>
    ''';
    final rows = RegisteredPosition.parseNpbRoster(html);
    final byName = {for (final row in rows) row.name: row.position};
    expect(byName['小久保裕紀'], isNull);
    expect(byName['上沢直之'], '投手');
    expect(byName['甲斐拓也'], '捕手');
    expect(byName['育成選手'], '外野手');
  });

  test('MLB名簿は投手捕手内野手外野手の見出しで分ける', () {
    const html = '''
      <h2 class="bb-head01__title">投手</h2>
      <p class="bb-playerList__name">アーロン・ジャッジ</p>
      <h2 class="bb-head01__title">外野手</h2>
      <p class="bb-playerList__name">アーロン・ジャッジ</p>
      <h2 class="bb-head01__title">指名打者</h2>
      <p class="bb-playerList__name">ジャンカルロ・スタントン</p>
      <h2 class="bb-head01__title">順位表</h2>
      <p class="bb-playerList__name">関係ない</p>
    ''';
    final rows = RegisteredPosition.parseYahooMlbRoster(html);
    expect(rows.map((row) => '${row.name}:${row.position}').toList(), [
      'アーロン・ジャッジ:投手',
      'アーロン・ジャッジ:外野手',
      'ジャンカルロ・スタントン:指名打者',
    ]);
  });

  test('MLBの略称と名簿の姓名は姓で揃う', () {
    expect(RegisteredPosition.lastToken('アロルディス・チャプマン'), 'チャプマン');
    expect(RegisteredPosition.lastToken('A.チャプマン'), 'チャプマン');
    expect(RegisteredPosition.lastToken('山本祐大'), '山本祐大');
  });

  test('Yahooの球団略称をDBの球団名に合わせる', () {
    final teams = [
      {'id': 15, 'name_short': 'ヤンキース', 'name_full': 'ニューヨーク・ヤンキース', 'name_shortest': 'NYY'},
      {'id': 14, 'name_short': 'レッドソックス', 'name_full': 'ボストン・レッドソックス', 'name_shortest': 'BOS'},
      {'id': 29, 'name_short': 'ダイヤモンドバックス', 'name_full': 'アリゾナ・ダイヤモンドバックス', 'name_shortest': 'AZ'},
    ];
    expect(RegisteredPosition.matchTeamId(teams, 'ヤンキース'), 15);
    expect(RegisteredPosition.matchTeamId(teams, 'Rソックス'), 14);
    expect(RegisteredPosition.matchTeamId(teams, 'Dバックス'), 29);
    expect(
      RegisteredPosition.yahooMlbTeamIds('<a href="/mlb/teams/2021010/top">ヤンキース</a>'),
      {'2021010': 'ヤンキース'},
    );
  });
}
