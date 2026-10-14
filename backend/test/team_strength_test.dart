import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../app/TeamStrength.dart';

const _team = <String, dynamic>{
  'id_team': 7,
  'id_league': 2,
  'name_team': 'ソフトバンク',
  'name_shortest': 'ソ',
  'color_back': 'yellow',
  'color_font': 'black',
};

String _lineupRow(String date, {String first = '8一番', String starter = '山田'}) => '<tr><td>$date</td>${[
      first,
      '4二番',
      '9三番',
      'D四番',
      '3五番',
      '5六番',
      '7七番',
      '2八番',
      '6九番',
      'P$starter',
      'F相手',
    ].map((cell) => '<td>$cell</td>').join()}</tr>';

const _pitching = '''<table>
<tr><th>選手</th><th>登板</th><th>セーブ</th><th>ホールド</th></tr>
<tr><td>山田　太郎</td><td>2</td><td>0</td><td>0</td></tr>
<tr><td><a>中継　投手</a></td><td>4</td><td>0</td><td>2</td></tr>
<tr><td><a>*抑え　投手</a></td><td>4</td><td>3</td><td>0</td></tr>
</table>''';

Map<String, dynamic> _npb(String lineup, {String pitching = _pitching}) => buildNpbTeamStrength(team: _team, year: 2026, lineupHtml: '<table>$lineup</table>', pitchingHtml: pitching, lineupUrl: 'https://sta-men.jp/2026hawks.html', pitchingUrl: 'https://npb.jp/bis/2026/stats/idp1_h.html');

Map<String, dynamic> _mlb({
  List<Map<String, dynamic>>? pitching,
  List<Map<String, dynamic>>? fielding,
}) =>
    buildMlbTeamStrength(
      team: _team,
      year: 2026,
      sourceTeamId: 119,
      pitching: pitching ??
          [
            {
              'team': {'id': 119},
              'player': {'id': 20, 'fullName': '先発投手'},
              'stat': {'gamesStarted': 1, 'gamesPitched': 1}
            }
          ],
      fielding: fielding ??
          [
            {
              'team': {'id': 119},
              'player': {'id': 1, 'fullName': '打者1'},
              'position': {'abbreviation': 'CF'},
              'stat': {'gamesStarted': 1}
            }
          ],
      teamStats: [
        {
          'team': {'id': 119},
          'stat': {'gamesPlayed': 1}
        }
      ],
      schedule: {
        'dates': [
          {
            'games': [
              {
                'gamePk': 1,
                'status': {'abstractGameState': 'Final'},
                'teams': {
                  'home': {
                    'team': {'id': 119}
                  }
                },
                'lineups': {
                  'homePlayers': [
                    for (var i = 1; i <= 9; i++) {'id': i, 'fullName': '打者$i'}
                  ]
                }
              }
            ]
          }
        ]
      },
      sourceUrl: 'https://statsapi.mlb.com/api/v1/schedule',
    );

class _ReadConnection implements Connection {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #execute) {
      throw StateError('Only SELECT allowed');
    }
    final sql = '${invocation.positionalArguments.first}'.trim();
    expect(sql, startsWith('SELECT'));
    expect(sql, contains('FROM t_team_strength'));
    expect(invocation.namedArguments[#parameters], [2026, 'npb']);
    calls++;
    final schema = ResultSchema([]);
    return Future<Result>.value(Result(rows: [
      ResultRow(values: [
        {'id_team': 7, 'name_team': 'ソフトバンク'}
      ], schema: schema),
    ], affectedRows: 1, schema: schema));
  }
}

class _ExistingTableConnection implements Connection {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #execute) {
      throw StateError('Only SELECT allowed');
    }
    final sql = '${invocation.positionalArguments.first}'.trim();
    expect(sql, startsWith('SELECT to_regclass'));
    calls++;
    final schema = ResultSchema([]);
    return Future<Result>.value(Result(rows: [
      ResultRow(values: [true], schema: schema),
    ], affectedRows: 1, schema: schema));
  }
}

void main() {
  test('登録済みテーブルの起動準備ではDDLを実行しない', () async {
    final conn = _ExistingTableConnection();
    await TeamStrength.ensure(conn);
    await TeamStrength.ensure(conn);
    expect(conn.calls, 1);
  });

  test('戦力の初期要求は保存済みテーブルをSELECTするだけ', () async {
    final conn = _ReadConnection();
    final result = await TeamStrength.read(conn, org: 'npb', year: 2026);
    expect(conn.calls, 1);
    expect(result['org'], 'npb');
    expect((result['teams'] as List).single['name_team'], 'ソフトバンク');
  });

  test('NPBスタメン9人を確認できた試合だけを分母にする', () {
    final result = _npb(
      '${_lineupRow('2026/3/27')}${_lineupRow('2026/3/28', first: '8別選手')}'
      '${_lineupRow('2026/3/29', first: '')}${_lineupRow('2025/3/27')}',
    );
    expect(result['game_count'], 2);
    final order = result['batting_order'] as List;
    expect(order, hasLength(9));
    expect(order.first['total'], 2);
    expect(order.first['players'], contains(equals({'name': '一番', 'player_key': 'npb:name:一番', 'count': 1, 'rate': 50.0})));
    final positions = result['positions'] as List;
    expect(positions.firstWhere((row) => row['slot'] == 'DH')['players'], [
      {'name': '四番', 'player_key': 'npb:name:四番', 'count': 2, 'rate': 100.0}
    ]);
    expect(positions.firstWhere((row) => row['slot'] == 'P')['players'], [
      {'name': '山田', 'player_key': 'npb:name:山田太郎', 'count': 2, 'rate': 100.0}
    ]);
  });

  test('NPBの投手氏名と打順・守備の略名は同じ選手キーを保存する', () {
    final result = _npb(_lineupRow('2026/3/27', first: '1山田'));
    final pitcher = ((result['pitchers'] as Map)['starters'] as List).single;
    final batting = ((result['batting_order'] as List).first['players'] as List).single;
    final fielding = ((result['positions'] as List).firstWhere((row) => row['slot'] == 'P')['players'] as List).single;
    expect(pitcher['name'], '山田太郎');
    expect(batting['name'], '山田');
    expect(pitcher['player_key'], 'npb:name:山田太郎');
    expect(batting['player_key'], pitcher['player_key']);
    expect(fielding['player_key'], pitcher['player_key']);
  });

  test('MLBの同じ公式IDは投手・打順・守備で同じ選手キーになる', () {
    final result = _mlb(pitching: [
      {
        'team': {'id': 119},
        'player': {'id': 1, 'fullName': '打者1'},
        'stat': {'gamesStarted': 1, 'gamesPitched': 1}
      }
    ]);
    final pitcher = ((result['pitchers'] as Map)['starters'] as List).single;
    final batting = ((result['batting_order'] as List).first['players'] as List).single;
    final fielding = ((result['positions'] as List).firstWhere((row) => row['slot'] == 'CF')['players'] as List).single;
    expect(pitcher['player_key'], 'mlb:1');
    expect(batting['player_key'], pitcher['player_key']);
    expect(fielding['player_key'], pitcher['player_key']);
  });

  test('既存データへの選手キー付与は全セクションに適用し同姓を混同しない', () {
    final official = parseNpbPitchers(_pitching.replaceFirst('</table>', '<tr><td>山田　次郎</td><td>2</td><td>0</td><td>0</td></tr></table>'));
    expect(() => npbStrengthPlayerAliases(official, ['山田']), throwsStateError);
    final aliases = npbStrengthPlayerAliases(official, ['山田太', '山田次']);
    final payload = <String, dynamic>{
      'org': 'npb',
      'pitchers': {
        'starters': [
          {'name': '山田太郎'},
          {'name': '山田次郎'}
        ]
      },
      'batting_order': [
        {
          'players': [
            {'name': '山田太'},
            {'name': '山田次'}
          ]
        }
      ],
      'positions': [
        {
          'players': [
            {'name': '野手'}
          ]
        }
      ],
    };
    final result = withStrengthPlayerKeys(payload, playerAliases: aliases);
    final starters = (result['pitchers'] as Map)['starters'] as List;
    final batting = (result['batting_order'] as List).single['players'] as List;
    expect(starters[0]['player_key'], batting[0]['player_key']);
    expect(starters[1]['player_key'], batting[1]['player_key']);
    expect(starters[0]['player_key'], isNot(starters[1]['player_key']));
    expect((result['positions'] as List).single['players'].single['player_key'], 'npb:name:野手');
    expect((payload['pitchers'] as Map)['starters'].first.containsKey('player_key'), false);
  });

  test('投手打順と別枠先発の二重計上をしない', () {
    final result = _npb(_lineupRow('2026/3/27', first: '1山田'));
    final positions = result['positions'] as List;
    expect(positions.firstWhere((row) => row['slot'] == 'P')['players'], [
      {'name': '山田', 'player_key': 'npb:name:山田太郎', 'count': 1, 'rate': 100.0}
    ]);
  });

  test('9打者が揃っていても先発投手が欠落した試合があれば更新を止める', () {
    final missingStarter = _lineupRow('2026/3/28').replaceFirst('<td>P山田</td>', '');
    expect(() => _npb('${_lineupRow('2026/3/27')}$missingStarter'), throwsStateError);
  });

  test('別枠先発がなくても打順内の投手が確認できれば採用する', () {
    final result = _npb(_lineupRow('2026/3/27', first: '1山田').replaceFirst('<td>P山田</td>', ''));
    expect(result['lineup_game_count'], 1);
    final starters = (result['pitchers'] as Map)['starters'] as List;
    expect(starters.fold<int>(0, (total, row) => total + row['starts'] as int), result['lineup_game_count']);
  });

  test('同じHTML行の重複を除き、日付が同じ別スタメンは残す', () {
    final first = _lineupRow('2026/3/27');
    final result = _npb('$first$first${_lineupRow('2026/3/27', first: '8別選手')}');
    expect(result['lineup_game_count'], 2);
  });

  test('NPB先発略称は公式の氏名を一意に照合する', () {
    final result = _npb('${_lineupRow('2026/3/27')}${_lineupRow('2026/3/28')}');
    final pitchers = result['pitchers'] as Map;
    expect((pitchers['starters'] as List).single['name'], '山田太郎');
    expect((pitchers['starters'] as List).single['starts'], 2);
    expect((pitchers['closers'] as List).single['name'], '抑え投手');
    expect((pitchers['relievers'] as List).single['name'], '中継投手');
  });

  test('略称が同姓2人に一致する時は推測して登録しない', () {
    final pitching = _pitching.replaceFirst('</table>', '<tr><td><a>山田　次郎</a></td><td>2</td><td>0</td><td>0</td></tr></table>');
    expect(() => _npb(_lineupRow('2026/3/27'), pitching: pitching), throwsStateError);
  });

  test('姓の完全一致を優先し、全角英字の外国人略称も照合する', () {
    const pitching = '''<table>
      <tr><th>選手</th><th>登板</th><th>セーブ</th><th>ホールド</th></tr>
      <tr><td>森　翔平</td><td>1</td><td>0</td><td>0</td></tr>
      <tr><td>森下　暢仁</td><td>1</td><td>0</td><td>0</td></tr>
      <tr><td>Ｅ．ラミレス</td><td>1</td><td>0</td><td>0</td></tr>
      </table>''';
    final result = _npb(
        '${_lineupRow('2026/3/27', starter: '森')}'
        '${_lineupRow('2026/3/28', starter: 'E.ラミレス')}',
        pitching: pitching);
    final pitchers = result['pitchers'] as Map;
    expect((pitchers['starters'] as List).map((row) => row['name']), unorderedEquals(['森翔平', 'Ｅ．ラミレス']));
  });

  test('先発数が公式登板数を超える場合は更新を止める', () {
    expect(() => _npb('${_lineupRow('2026/3/27')}${_lineupRow('2026/3/28')}${_lineupRow('2026/3/29')}'), throwsStateError);
  });

  test('先発救援の兼任と最多セーブ同数を実績で分類する', () {
    final original = {'name': '兼任', 'starts': 2, 'appearances': 5, 'saves': 0, 'holds': 1};
    final result = classifyStrengthPitchers([
      original,
      {'name': '抑えA', 'starts': 0, 'appearances': 4, 'saves': 3, 'holds': 0},
      {'name': '抑えB', 'starts': 0, 'appearances': 4, 'saves': 3, 'holds': 0},
    ]);
    expect((result['starters'] as List).single['name'], '兼任');
    expect((result['relievers'] as List).single['relief_appearances'], 3);
    expect(result['closers'], hasLength(2));
    expect(original.containsKey('relief_appearances'), false);
    expect(classifyStrengthPitchers([original])['closers'], isEmpty);
  });

  test('MLB公式戦とスタメンがあっても投手または守備成績が空なら更新を止める', () {
    expect(_mlb()['lineup_game_count'], 1);
    expect(() => _mlb(pitching: []), throwsStateError);
    expect(() => _mlb(fielding: []), throwsStateError);
  });

  test('MLB投手成績は氏名と登板のある対象球団の行を必須にする', () {
    expect(
        () => _mlb(pitching: [
              {
                'team': {'id': 119},
                'player': {'id': 20, 'fullName': '   '},
                'stat': {'gamesPitched': 1}
              },
              {
                'team': {'id': 119},
                'player': {'id': 21, 'fullName': '登板なし'},
                'stat': {'gamesPitched': 0}
              },
              {
                'team': {'id': 120},
                'player': {'id': 22, 'fullName': '他球団'},
                'stat': {'gamesPitched': 1}
              },
            ]),
        throwsStateError);
  });

  test('MLB守備成績は氏名と守備位置と先発数のある対象球団の行を必須にする', () {
    expect(
        () => _mlb(fielding: [
              {
                'team': {'id': 119},
                'player': {'id': 1},
                'position': {'abbreviation': 'CF'},
                'stat': {'gamesStarted': 1}
              },
              {
                'team': {'id': 119},
                'player': {'id': 2, 'fullName': '途中出場'},
                'position': {'abbreviation': 'CF'},
                'stat': {'gamesStarted': 0, 'gamesPlayed': 1}
              },
              {
                'team': {'id': 119},
                'player': {'id': 3, 'fullName': '位置不明'},
                'position': {'abbreviation': 'INVALID'},
                'stat': {'gamesStarted': 1}
              },
              {
                'team': {'id': 120},
                'player': {'id': 4, 'fullName': '他球団'},
                'position': {'abbreviation': 'CF'},
                'stat': {'gamesStarted': 1}
              },
            ]),
        throwsStateError);
  });

  test('MLB打順は終了試合の9人だけ、守備位置は公式先発数を使う', () {
    Map<String, dynamic> game(int id, String state, int length) => {
          'gamePk': id,
          'status': {'abstractGameState': state},
          'teams': {
            'home': {
              'team': {'id': 119}
            }
          },
          'lineups': {
            'homePlayers': [
              for (var i = 1; i <= length; i++) {'id': i, 'fullName': '打者$i'}
            ]
          },
        };
    final result = buildMlbTeamStrength(
      team: {..._team, 'id_league': 4},
      year: 2026,
      sourceTeamId: 119,
      pitching: [
        {
          'team': {'id': 119},
          'player': {'id': 20, 'fullName': '先発投手'},
          'stat': {'gamesStarted': 2, 'gamesPitched': 3, 'saves': 0, 'holds': 0}
        },
        {
          'team': {'id': 119},
          'player': {'id': 21, 'fullName': '野手登板'},
          'stat': {'gamesStarted': 0, 'gamesPitched': 1, 'saves': 0, 'holds': 0}
        },
        {
          'team': {'id': 120},
          'player': {'id': 20, 'fullName': '先発投手'},
          'stat': {'gamesStarted': 20, 'gamesPitched': 20, 'saves': 0, 'holds': 0}
        }
      ],
      pitcherIds: {20},
      fielding: [
        {
          'team': {'id': 119},
          'player': {'id': 1, 'fullName': '打者1'},
          'position': {'abbreviation': 'CF'},
          'stat': {'gamesStarted': 2, 'gamesPlayed': 3}
        }
      ],
      teamStats: [
        {
          'team': {'id': 119},
          'stat': {'gamesPlayed': 3}
        }
      ],
      schedule: {
        'dates': [
          {
            'games': [
              game(1, 'Final', 9),
              game(2, 'Final', 8),
              game(3, 'Preview', 9),
              {
                ...game(4, 'Final', 9),
                'status': {'abstractGameState': 'Final', 'detailedState': 'Cancelled', 'reason': 'Rain'}
              }
            ]
          }
        ]
      },
      sourceUrl: 'https://statsapi.mlb.com/api/v1/schedule',
    );
    expect(result['game_count'], 3);
    expect(result['lineup_game_count'], 1);
    expect(((result['pitchers'] as Map)['relievers'] as List).map((row) => row['name']), ['先発投手']);
    expect(((result['pitchers'] as Map)['starters'] as List).single['starts'], 2);
    expect((result['notes'] as List).any((note) => '$note'.contains('中止（Cancelled）となった1試合')), true);
    expect((result['batting_order'] as List).first['players'], [
      {'name': '打者1', 'player_key': 'mlb:1', 'count': 1, 'rate': 100.0}
    ]);
    final cf = (result['positions'] as List).firstWhere((row) => row['slot'] == 'CF');
    expect(cf['total'], 3);
    expect(cf['players'], [
      {'name': '打者1', 'player_key': 'mlb:1', 'count': 2, 'rate': 66.7}
    ]);
  });
}
