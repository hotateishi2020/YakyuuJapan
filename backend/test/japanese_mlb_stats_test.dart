import 'package:test/test.dart';
import '../app/JapaneseMlbStats.dart';

void main() {
  test('大谷の正式ランキングを略称のランク外ゼロで上書きしない', () {
    final ranked={'id_player':5625,'name_player':'大谷翔平','name_last':'大谷','id_team':40,
      'id_league':4,'flg_japan':true,'flg_pitcher':false,'title':'本塁打',
      'int_rank':9,'cnt_play':618,'stats':'30'};
    final stale={...ranked,'id_player':5334,'name_player':'大谷','int_rank':1000,'cnt_play':14,'stats':'0'};
    for(final rows in [[ranked,stale],[stale,ranked]]) {
      final data=buildJapaneseMlbStats([],rows,2026);
      expect(data['players'],hasLength(1));
      expect(data['players'].single['stats']['本塁打'],'30');
      expect(data['players'].single['stats']['打席'],618);
    }
  });
  test('重複時に数値の最大値を選ばず正当なゼロも保持する', () {
    final ranked={'id_player':1,'name_player':'対象太郎','name_last':'対象','id_team':40,
      'id_league':4,'flg_japan':true,'flg_pitcher':true,'title':'防御率',
      'int_rank':1,'cnt_play':180,'stats':'0.00'};
    final duplicate={...ranked,'id_player':2,'name_player':'対象','int_rank':1000,'cnt_play':14,'stats':'5.00'};
    final data=buildJapaneseMlbStats([],[ranked,duplicate],2026);
    expect(data['players'].single['stats']['防御率'],'0.00');
  });

  test('ヌートバーは合計成績を維持して所属だけアリゾナ西地区にする', () {
    final result=buildJapaneseMlbStats([
      for(final west in [false,true]) {
        'id_player':1,'name_player':'ラーズ・ヌートバー',
        'url':'https://baseball.yahoo.co.jp/mlb/player/2102188/',
        'id_team':west?2:1,'id_league':4,'code_area':west?'WEST':'CENTER',
        'name_team':west?'ダイヤモンドバックス':'カージナルス',
        'color_back':west?'red':'blue','int_appearance':west?100:234,
        'int_batting':west?85:200,
      },
    ],[],2026);
    final player=(result['players'] as List).single;
    expect(player['name_team'],'ダイヤモンドバックス');
    expect(player['name_area'],'西地区');
    expect(player['id_team'],2);
    expect(player['color_back'],'red');
    expect(player['stats']['打席'],334);
    expect(player['stats']['打数'],285);
  });

  test('リーグ・東中西地区・球団名の順に並び同一球団内は年齢順', () {
    final data = buildJapaneseMlbStats([
      {'id_player': 1, 'id_league': 4, 'code_area': 'EAST', 'name_team': 'A', 'int_pitching': 1},
      {'id_player': 2, 'id_league': 3, 'code_area': 'WEST', 'name_team': 'A', 'int_pitching': 1},
      {'id_player': 3, 'id_league': 3, 'code_area': 'CENTER', 'name_team': 'A', 'int_pitching': 1},
      {'id_player': 4, 'id_league': 3, 'code_area': 'EAST', 'name_team': 'B', 'int_pitching': 1},
      {'id_player': 5, 'id_league': 3, 'code_area': 'EAST', 'name_team': 'A', 'int_pitching': 1, 'date_birth': '2000-01-01'},
      {'id_player': 6, 'id_league': 3, 'code_area': 'EAST', 'name_team': 'A', 'int_pitching': 1, 'date_birth': '1990-01-01'},
    ], [], 2026);
    final players = data['players'] as List;
    expect(players.map((p) => p['id_player']), [6, 5, 4, 3, 2, 1]);
    expect(players.first['name_league'], 'ア・リーグ');
    expect(players.first['name_area'], '東地区');
    expect(players.last['name_league'], 'ナ・リーグ');
  });

  test('移籍選手の球団とリーグ・地区を同じ順に併記し成績を合算する', () {
    final data = buildJapaneseMlbStats([
      {'id_player': 1, 'id_team': 20, 'id_league': 4, 'code_area': 'WEST', 'name_team': 'B', 'int_appearance': 30, 'int_batting': 20},
      {'id_player': 1, 'id_team': 10, 'id_league': 3, 'code_area': 'EAST', 'name_team': 'A', 'int_appearance': 50, 'int_batting': 40},
    ], [], 2026);
    final player = (data['players'] as List).single;
    expect(player['name_team'], 'A / B');
    expect(player['name_league'], 'ア・リーグ / ナ・リーグ');
    expect(player['name_area'], '東地区 / 西地区');
    expect(player['id_team'], 10);
    expect(player['stats']['打席'], 80);
  });

  test('規定到達率は打席とアウト数から計算し100%超も表示する', () {
    final data = buildJapaneseMlbStats([
      {'id_player': 1, 'int_pitching': 2, 'double_inning': 1.2, 'int_game': 3},
      {'id_player': 5, 'int_pitching': 4, 'double_inning': 12.1, 'int_game': 10},
      {'id_player': 2, 'int_appearance': 31, 'int_batting': 30, 'int_game': 20},
      {'id_player': 3, 'int_appearance': 100, 'int_batting': 90, 'int_game': 20},
      {'id_player': 4, 'name_player': 'ダルビッシュ有', 'url': 'https://baseball.yahoo.co.jp/mlb/player/2100954/', 'txt_position': '投手', 'int_game': 20},
    ], [], 2026);
    final players = {for (final p in data['players']) p['id_player']: p};
    expect(players[1]['stats']['規定到達率'], '55.6');
    expect(players[2]['stats']['規定到達率'], '50.0');
    expect(players[3]['stats']['規定到達率'], '161.3');
    expect(players[5]['stats']['規定到達率'], '123.3');
    expect(players[4]['pitching'], true);
    expect((players[4]['stats'] as Map).values.every((v) => v == null), true);
  });

  test('ヌートバーは国籍によらず表示し同じURLの略称を統合する', () {
    final data = buildJapaneseMlbStats([
      {'id_player': 1, 'name_player': 'ラーズ・ヌートバー', 'id_team': 38, 'url': 'https://baseball.yahoo.co.jp/mlb/player/2102188/', 'int_appearance': 334, 'int_batting': 285},
    ], [
      {'id_player': 2, 'name_player': 'L.ヌートバー', 'id_team': 38, 'url': 'https://baseball.yahoo.co.jp/mlb/player/2102188/', 'id_league': 4, 'flg_japan': false, 'title': 'OPS', 'stats': '.721'},
    ], 2026);
    expect(data['players'], hasLength(1));
    expect(data['players'].single['stats']['OPS'], '.721');
  });

  test('野手の投手ランキング行が存在しても投手一覧に含めない', () {
    final result = buildJapaneseMlbStats([
      {'id_player': 1, 'name_player': '野手', 'txt_position': '外野手', 'int_appearance': 200, 'int_batting': 180, 'int_pitching': 0},
      {'id_player': 2, 'name_player': '投手', 'txt_position': '投手', 'int_pitching': 20},
    ], [
      for (final id in [1, 2])
        {'id_player': id, 'id_league': 3, 'flg_japan': true, 'flg_pitcher': true, 'title': '防御率', 'stats': '0.00'},
    ], 2026);
    final players = result['players'] as List;
    expect(players.where((p) => p['pitching'] == true).map((p) => p['id_player']), [2]);
    expect(players.where((p) => p['pitching'] == false).map((p) => p['id_player']), [1]);
  });

  test('少打席の投手を野手一覧から除き、二刀流と少打席の野手を残す', () {
    final result = buildJapaneseMlbStats([
      {'id_player': 1, 'name_player': '投手', 'txt_position': '投手', 'int_pitching': 20, 'int_appearance': 3, 'int_batting': 2},
      {'id_player': 2, 'name_player': '二刀流', 'txt_position': '投手', 'int_pitching': 10, 'int_appearance': 100, 'int_batting': 90},
      {'id_player': 3, 'name_player': '野手', 'txt_position': '投手', 'int_appearance': 5, 'int_batting': 4},
    ], [], 2026);
    final players = result['players'] as List;
    expect(players.where((p) => p['pitching'] == false).map((p) => p['id_player']), [2, 3]);
    expect(players.where((p) => p['id_player'] == 1 && p['pitching'] == true), hasLength(1));
  });

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
        'int_appearance': 100,
        'int_batting': 8
      },
      {
        'id_player': 1,
        'name_player': '二刀流',
        'name_team': 'B',
        'int_pitching': 3,
        'double_inning': 2.2,
        'int_appearance': 50,
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
    expect(batter['stats']['打席'], 150);
    expect(batter['stats'].containsKey('打率'), false);
    expect(batter['stats'].containsKey('打点'), false);
  });
}
