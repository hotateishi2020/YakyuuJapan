import 'package:test/test.dart';
import '../app/JapaneseMlbStats.dart';

void main() {
  test('ホールドとHPは別の成績として保持する', () {
    final result = buildJapaneseMlbStats([], [
      for (final entry in {'ホールド': 12, 'HP': 15}.entries)
        {'id_player': 1, 'name_player': '投手', 'id_league': 3,
         'flg_japan': true, 'flg_pitcher': true,
         'title': entry.key, 'stats': entry.value},
    ], 2026);
    final stats = (result['players'] as List).single['stats'];
    expect(stats['ホールド'], 12);
    expect(stats['HP'], 15);
  });

  test('姓にフルネームが入った村上も略称と統合し成績を維持する', () {
    final result = buildJapaneseMlbStats([
      {'id_player': 1, 'name_player': '村上', 'name_last': '村上', 'id_team': 18, 'date_birth': '2000-02-02', 'int_batting': 454},
      {'id_player': 2, 'name_player': '村上宗隆', 'name_last': '村上宗隆', 'name_first': '', 'id_team': 18, 'date_birth': '2000-02-02', 'int_batting': 454},
    ], [
      {'id_player': 2, 'name_player': '村上宗隆', 'name_last': '村上宗隆', 'id_team': 18, 'id_league': 3, 'flg_japan': true, 'flg_pitcher': false, 'title': '本塁打', 'stats': '35'},
    ], 2026);
    final players = result['players'] as List;
    expect(players, hasLength(1));
    expect(players.single['name_player'], '村上宗隆');
    expect(players.single['stats']['打数'], 454);
    expect(players.single['stats']['本塁打'], '35');
  });

  test('年長順に表示し生年月日不明は末尾に置く', () {
    final rows = <Map<String,dynamic>>[
      {'id_player':1,'name_player':'若手','date_birth':'2000-01-01','int_pitching':1},
      {'id_player':2,'name_player':'不明','int_pitching':1},
      {'id_player':3,'name_player':'年長','date_birth':'1988-12-31','int_pitching':1},
      {'id_player':4,'name_player':'中堅','date_birth':'1994-07-05','int_pitching':1},
    ];
    final result = buildJapaneseMlbStats(rows, [], 2026);
    expect((result['players'] as List).map((p) => p['id_player']), [3,4,1,2]);
  });

  test('略称とフルネームを統合し、同じ球団の成績を二重加算しない', () {
    final rows = <Map<String, dynamic>>[
      {
        'id_player': 1,
        'name_player': '大谷',
        'id_team': 10,
        'int_pitching': 14,
        'int_win': 8,
        'int_batting': 523
      },
      {
        'id_player': 2,
        'name_player': '大谷 翔平',
        'name_last': '大谷',
        'id_team': 10,
        'int_pitching': 14,
        'int_win': 8,
        'int_batting': 523
      },
      {'id_player': 3, 'name_player': '山本', 'id_team': 10, 'int_pitching': 28},
      {
        'id_player': 4,
        'name_player': '山本 由伸',
        'name_last': '山本',
        'id_team': 10,
        'int_pitching': 28
      },
    ];
    final result = buildJapaneseMlbStats(
        rows,
        [
          {
            'id_player': 3,
            'name_player': '山本',
            'id_team': 10,
            'id_league': 3,
            'flg_japan': true,
            'flg_pitcher': true,
            'title': 'WHIP',
            'stats': '0.87'
          },
        ],
        2026);
    final players = (result['players'] as List).cast<Map<String, dynamic>>();
    expect(players, hasLength(3));
    expect(players.where((p) => p['name_player'] == '大谷 翔平'), hasLength(2));
    final pitcher =
        players.firstWhere((p) => p['id_player'] == 2 && p['pitching'] == true);
    expect(pitcher['stats']['登板'], 14);
    expect(pitcher['stats']['勝利'], 8);
    expect(players.firstWhere((p) => p['id_player'] == 4)['stats']['WHIP'],
        '0.87');
  });
  test('同姓の候補が複数いる場合や生年月日が違う場合は統合しない', () {
    final rows = <Map<String, dynamic>>[
      {'id_player': 1, 'name_player': '山本', 'id_team': 10},
      {
        'id_player': 2,
        'name_player': '山本 一郎',
        'name_last': '山本',
        'id_team': 10
      },
      {
        'id_player': 3,
        'name_player': '山本 二郎',
        'name_last': '山本',
        'id_team': 10
      },
    ];
    expect(canonicalJapaneseRows(rows, []).$1, hasLength(3));
    expect(
        canonicalJapaneseRows([
          {...rows[0], 'date_birth': '1990-01-01'},
          {...rows[1], 'date_birth': '1992-01-01'},
        ], []).$1,
        hasLength(2));
  });

  test('ランキング圏外と二刀流を含め、投球回をアウト単位で合算する', () {
    final result = buildJapaneseMlbStats([
      {
        'id_player': 1,
        'name_player': '二刀流',
        'name_team': 'A',
        'int_pitching': 2,
        'double_inning': 1.2,
        'int_appearance': 10,
        'int_batting': 8
      },
      {
        'id_player': 1,
        'name_player': '二刀流',
        'name_team': 'B',
        'int_pitching': 3,
        'double_inning': 2.2,
        'int_appearance': 5,
        'int_batting': 4
      },
      {
        'id_player': 2,
        'name_player': 'ランキング圏外',
        'name_team': 'C',
        'int_pitching': 1,
        'double_inning': 1.0
      },
    ], [
      {
        'id_player': 1,
        'name_player': '二刀流',
        'id_league': 3,
        'flg_japan': true,
        'flg_pitcher': false,
        'title': '本塁打',
        'stats': '4'
      },
      {
        'id_player': 3,
        'id_league': 3,
        'flg_japan': false,
        'title': '本塁打',
        'stats': '50'
      },
      {
        'id_player': 4,
        'id_league': 1,
        'flg_japan': true,
        'title': '本塁打',
        'stats': '50'
      },
    ], 2026);
    final players = (result['players'] as List).cast<Map<String, dynamic>>();
    expect(players, hasLength(3));
    final pitcher =
        players.firstWhere((p) => p['id_player'] == 1 && p['pitching'] == true);
    expect(pitcher['stats']['投球回'], '4.1');
    expect(pitcher['stats']['登板'], 5);
    final batter = players.firstWhere((p) => p['pitching'] == false);
    expect(batter['stats']['本塁打'], '4');
    expect(batter['stats']['打席'], 15);
    expect(batter['stats'].containsKey('打率'), false);
    expect(batter['stats'].containsKey('打点'), false);
  });
}
