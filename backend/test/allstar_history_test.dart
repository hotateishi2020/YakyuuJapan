import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../app/AllStarHistory.dart';

String page(String rows,
        {String legend = '◎印はファン選抜、他は監督選抜による。', String notes = ''}) =>
    '<div class="contents"><p>$legend</p><div><h5>セントラル・リーグ</h5><table class="player">$rows</table></div><div class="att_box">$notes</div></div>';
String player(String name, String marks, {String star = ''}) =>
    '<tr><td class="mark">$marks</td><td class="star">$star</td><td class="name">$name</td><td class="team">阪神</td></tr>';
void main() {
  test('historical roster distinguishes replacements, withdrawal and staff',
      () {
    final rows = parseHistoricalAllStarRoster(
        '''<div class="abstract">◎：ファン投票 その他は監督推薦 ◇：補充</div>
    <table class="chgtbl"><tr><th class="label">監督</th><td class="league l01"><div class="player"><span class="p_name">監督</span></div></td></tr>
    <tr><th class="label">一塁手</th><td class="league l01"><div class="player decline"><span class="p_name">選手A</span><span class="t_name">(巨人)</span><span class="mark">◎</span></div></td>
    <td class="league l02"><div class="player"><span class="p_name">選手B</span><span class="t_name">(南海)</span><span class="mark">◇</span></div></td></tr></table>''',
        1980);
    expect(rows, hasLength(2));
    expect(rows.first['withdrawn'], true);
    expect(rows.first['selections'], ['ファン投票']);
    expect(rows.last['selections'], ['補充選出']);
    expect(rows.last['team'], '南海');
    expect(rows.last['league'], 'パ・リーグ');
    expect(rows.last['source'], contains('y=1980'));
  });

  test('positions and overlapping ballots are preserved', () {
    final rows = parseNpbAllStarRoster(
        page(
            '<tr><th class="position">先発投手</th></tr>${player('A', '◎', star: '☆')}<tr><th class="position">投手</th></tr>${player('B', '', star: '☆')}${player('C', '')}'),
        2026);
    expect(rows[0]['position'], '先発投手');
    expect(rows[0]['selections'], ['ファン投票', '選手間投票']);
    expect(rows[1]['selections'], ['選手間投票']);
    expect(rows[2]['selections'], ['監督選抜']);
  });
  test('replacement, plus-one, withdrawal and staff are distinct', () {
    final rows = parseNpbAllStarRoster(
        page(
            '<tr><th class="position">監督</th></tr>${player('監督名', '')}<tr><th class="position">内野手</th></tr>${player('選手 A', '◇')}${player('選手 B', '◆')}${player('選手 C', '')}',
            notes: '選手A（阪神）けがのため辞退<br>選手C（阪神）を補充【選手A（阪神）けがのため欠場】'),
        2026);
    expect(rows.length, 3);
    expect(rows[0]['selections'], ['プラスワン投票']);
    expect(rows[0]['withdrawn'], true);
    expect(rows[1]['selections'], ['補充選出']);
    expect(rows[2]['selections'], ['補充選出']);
    expect(rows[2]['withdrawn'], false);
  });
  test('missing legend does not guess manager selection', () {
    final rows = parseNpbAllStarRoster(
        page('<tr><th class="position">捕手</th></tr>${player('A', '')}',
            legend: ''),
        2026);
    expect(rows.single['selections'], ['選出区分未確認']);
  });
  test('imported archive contains 75 complete seasons and selection methods',
      () {
    final data =
        jsonDecode(File('data/allstar_history.json').readAsStringSync()) as Map;
    final rows = data['players'] as List;
    expect(data['errors'], isEmpty);
    expect(rows.map((r) => r['year']).toSet().length, 75);
    expect(rows.any((r) => r['year'] == 2020), false);
    expect(
        rows.every((r) =>
            (r['selections'] as List).isNotEmpty &&
            ['セ・リーグ', 'パ・リーグ'].contains(r['league'])),
        true);
    expect(rows.any((r) => (r['selections'] as List).length == 2), true);
  });
}
