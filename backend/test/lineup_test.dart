import 'package:test/test.dart';

import '../app/Lineup.dart';
import '../app/Value.dart';

Map<String, dynamic> _row({
  required String result,
  required String batter,
  int id = 1,
  int inning = 1,
  bool bottom = false,
  int order = 6,
  int team = 201,
  int home = 202,
  int away = 201,
  String enter = '',
  String exit = '',
  String direction = '',
  String positionFrom = '',
  String positionTo = '',
  bool finePlay = false,
}) {
  return {
    'id': id,
    'id_game': 1,
    'id_team': team,
    'id_team_home': home,
    'id_team_away': away,
    'int_inning': inning,
    'flg_bottom': bottom,
    'int_batting_order': order,
    'cnt_out': 0,
    'code_result': result,
    'code_direction_batting': direction,
    'name_full': batter,
    'name_enter': enter,
    'name_exit': exit,
    'code_position_from': positionFrom,
    'code_position_to': positionTo,
    'flg_fine_play': finePlay,
  };
}

void main() {
  test('代打のあとに打席だけ残る選手は代守になる', () {
    final lineups = battingLineupsOf(
      [
        _row(id: 1, result: Value.CodeGameResult.STRIKE_OUT, batter: 'トリスタン・ピーターズ', inning: 2),
        _row(id: 2, result: Value.CodeGameResult.OUT_FLY, batter: 'トミー・ファム', inning: 6, direction: 'LEFT'),
        _row(
          id: 3,
          result: Value.CodeGameResult.PINCH_HITTER,
          batter: 'トミー・ファム',
          inning: 6,
          enter: 'トミー・ファム',
          exit: 'トリスタン・ピーターズ',
        ),
        _row(id: 4, result: Value.CodeGameResult.OUT_GROUND, batter: 'ブレンドン・ドイル', inning: 8, direction: 'SECOND'),
      ],
      plays: const {},
      pitchers: const {},
    );
    final slot = lineups[1]!.firstWhere((row) => row['order'] == 6);
    final players = (slot['players'] as List).cast<Map<String, dynamic>>();
    expect(players.map((player) => player['name']).toList(), [
      'トリスタン・ピーターズ',
      'トミー・ファム',
      'ブレンドン・ドイル',
    ]);
    expect(players[1]['role'], '代打');
    expect(players[2]['role'], '代守');
  });

  List<Map<String, dynamic>> playersOf(Map<int, List<Map<String, dynamic>>> lineups, int order) {
    final slot = lineups[1]!.firstWhere((row) => row['order'] == order);
    return (slot['players'] as List).cast<Map<String, dynamic>>();
  }

  test('先発の守備交代を同じ選手の代守にしない', () {
    final lineups = battingLineupsOf(
      [
        _row(
          id: 1,
          result: Value.CodeGameResult.STRIKE_OUT,
          batter: 'ダスティン・ハリス',
          order: 2,
          inning: 1,
        ),
        _row(
          id: 2,
          result: Value.CodeGameResult.PINCH_FIELDER,
          batter: '相手打者',
          order: 4,
          team: 202,
          inning: 6,
          bottom: true,
          enter: 'ダスティン・ハリス',
        ),
        _row(
          id: 3,
          result: Value.CodeGameResult.OUT_FLY,
          batter: 'ダスティン・ハリス',
          order: 2,
          inning: 7,
          direction: 'LEFT',
        ),
      ],
      plays: const {},
      pitchers: const {},
    );
    final players = playersOf(lineups, 2);
    expect(players.map((player) => player['name']).toList(), ['ダスティン・ハリス']);
    expect(players.single['role'], '');
  });

  test('打席前の守備交代だけでも先発を代守にしない', () {
    final lineups = battingLineupsOf(
      [
        _row(
          id: 1,
          result: Value.CodeGameResult.PINCH_FIELDER,
          batter: '相手打者',
          order: 1,
          team: 202,
          bottom: true,
          enter: 'ダスティン・ハリス',
        ),
        _row(
          id: 2,
          result: Value.CodeGameResult.STRIKE_OUT,
          batter: 'ダスティン・ハリス',
          order: 2,
          inning: 1,
        ),
      ],
      plays: const {},
      pitchers: const {},
    );
    final players = playersOf(lineups, 2);
    expect(players.map((player) => player['name']).toList(), ['ダスティン・ハリス']);
    expect(players.single['role'], '');
  });

  test('中黒の有無が違う同じ選手を代守として重ねない', () {
    final lineups = battingLineupsOf(
      [
        _row(id: 1, result: Value.CodeGameResult.STRIKE_OUT, batter: 'ダスティン・ハリス', order: 2),
        _row(
          id: 2,
          result: Value.CodeGameResult.OUT_GROUND,
          batter: 'ダスティンハリス',
          order: 2,
          inning: 3,
          direction: 'SECOND',
        ),
      ],
      plays: const {},
      pitchers: const {},
    );
    final players = playersOf(lineups, 2);
    expect(players.map((player) => player['name']).toList(), ['ダスティン・ハリス']);
    expect(players.single['role'], '');
  });

  test('フル名の先発に略称の守備交代を代守として重ねない', () {
    final lineups = battingLineupsOf(
      [
        _row(id: 1, result: Value.CodeGameResult.STRIKE_OUT, batter: 'ジャクソン・メリル', order: 5),
        _row(
          id: 2,
          result: Value.CodeGameResult.PINCH_FIELDER,
          batter: '相手打者',
          order: 3,
          team: 202,
          inning: 8,
          bottom: true,
          enter: 'J.メリル',
          exit: 'ジャクソン・メリル',
        ),
        _row(
          id: 3,
          result: Value.CodeGameResult.CHANGE_POSITION,
          batter: '相手打者',
          order: 4,
          team: 202,
          inning: 8,
          bottom: true,
          enter: 'J.メリル',
          exit: 'ジャクソン・メリル',
        ),
      ],
      plays: const {},
      pitchers: const {},
    );
    final players = playersOf(lineups, 5);
    expect(players.map((player) => player['name']).toList(), ['ジャクソン・メリル']);
    expect(players.single['role'], '');
  });

  test('同姓の先発打者は別の打順枠に残す', () {
    final lineups = battingLineupsOf(
      [
        _row(id: 1, result: Value.CodeGameResult.STRIKE_OUT, batter: 'ブレーデン・モンゴメリー', order: 7),
        _row(id: 2, result: Value.CodeGameResult.WALK_BALL, batter: 'コルソン・モンゴメリー', order: 9),
        _row(id: 3, result: Value.CodeGameResult.STRIKE_OUT, batter: 'コルソン・モンゴメリー', order: 9, inning: 5),
      ],
      plays: const {
        '1|201|ブレーデン・モンゴメリー': '空三振|out',
        '1|201|コルソン・モンゴメリー': '四球|walk 空三振|out',
      },
      pitchers: const {},
    );
    final seventh = playersOf(lineups, 7);
    final ninth = playersOf(lineups, 9);
    expect(seventh.single['name'], 'ブレーデン・モンゴメリー');
    expect(seventh.single['plays'], '空三振|out');
    expect(ninth.single['name'], 'コルソン・モンゴメリー');
    expect(ninth.single['plays'], '四球|walk 空三振|out');
  });

  test('試合中は未打席のスタメンも打順枠に残す', () {
    final lineups = battingLineupsOf(
      [
        _row(id: 1, result: Value.CodeGameResult.HIT_SINGLE, batter: 'スティーブン・クワン', order: 1, team: 202, home: 202, away: 201),
        _row(id: 2, result: Value.CodeGameResult.WALK_BALL, batter: 'ホセ・ラミレス', order: 2, team: 202, home: 202, away: 201),
      ],
      plays: const {
        '1|202|スティーブン・クワン': '右安|single',
      },
      pitchers: const {},
      starters: [
        for (final entry in [
          (1, 'スティーブン・クワン', '中'),
          (2, 'ホセ・ラミレス', '三'),
          (3, 'チェース・デローター', '右'),
          (4, 'ジョ・アデル', '指'),
          (5, 'ナサニエル・ロウ', '一'),
          (6, 'アンヘル・マルティネス', '左'),
          (7, 'トラビス・バザナ', '二'),
          (8, 'パトリック・ベイリー', '捕'),
          (9, 'ブラヤン・ロッキオ', '遊'),
        ])
          {
            'id_game': 1,
            'id_team': 202,
            'name_full': entry.$2,
            'int_batting_order': entry.$1,
            'code_position_from': entry.$3,
          },
      ],
    );
    final names = [
      for (var order = 1; order <= 9; order++) playersOf(lineups, order).first['name'],
    ];
    expect(names, [
      'スティーブン・クワン',
      'ホセ・ラミレス',
      'チェース・デローター',
      'ジョ・アデル',
      'ナサニエル・ロウ',
      'アンヘル・マルティネス',
      'トラビス・バザナ',
      'パトリック・ベイリー',
      'ブラヤン・ロッキオ',
    ]);
    expect(playersOf(lineups, 4).single['pos'], '指');
    expect(playersOf(lineups, 1).single['plays'], '右安|single');
    expect(playersOf(lineups, 9).single['plays'], '');
  });

  test('守備変更の代守は投手の9番でなく外れた野手の打順に載せる', () {
    final lineups = battingLineupsOf(
      [
        _row(
          id: 1,
          result: Value.CodeGameResult.STRIKE_OUT,
          batter: '佐藤輝明',
          order: 4,
          team: 202,
          home: 202,
          away: 201,
          bottom: true,
        ),
        _row(
          id: 2,
          result: Value.CodeGameResult.PINCH_FIELDER,
          batter: '坂倉将吾',
          order: 4,
          team: 201,
          home: 202,
          away: 201,
          inning: 8,
          bottom: false,
          enter: '小野寺暖',
          exit: '木下',
        ),
        _row(
          id: 3,
          result: Value.CodeGameResult.OUT_GROUND,
          batter: '小野寺暖',
          order: 4,
          team: 202,
          home: 202,
          away: 201,
          inning: 8,
          bottom: true,
          direction: 'SS',
        ),
      ],
      plays: const {
        '1|202|佐藤輝明': '空三振|out',
        '1|202|小野寺暖': '遊ゴロ|out',
      },
      pitchers: const {'1|202|木下'},
    );
    final fourth = lineups[1]!.firstWhere((row) => row['order'] == 4 && row['id_team'] == 202);
    final players = (fourth['players'] as List).cast<Map<String, dynamic>>();
    expect(players.map((player) => player['name']).toList(), ['佐藤輝明', '小野寺暖']);
    expect(players.last['role'], '代守');
    expect(
      lineups[1]!.any(
        (row) =>
            row['order'] == 9 &&
            row['id_team'] == 202 &&
            (row['players'] as List).any((player) => '${player['name']}'.contains('小野寺')),
      ),
      isFalse,
    );
  });

  test('投手交代直後の代守だけでも9番枠に載せない', () {
    final lineups = battingLineupsOf(
      [
        _row(
          id: 1,
          result: Value.CodeGameResult.STRIKE_OUT,
          batter: '佐藤輝明',
          order: 4,
          team: 202,
          home: 202,
          away: 201,
          bottom: true,
        ),
        _row(
          id: 2,
          result: Value.CodeGameResult.PINCH_FIELDER,
          batter: '坂倉将吾',
          order: 4,
          team: 201,
          home: 202,
          away: 201,
          inning: 8,
          bottom: false,
          enter: '小野寺暖',
          exit: '木下',
        ),
      ],
      plays: const {},
      pitchers: const {'1|202|木下'},
    );
    final namesOnNine = [
      for (final row in lineups[1]!.where((row) => row['order'] == 9 && row['id_team'] == 202))
        for (final player in (row['players'] as List)) player['name'],
    ];
    expect(namesOnNine, isNot(contains('小野寺暖')));
  });

  test('代守は入った守備位置を持ち、失策とファインプレーは守備側に付く', () {
    final lineups = battingLineupsOf(
      [
        _row(
          id: 1,
          result: Value.CodeGameResult.STRIKE_OUT,
          batter: '源田壮亮',
          order: 2,
          team: 201,
          home: 202,
          away: 201,
          positionFrom: 'SS',
        ),
        _row(
          id: 2,
          result: Value.CodeGameResult.ERROR_FIELDING,
          batter: '佐藤輝明',
          order: 4,
          team: 202,
          home: 202,
          away: 201,
          bottom: true,
          inning: 3,
          direction: 'SS',
        ),
        _row(
          id: 3,
          result: Value.CodeGameResult.PINCH_FIELDER,
          batter: '佐藤輝明',
          order: 4,
          team: 202,
          home: 202,
          away: 201,
          bottom: true,
          inning: 7,
          enter: '外崎修汰',
          exit: '源田壮亮',
          positionTo: 'SS',
        ),
        _row(
          id: 4,
          result: Value.CodeGameResult.OUT_FLY,
          batter: '近本光司',
          order: 1,
          team: 202,
          home: 202,
          away: 201,
          bottom: true,
          inning: 8,
          direction: 'SS',
          finePlay: true,
        ),
      ],
      plays: const {},
      pitchers: const {},
    );
    final players = playersOf(lineups, 2);
    expect(players.first['pos'], '遊');
    expect(players.first['field_marks'], 'E');
    expect(players.last['name'], '外崎修汰');
    expect(players.last['role'], '代守');
    expect(players.last['pos'], '遊');
    expect(players.last['field_marks'], 'FP');
  });
}
