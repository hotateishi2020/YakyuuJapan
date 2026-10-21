import 'package:test/test.dart';
import '../app/SeasonAwards.dart';

void main() {
  test('特別表彰は見出しの文脈で分類し正力特別賞を混ぜない', () {
    final rows = parseSeasonAwardPage(
      '<div class="contents"><h4>連盟特別表彰</h4>'
      '<div class="player_unit_1"><h6>最優秀監督賞</h6><dt class="name">監督</dt></div>'
      '<div class="player_unit_1"><h6>功労賞</h6><dt class="name">功労</dt></div>'
      '<div class="player_unit_1"><h6>特別賞</h6><dt class="name">連盟</dt></div>'
      '<h4>コミッショナー特別表彰</h4>'
      '<div class="player_unit_1"><h6>特別賞</h6><dt class="name">特別</dt></div>'
      '<h4>正力松太郎賞</h4>'
      '<div class="player_unit_1"><h6>正力松太郎賞</h6><dt class="name">正力</dt></div>'
      '<div class="player_unit_1"><h6>正力松太郎賞（特別賞）</h6><dt class="name">正力特別</dt></div></div>',
      'award/2026/cl.html', 2026);
    expect(rows.map((r) => r['key']), [
      'manager', 'league_merit', 'league_special', 'commissioner_special', 'shoriki', 'shoriki_special']);
  });
  test('日本シリーズのMVP・敢闘賞・複数の優秀選手を区別する', () {
    final rows = parseSeasonAwardPage(
      '<div class="contents"><h4>最高殊勲選手賞</h4><dl><dt class="name">MVP</dt><dd class="team">阪神</dd></dl>'
      '<h4>敢闘選手賞</h4><dl><dt class="name">敢闘</dt><dd class="team">ソフトバンク</dd></dl>'
      '<h4>優秀選手賞</h4><dl><dt class="name">優秀A</dt><dd class="team">阪神</dd></dl>'
      '<dl><dt class="name">優秀B</dt><dd class="team">阪神</dd></dl></div>',
      'nippons/2026/award.html', 2026);
    expect(rows.map((r) => r['key']), ['series_mvp', 'series_fighting', 'series_outstanding', 'series_outstanding']);
  });
  test('sayonara month and farm awards stay separate from first-team awards', () {
    final monthly = parseSeasonAwardPage(
      '<div class="contents"><h5>セントラル・リーグ</h5><table><tr><th>3、4月度</th><td>選手A</td><td>（阪神）</td></tr></table></div>',
      'award/2026/sayonara.html', 2026);
    expect(monthly.single['key'], 'sayonara');
    final farm = parseSeasonAwardPage(
      '<div class="player_unit_1"><h6>最多本塁打者賞</h6><dt class="name">選手B</dt><dd class="team">（中日）</dd></div>',
      'award/2026/2c.html', 2026);
    expect(farm.single['key'], 'farm_major');
    expect(farm.single['farm_league'], '中地区');
    expect(farm.single['award_label'], '最多本塁打者賞');
  });
  test('farm statistical leaders keep ties without declaring awards', () {
    final rows = parseSeasonAwardPage(
      '<div class="unit-half__section"><h5>奪三振</h5><table>'
      '<tr><td>1</td><td>A (Ｆ)</td><td>100</td></tr>'
      '<tr><td>1</td><td>B (Ｓ)</td><td>100</td></tr>'
      '<tr><td>3</td><td>C (Ｍ)</td><td>90</td></tr></table></div>',
      'bis/2026/stats/llp_2e.html', 2026);
    expect(rows.length, 2);
    expect(rows.first['team'], '日本ハム');
    expect(rows.first['confirmed'], false);
    expect(rows.first['statistical'], true);
  });
  test('monthly table uses th month and keeps league/role', () {
    final rows = parseSeasonAwardPage(
        '''<div class="contents"><h5>セントラル・リーグ</h5><h6>投手</h6><table><tr><th>月</th><th>選手</th><th>球団</th></tr><tr><th>5月度</th><td>A 投手</td><td>（阪神）</td><td>初受賞</td></tr></table></div>''',
        'award/2026/month.html',
        2026);
    expect(rows.single['name'], 'A 投手');
    expect(rows.single['team'], '阪神');
    expect(rows.single['detail'], 'セントラル・リーグ 投手 5月度');
  });
  test('award page distinguishes MVP and rookie and keeps performance', () {
    final rows = parseSeasonAwardPage(
        '''<a class="player_unit_1"><h6>最優秀新人賞</h6><dt class="name">新人</dt><dd class="team">（中日）</dd></a><a class="player_unit_1"><h6>最多本塁打者賞</h6><dt class="name">打者</dt><dd class="comment">本塁打 40</dd></a>''',
        'award/2026/cl.html',
        2026);
    expect(rows[0]['key'], 'rookie');
    expect(rows[1]['key'], 'major');
    expect(rows[1]['value'], '本塁打 40');
  });
  test('roster excludes coaches and keeps selected players', () {
    final rows = parseSeasonAwardPage(
        '''<div><h5>セントラル・リーグ</h5><table class="player"><tr><th class="position">監督</th></tr><tr><td class="name">監督名</td></tr><tr><th class="position">投手</th></tr><tr><td class="name">投手名</td><td class="team">西武</td></tr></table></div>''',
        'allstar/2026/roster.html',
        2026);
    expect(rows.single['name'], '投手名');
  });
  test('weekly MVP does not import second and third places', () {
    final rows = parseSportsNaviWeekly(
        '''<div class="cm-articleParagraph__text">パ・リーグ野手では</div><div class="cm-articleParagraph__text"><b>1位 選手 一（西武）</b><b>2位 選手 二（ロッテ）</b></div>''',
        'https://sports.yahoo.co.jp/column/detail/2026092800006-spnavi?p=2');
    expect(rows.single['name'], '選手 一');
    expect(rows.single['detail'], '2026/09/28発表 パ・リーグ 野手');
  });
  test('live standings are not recorded as pennant winners', () {
    const table =
        '<div class="contents"><table class="tablefix2"><tbody><tr><td>阪神</td></tr></tbody></table></div>';
    expect(parseSeasonAwardPage(table, 'bis/2026/stats/std_c.html', 2026),
        isEmpty);
    expect(
        parseSeasonAwardPage(table.replaceFirst('<table', '<p>全日程終了</p><table'),
                'bis/2026/stats/std_c.html', 2026)
            .single['key'],
        'league_champion');
  });
}
