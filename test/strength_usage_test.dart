import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/strength_usage.dart';

void main() {
  test('カード色は1軍支配下・2軍支配下・2軍育成・その他の順に淡くなる', () {
    double tint(String registration, Map<String, int> levels) =>
        rosterCardTint({
          'registration': registration,
          'level_appearances': levels,
        });
    final colors = [
      tint('支配下', {'1': 50, '2': 10}),
      tint('支配下', {'1': 10, '2': 50}),
      tint('育成', {'2': 50}),
      tint('育成', {'3': 50})
    ];
    for (var i = 0; i < colors.length - 1; i++) {
      expect(colors[i], greaterThan(colors[i + 1]));
    }
    expect(tint('支配下', {}), colors.last);
    expect(tint('支配下', {'1': 0, '2': 0}), colors.last);
    expect(tint('支配下', {'1': 10, '2': 10}), colors.first);
  });

  test('一覧はDHを除外して守備起用が最多の位置に配置する', () {
    final team = <String, dynamic>{
      'positions': [
        for (final entry in [('DH', 100), ('1B', 20), ('LF', 5)])
          {
            'slot': entry.$1,
            'players': [
              {'player_key': '1', 'count': entry.$2}
            ]
          },
      ]
    };
    expect(rosterPosition({'player_key': '1', 'position_group': '内野手'}, team),
        '一塁');
    expect(rosterPosition({'player_key': '2', 'position_group': '外野手'}, team),
        '右翼');
    expect(rosterPosition({'player_key': '3', 'position_group': '指名打者'}, team),
        '守備位置未確認');
  });

  test('下部組織の起用は2軍→3軍→4軍の順に確認し不明時のみ指定列へ置く', () {
    final team = <String, dynamic>{};
    Map<String, dynamic> player(String group, Map<String, dynamic> lower) =>
        {'position_group': group, 'lower_level_usage': lower};
    final starter = player('投手', {
      '2': {'starts': 8, 'relief': 2}
    });
    expect(rosterPosition(starter, team), '先発');
    expect(rosterUsageUnknown(starter, team), false);
    expect(
        rosterPosition(
            player('投手', {
              '3': {'starts': 1, 'relief': 5}
            }),
            team),
        '中継ぎ');
    expect(
        rosterPosition(
            player('投手', {
              '4': {'starts': 3, 'relief': 1}
            }),
            team),
        '先発');
    expect(
        rosterPosition(
            player('外野手', {
              '4': {
                'positions': {'LF': 4, 'CF': 7}
              }
            }),
            team),
        '中堅');
    expect(
        rosterPosition(
            player('内野手', {
              '3': {
                'positions': {'SS': 5}
              }
            }),
            team),
        '遊撃');
    for (final entry in {'投手': '中継ぎ', '外野手': '右翼', '内野手': '一塁'}.entries) {
      final unknown = player(entry.key, {});
      expect(rosterPosition(unknown, team), entry.value);
      expect(rosterUsageUnknown(unknown, team), true);
    }
    expect(
        rosterUsageUnknown(
            player('内野手', {
              '4': {
                'positions': {'SS': 5}
              }
            }),
            team),
        true);
    expect(
        rosterPosition(
            player('外野手', {
              '2': {
                'positions': {'LF': 2}
              },
              '3': {
                'positions': {'CF': 20}
              }
            }),
            team),
        '左翼');
  });

  test('レギュラー名は同姓でも選手IDが一致する名簿のフルネームを表示する', () {
    final roster = [
      {'player_key': 'npb:1', 'name': '坂本勇人'},
      {'player_key': 'npb:2', 'name': '坂本誠志郎'},
    ];
    expect(regularPlayerName({'player_key': 'npb:1', 'name': '坂本勇'}, roster),
        '坂本勇人');
    expect(regularPlayerName({'player_key': 'npb:2', 'name': '坂本'}, roster),
        '坂本誠志郎');
    expect(regularPlayerName({'name': '坂本'}, roster), '坂本');
    expect(regularPlayerName({'name': '大谷', 'full_name': '大谷翔平'}, []), '大谷翔平');
  });

  test('レギュラー追加は最多スタメン数の70%以上で投手を除外し重複させない', () {
    Map<String, dynamic> group(String slot, List<(String, int)> players) => {
          'slot': slot,
          'total': 200,
          'players': [
            for (final p in players) {'name': p.$1, 'count': p.$2}
          ],
        };
    final result = selectRegularGroups([
      group('P', [('A', 200)]),
      group('C', [('A', 100), ('B', 70), ('C', 69)]),
      group('DH', [('D', 100), ('B', 80), ('E', 70)]),
      group('1B', [('F', 100), ('D', 80)]),
    ]);
    expect(result.containsKey('P'), isFalse);
    expect(result['C']!.map((p) => p['name']), ['A']);
    expect(result['DH']!.map((p) => p['name']), ['D', 'B', 'E']);
    expect(result['1B']!.map((p) => p['name']), ['F']);
    expect(
        result.values.expand((p) => p).any((p) => p['name'] == 'C'), isFalse);
  });

  test('守備重複は高い起用率に割り当て、使用済みの第2・第3候補を飛ばす', () {
    Map<String, dynamic> group(String slot, List<(String, int)> players) => {
          'slot': slot,
          'total': 100,
          'players': [
            for (final p in players)
              {'player_key': p.$1, 'name': p.$1, 'count': p.$2}
          ]
        };
    final selected = selectRegulars([
      group('SS', [('A', 70), ('B', 20)]),
      group('2B', [('A', 30), ('B', 25), ('C', 20), ('D', 15)]),
      group('3B', [('B', 80)]),
      group('1B', [('C', 90)]),
    ]);
    expect(selected['SS']!['name'], 'A');
    expect(selected['3B']!['name'], 'B');
    expect(selected['1B']!['name'], 'C');
    expect(selected['2B']!['name'], 'D');
  });
  test('守備位置ごとの分母が異なる場合も回数でなく率で選ぶ', () {
    final result = selectRegulars([
      {
        'slot': 'C',
        'total': 10,
        'players': [
          {'name': 'A', 'count': 8}
        ]
      },
      {
        'slot': 'DH',
        'total': 100,
        'players': [
          {'name': 'A', 'count': 60},
          {'name': 'B', 'count': 30}
        ]
      },
    ]);
    expect(result['C']!['name'], 'A');
    expect(result['DH']!['name'], 'B');
  });
  test('先発と救援の負担率はチーム総アウト数を共通分母にする', () {
    final result = pitchingWorkloadBands([
      {
        'name': '兼任',
        'player_key': '1',
        'starter_outs': 19,
        'relief_outs': 2,
        'total_outs': 21
      },
      {
        'name': '救援',
        'player_key': '2',
        'starter_outs': 0,
        'relief_outs': 6,
        'total_outs': 6
      },
    ]);
    expect(result.map((p) => p['total']), [27, 27]);
    expect(result.map((p) => p['role_outs']), [19, 8]);
    expect(inningsLabel(19), '6 1/3回');
    expect(inningsLabel(2), '0 2/3回');
  });
  test('出場数が最も多い軍を表示する', () {
    expect(
        rosterLevel({
          'level_appearances': {'1': 5, '2': 40},
          'level_coverage': [1, 2]
        }),
        '2軍中心');
    expect(
        rosterLevel({
          'level_appearances': {'1': 5, '2': 40, '3': 42, '4': 0},
          'level_coverage': [1, 2, 3, 4]
        }),
        '3軍中心');
  });
  test('野手の一時登板は一覧の投手役割へ移さない', () {
    final team = <String, dynamic>{
      'pitching_workload': [
        {
          'player_key': '1',
          'starter_outs': 0,
          'relief_outs': 3,
          'total_outs': 3
        }
      ],
      'positions': [
        {
          'slot': '1B',
          'total': 100,
          'players': [
            {'player_key': '1', 'count': 90}
          ]
        }
      ]
    };
    expect(rosterPosition({'player_key': '1', 'position_group': '内野手'}, team),
        '一塁');
  });
}
