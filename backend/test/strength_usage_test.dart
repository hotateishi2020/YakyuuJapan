import 'package:test/test.dart';
import '../app/StrengthUsage.dart';

void main() {
  test('公式名簿と成績の異体字・全角英字を照合する', () {
    expect(usageName('伊藤 大海'), usageName('伊藤大海'));
    expect(usageName('Ａ．コックス'), usageName('A.コックス'));
  });
  test('投球回端数、0回、打者を残して交代した＋表記をアウト数に変換', () {
    expect(inningsToOuts('6.1'), 19);
    expect(inningsToOuts('0.2'), 2);
    expect(inningsToOuts('0 +'), 0);
    expect(inningsToOuts('+'), 0);
    expect(inningsToOuts(' 5\n .2 '), 17);
    expect(inningsToOuts('6 1/3'), 19);
    expect(() => inningsToOuts('6.3'), throwsFormatException);
  });
  test('同一投手の先発・救援と移籍前後の球団を分け重複試合を除く', () {
    final games = [
      {
        'game_key': '1',
        'players': [
          {
            'source_player_id': 'p',
            'name': '兼任',
            'team_code': 'g',
            'starter': true,
            'outs': 19
          },
          {
            'source_player_id': 'q',
            'name': '抑え',
            'team_code': 'g',
            'starter': false,
            'outs': 8
          }
        ]
      },
      {
        'game_key': '2',
        'players': [
          {
            'source_player_id': 'q',
            'name': '抑え',
            'team_code': 'g',
            'starter': true,
            'outs': 21
          },
          {
            'source_player_id': 'p',
            'name': '兼任',
            'team_code': 'g',
            'starter': false,
            'outs': 2
          }
        ]
      },
      {
        'game_key': '3',
        'players': [
          {
            'source_player_id': 'p',
            'name': '兼任',
            'team_code': 't',
            'starter': true,
            'outs': 18
          }
        ]
      },
    ];
    final rows = aggregateUsageGames([...games, games.first], 'g');
    final p = rows.firstWhere((p) => p['source_player_id'] == 'p');
    expect(p['total_outs'], 21);
    expect(p['starter_outs'], 19);
    expect(p['relief_outs'], 2);
    expect(p['appearances'], 2);
    expect(p['starts'], 1);
    expect(aggregateUsageGames(games, 't').single['total_outs'], 18);
  });
  test('先発が欠けた試合は不完全な負担率を保存しない', () {
    expect(
        () => aggregateUsageGames([
              {
                'game_key': '1',
                'players': [
                  {
                    'team_code': 'g',
                    'source_player_id': 'p',
                    'starter': false,
                    'outs': 3
                  }
                ]
              }
            ], 'g'),
        throwsStateError);
  });
  test('NPB月別日程は終了スコアのある試合だけ取得する', () {
    expect(
        npbSeasonGames(
            '''<table><tr><td><div class="team1">巨人</div><a href="/scores/2026/0327/g-t-01/"><div class="score1">1</div><div class="score2">0</div></a></td></tr><tr><td><div class="team1">巨人</div><a href="/scores/2026/0328/g-t-02/">中止</a></td></tr></table>''',
            2026),
        ['https://npb.jp/scores/2026/0327/g-t-01/box.html']);
  });
  test('ポストシーズンは公式戦の負担率から除外する', () {
    expect(
        parseNpbUsageGame('<div class="game_tit"><h3>【CS ファーストステージ】</h3></div>',
            'https://npb.jp/scores/2026/1010/g-t-01/box.html'),
        isEmpty);
  });
  test('公示の登録選手リンクから所属球団と退団確定を取得する', () {
    final rows = parseNpbStatusAnnouncements(
        '<table><tr><th>2026/10/12</th><td><a href="./registered_b.html">球団</a></td><td><a href="https://npb.jp/bis/players/123.html">選手</a></td></tr></table>',
        'https://npb.jp/announcement/2026/pn_released.html');
    expect(rows.single['team_code'], 'b');
    expect(rows.single['player_key'], 'npb:123');
    expect(rows.single['departure_confirmed'], true);
  });
}
