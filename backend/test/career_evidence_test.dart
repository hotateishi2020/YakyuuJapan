import 'package:test/test.dart';
import '../app/CareerEvidence.dart';

void main() {
  test('リトルシニアをリトルと混同しない', () {
    expect(careerCategory('調布リトルリーグ'), 'リトル');
    expect(careerCategory('調布リトルシニア'), 'シニア');
  });

  test('経歴から学校・社会人・独立を抽出し海外プロは除外', () {
    final p = npbCareerEvidence(
        '''<table><tr><th>経歴</th><td>横浜高 - 明治大 - ENEOS - 四国・徳島 - 米マイナー - パドレス</td></tr><tr><th>ドラフト</th><td>2020年ドラフト1位</td></tr></table>''',
        'https://npb.jp/');
    final paths = p['career_history'] as List;
    expect(paths.map((p) => p['category']), ['高校', '大学', '社会人', '独立']);
    expect((p['badges'] as List).single['label'], 'ドラフト1位');
    expect(careerCategory('東海大相模高'), '高校');
    expect(careerCategory('東海大九州キャンパス'), '大学');
    expect(careerCategory('大分商'), '高校');
  });
  test('育成1位は支配下1位と区別し、11位を1位と誤認しない', () {
    List badges(String text) => (npbCareerEvidence(
        '<table><tr><th>ドラフト</th><td>$text</td></tr></table>',
        'https://npb.jp/')['badges'] as List);
    expect(badges('2020年育成ドラフト1位').single['label'], '育成ドラフト1位');
    expect(badges('2020年ドラフト11位'), isEmpty);
    expect(badges('2020年育成選手ドラフト1位').single['label'], '育成ドラフト1位');
  });
  test('受賞欄のポジション名をゴールデングラブ賞に付ける', () {
    final rows = namedAwardEvidence(
        '<a class="player_unit_1" href="/bis/players/123.html"><h6>捕手</h6><dt class="name">選手名</dt><dd class="comment">初受賞</dd></a>',
        2025,
        'https://npb.jp/',
        glove: true);
    expect(rows.single['player_key'], 'npb:123');
    expect(rows.single['badge']['label'], 'ゴールデングラブ賞（捕手）');
  });
}
