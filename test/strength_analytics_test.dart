import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/strength_analytics.dart';
import 'package:Yakyuu_Japan/logic/display_settings.dart';
import 'package:Yakyuu_Japan/View/strength_contracts.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/pages/display_settings_page.dart';

void main() {
  testWidgets('MLB生涯年俸は為替未確認でも全ドル年俸をドル札で表示する', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthContracts(year: 2026, team: {
      'id_team': 13,
      'id_league': 3,
      'org': 'mlb',
      'name_team': '球団A',
      'contracts': [
        {
          'player_key': 'a',
          'name': '選手A',
          'salary_history': [
            for (var year = 2024; year <= 2027; year++) {'year': year, 'amount': 15000000, 'currency': 'USD'}
          ]
        }
      ]
    }))));
    await tester.pumpAndSettle();
    final finder = find.byKey(const ValueKey('career-money-13-a'));
    final bar = tester.widget<SalaryMoneyBar>(finder);
    expect(bar.currency, 'USD');
    expect(bar.amount, 45000000);
    expect(bar.wrapAt, 20000000);
    expect(find.descendant(of: finder, matching: find.byType(CustomPaint)), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('MLB総年俸はア・リーグ上段、ナ・リーグ下段で共通尺度', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TeamSalaryChart(year: 2026, teams: [
      for (var id = 1; id <= 4; id++)
        {
          'id_team': id,
          'id_league': id.isOdd ? 4 : 3,
          'name_team': '球団$id',
          'contracts': [
            {
              'player_key': '$id',
              'salary_history': [
                {'year': 2026, 'amount': id * 10000000, 'currency': 'USD'}
              ]
            }
          ]
        }
    ]))));
    final al = find.byKey(const ValueKey('team-salary-bar-2-USD'));
    final nl = find.byKey(const ValueKey('team-salary-bar-1-USD'));
    expect(tester.getTopLeft(find.text('ア・リーグ')).dy, lessThan(tester.getTopLeft(find.text('ナ・リーグ')).dy));
    expect(tester.getTopLeft(al).dy, lessThan(tester.getTopLeft(nl).dy));
    expect(tester.widget<VerticalSalaryMoneyBar>(al).maximum, 40000000);
    expect(tester.widget<VerticalSalaryMoneyBar>(nl).maximum, 40000000);
    expect(find.byType(VerticalSalaryMoneyBar), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('球団別総年俸図は比較モードのみ表示する', (tester) async {
    final team = <String, dynamic>{'id_team': 1, 'name_team': '球団A', 'contracts': []};
    Widget screen(bool compare) => MaterialApp(home: Scaffold(body: StrengthContracts(team: team, year: 2026, colorTeams: [team], comparisonTeams: compare ? [team] : null)));
    await tester.pumpWidget(screen(false));
    await tester.pumpAndSettle();
    expect(find.byType(TeamSalaryChart), findsNothing);
    await tester.pumpWidget(screen(true));
    await tester.pumpAndSettle();
    expect(find.byType(TeamSalaryChart), findsOneWidget);
    await tester.pumpWidget(screen(false));
    await tester.pumpAndSettle();
    expect(find.byType(TeamSalaryChart), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('円換算のMLB年俸も当時の所属でドル札にする', () {
    for (final team in ['ヤンキース', 'NYY', 'レイズ → ドジャース → パイレーツ']) {
      expect(salaryBanknoteCurrency({'team': team, 'currency': 'JPY'}), 'USD');
    }
    expect(salaryBanknoteCurrency({'team': '阪神', 'currency': 'JPY'}), 'JPY');
    expect(salaryBanknoteCurrency({'team': '巨人', 'currency': 'JPY'}), 'JPY');
    expect(salaryBanknoteCurrency({'currency': 'USD'}), 'USD');
  });
  testWidgets('NPB復帰選手の過去MLB年は金額を円のままドル札で描く', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: StrengthContracts(year: 2026, team: {
      'id_team': 1,
      'name_team': '巨人',
      'contracts': [
        {
          'player_key': 'a',
          'name': '選手A',
          'salary_history': [
            {'year': 2024, 'team': 'ヤンキース', 'amount': 500000000, 'currency': 'JPY'},
            {'year': 2026, 'team': '巨人', 'amount': 100000000, 'currency': 'JPY'},
          ]
        }
      ]
    }))));
    await tester.pumpAndSettle();
    final bars = tester.widgetList<SalaryMoneyBar>(find.byType(SalaryMoneyBar));
    final historical = bars.singleWhere((bar) => bar.banknoteCurrency == 'USD');
    expect(historical.amount, 500000000);
    expect(historical.currency, 'JPY');
    expect(historical.wrapAt, 500000000);
    expect(bars.any((bar) => bar.banknoteCurrency == 'JPY'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('総年俸は共通尺度の札束グラフで金額に比例する', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TeamSalaryChart(year: 2026, teams: [
      for (var id = 1; id <= 2; id++)
        {
          'id_team': id,
          'name_team': '球団$id',
          'color_back': '#123456',
          'contracts': [
            {
              'player_key': '$id',
              'salary_history': [
                {'year': 2026, 'amount': id * 100000000}
              ]
            }
          ]
        }
    ]))));
    final small = find.byKey(const ValueKey('team-salary-bar-1-JPY'));
    final large = find.byKey(const ValueKey('team-salary-bar-2-JPY'));
    final smallPaint = find.descendant(of: small, matching: find.byType(CustomPaint));
    final largePaint = find.descendant(of: large, matching: find.byType(CustomPaint));
    expect(tester.getSize(smallPaint).height * 2, closeTo(tester.getSize(largePaint).height, .01));
    expect(tester.widget<VerticalSalaryMoneyBar>(small).currency, 'JPY');
    expect(tester.widget<VerticalSalaryMoneyBar>(small).maximum, 200000000);
    expect(tester.getBottomLeft(smallPaint).dy, tester.getBottomLeft(largePaint).dy);
    expect(tester.getTopLeft(largePaint).dy, lessThan(tester.getTopLeft(smallPaint).dy));
    expect(find.text('1.0億円'), findsOneWidget);
    expect(find.text('2.0億円'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('球団総年俸は選択年度だけを選手重複なし・通貨別で集計する', () {
    final p = {
      'player_key': 'a',
      'salary_history': [
        {'year': 2025, 'amount': 900000000},
        {'year': 2026, 'amount': 100000000},
      ]
    };
    final rows = teamSalaryTotals([
      {
        'id_team': 1,
        'contracts': [
          p,
          p,
          {
            'player_key': 'b',
            'salary_history': [
              {'year': 2026, 'amount': 200000000}
            ]
          },
          {
            'player_key': 'c',
            'salary_history': [
              {'year': 2026, 'amount': 1000000, 'currency': 'USD'}
            ]
          },
        ]
      },
      {'id_team': 2, 'contracts': []},
    ], 2026);
    expect(rows.first['totals'], {'JPY': 300000000, 'USD': 1000000});
    expect(rows.first['count'], 3);
    expect(rows.last['totals'], isEmpty);
  });

  test('年俸がなくても年度別の所属から球団色の帯を作る', () {
    final bands = contractTimelineBands([], [], [
      {'year': 2022, 'team': 'NYY'},
      {'year': 2023, 'team': 'NYY'},
      {'year': 2024, 'team': 'NYM'},
    ]);
    expect(bands.length, 3);
    expect(bands.last['team'], 'NYM');
    expect(bands.last['start_year'], 2024);
    expect(bands.last['end_year'], 2024);
  });

  test('生涯年俸は過去の確認済みレートだけ円換算する', () {
    final total = careerSalaryYen([
      {'year': 2024, 'amount': 2100000000},
      {'year': 2025, 'amount': 1000000, 'currency': 'USD', 'usd_jpy_rate': 150},
      {'year': 2026, 'amount': 1000000, 'currency': 'USD'},
      {'year': 2027, 'amount': 5000000000},
    ], 2026);
    expect(total.yen, 2250000000);
    expect(total.missing, 1);
    expect(salaryBarRows(total.yen, 2000000000), 2);
  });

  testWidgets('札束はNPB5億円・MLB2000万ドルごとに折り返す', (tester) async {
    expect(salaryWrapAmount('JPY'), 500000000);
    expect(salaryWrapAmount('USD'), 20000000);
    expect(salaryBarRows(500000000, 500000000), 1);
    expect(salaryBarRows(500000001, 500000000), 2);
    for (final currency in ['JPY', 'USD']) {
      final limit = salaryWrapAmount(currency);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 200, child: SalaryMoneyBar(amount: limit * 2 + limit ~/ 2, maximum: limit, wrapAt: limit, currency: currency)))));
      final paints = find.descendant(of: find.byType(SalaryMoneyBar), matching: find.byType(CustomPaint));
      expect(paints, findsNWidgets(3));
      expect(tester.getSize(paints.at(0)).width, 200);
      expect(tester.getSize(paints.at(2)).width, 100);
      expect(tester.getTopLeft(paints.at(1)).dy - tester.getTopLeft(paints.at(0)).dy, 32);
      expect(tester.takeException(), isNull);
    }
  });

  test('生涯年俸は選択年度までの年俸のみ通貨別に合計する', () {
    expect(
        careerSalaryLabel([
          {'year': 2024, 'amount': 100000000},
          {'year': 2026, 'amount': 50000000},
          {'year': 2027, 'amount': 900000000},
          {'year': 0, 'amount': 900000000},
        ], 2026),
        '1.5億円');
    expect(careerSalaryLabel([], 2026), '未確認');
    expect(
        careerSalaryLabel([
          {'year': 2025, 'amount': 10000000, 'currency': 'USD'},
          {'year': 2026, 'amount': 4285000, 'currency': 'USD'},
        ], 2026),
        '1428.5万ドル');
  });

  test('ドルは億・万表記で契約時レートの円換算を併記する', () {
    expect(salaryAmount(7050000000, 'USD'), '70.5億ドル');
    expect(salaryAmount(14285000, 'USD'), '1428.5万ドル');
    expect(salaryAmount(100000000, 'USD'), '10000.0万ドル');
    expect(contractSalaryLabel({'amount': 14285000, 'currency': 'USD', 'usd_jpy_rate': 150}), '1428.5万ドル（約21.4億円）');
    expect(contractSalaryLabel({'amount': 14285000, 'currency': 'USD'}), '1428.5万ドル（円換算未確認）');
  });

  test('過去年俸の確認年を補い、既知の契約期間や履歴の空白を変更しない', () {
    final periods = <Map<String, dynamic>>[
      {'start_year': 2024, 'end_year': 2026, 'team': '現球団'},
      {'period': '終了年未確認', 'start_year': 2027},
    ];
    final bands = contractTimelineBands(periods, [
      {'year': 2020, 'team': '前球団'},
      {'year': 2020, 'team': '前球団'},
      {'year': 2022, 'team': '前球団'},
      {'year': 2025, 'team': '現球団'},
      {'year': 0},
    ]);
    expect(bands.length, 4);
    expect(bands.first, periods.first);
    expect(bands[1]['start_year'], 2020);
    expect(bands[1]['end_year'], 2020);
    expect(bands[1]['team'], '前球団');
    expect(bands[1]['annual_evidence'], true);
    expect(bands[2]['start_year'], 2022);
    expect(periods.length, 2);
    expect(contractTimelineBands([], []), isEmpty);
  });

  testWidgets('複数年契約のない過去年にも所属球団色の帯と年俸を表示する', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: StrengthContracts(
      year: 2020,
      team: {
        'id_team': 1,
        'name_team': '現球団',
        'contracts': [
          {
            'player_key': 'a',
            'name': '選手A',
            'periods': [],
            'salary_history': [
              {'year': 2020, 'amount': 10000000, 'team': '前球団'},
              {'year': 2022, 'amount': 20000000, 'team': '現球団'},
            ]
          }
        ],
      },
      colorTeams: [
        {'name_team': '前球団', 'color_back': '#123456'},
        {'name_team': '現球団', 'color_back': '#654321'},
      ],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('2020 前球団'), findsOneWidget);
    expect(find.text('2022 現球団'), findsOneWidget);
    expect(find.text('期間未確認'), findsNothing);
    expect(find.byType(SalaryMoneyBar), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
  test('億円表記は小数第1位まで切り捨て、所属球団の色を照合する', () {
    expect(salaryAmount(1069999999, 'JPY'), '10.6億円');
    expect(salaryAmount(100000000, 'JPY'), '1.0億円');
    expect(salaryAmount(999999999, 'JPY'), '9.9億円');
    expect(salaryAmount(95000000, 'JPY'), '9500万円');
    final teams = <Map<String, dynamic>>[
      {'name_team': '前球団', 'color_back': '#123456'},
      {'name_team': '現球団', 'name_shortest': 'ABC', 'color_back': '#654321'},
    ];
    expect(contractTeamColor({'team': '前球団'}, teams), const Color(0xFF123456));
    expect(contractTeamColor({'team': 'ABC'}, teams), const Color(0xFF654321));
    expect(contractTeamColor({'team': '未確認'}, teams), Colors.blueGrey);
  });
  testWidgets('契約の金額は札束の上に置き所属していた球団色で帯を描く', (tester) async {
    final current = <String, dynamic>{
      'id_team': 1,
      'name_team': '現球団',
      'color_back': '#654321',
      'contracts': [
        {
          'player_key': 'a',
          'name': '選手A',
          'periods': [
            {'start_year': 2025, 'end_year': 2026, 'team': '前球団'}
          ],
          'salary_history': [
            {'year': 2026, 'amount': 1069999999}
          ]
        }
      ]
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthContracts(team: current, year: 2026, colorTeams: [
      current,
      const {'name_team': '前球団', 'color_back': '#123456'}
    ]))));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.info_outline), findsNothing);
    final nameCell = tester.widget<Container>(find.byKey(const ValueKey('contract-name-1-a')));
    expect(nameCell.color, const Color(0xFF654321));
    final careerCell = tester.widget<Container>(find.byKey(const ValueKey('career-salary-1-a')));
    expect((careerCell.decoration as BoxDecoration).color, Color.lerp(const Color(0xFF654321), Colors.white, .85));

    expect(tester.getTopLeft(find.byKey(const ValueKey('career-salary-1-a'))).dx, tester.getTopRight(find.byKey(const ValueKey('contract-name-1-a'))).dx);
    final careerBar = tester.widget<SalaryMoneyBar>(find.byKey(const ValueKey('career-money-1-a')));
    expect(careerBar.wrapAt, 2000000000);

    expect(find.text('生涯年俸'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('career-salary-1-a')), matching: find.text('10.6億円')), findsOneWidget);
    final amount = tester.getRect(find.descendant(of: find.byKey(const ValueKey('contract-player-1-a')), matching: find.text('10.6億円')).first);
    final graph = tester.getRect(find.descendant(of: find.byKey(const ValueKey('contract-player-1-a')), matching: find.byType(SalaryMoneyBar)).first);
    expect(amount.bottom, lessThanOrEqualTo(graph.top));
    final band = find.ancestor(of: find.text('2025–2026 前球団'), matching: find.byType(Container)).first;
    expect((tester.widget<Container>(band).decoration as BoxDecoration).color, const Color(0xFF123456));
    expect(tester.getSize(find.byKey(const ValueKey('contract-player-1-a'))).height, lessThan(170));
    expect(tester.takeException(), isNull);
  });

  test('途中出場レギュラーは重複を除外し選出首位の70%以上を追加する', () {
    final team = <String, dynamic>{
      'roster': [
        for (final id in ['regular', 'left', 'extra', 'low']) {'player_key': id, 'name': id, 'bats': '左'},
        {'player_key': 'right', 'bats': '右'}
      ],
      'substitutions': [
        {
          'slot': 'PH',
          'total': 100,
          'players': [
            {'player_key': 'regular', 'count': 50},
            {'player_key': 'left', 'count': 20},
            {'player_key': 'extra', 'count': 14},
            {'player_key': 'low', 'count': 13},
            {'player_key': 'right', 'count': 10}
          ]
        },
        {
          'slot': 'PR',
          'total': 40,
          'players': [
            {'player_key': 'regular', 'count': 30},
            {'player_key': 'left', 'count': 10},
            {'player_key': 'runner', 'count': 9}
          ]
        }
      ],
      'defense_substitutions': [
        {
          'slot': 'DEF_IF',
          'total': 10,
          'players': [
            {'player_key': 'infielder', 'count': 10}
          ]
        },
        {
          'slot': 'DEF_OF',
          'total': 11,
          'players': [
            {'player_key': 'outfielder', 'count': 11}
          ]
        }
      ]
    };
    final result = selectBenchRegulars(team, {
      'C': [
        {'player_key': 'regular'}
      ]
    });
    expect(result['PH_L']!.map((p) => p['player_key']), ['left', 'extra']);
    expect(result['PH_R']!.single['player_key'], 'right');
    expect(result['PR']!.single['player_key'], 'runner');
    expect(result['DEF_IF']!.single['player_key'], 'infielder');
    expect(result['DEF_OF']!.single['player_key'], 'outfielder');
  });

  test('略称と異体字は球団内の一意な選手にだけ照合する', () {
    final roster = [
      {'player_key': 'npb:1', 'name': '廣瀨隆太'}
    ];
    final team = {
      'roster': roster,
      'batting_stats': [
        {'player_key': 'npb:1', 'ops': .649, 'home_runs': 1}
      ]
    };
    final player = {'player_key': 'npb:name:廣瀬隆', 'name': '廣瀬隆'};
    expect(strengthPlayerMetrics(team, player)['ops'], .649);
    roster.add({'player_key': 'npb:2', 'name': '廣瀨隆一'});
    expect(strengthPlayerMetrics(team, player)['ops'], isNull);
  });
  test('OPSは小数点の前の0だけを省き、1以上と未登録を保持する', () {
    expect(opsValue(0.850), '.850');
    expect(opsValue(0), '.000');
    expect(opsValue(1.025), '1.025');
    expect(opsValue(null), '—');
    expect(battingMetricLabel({'ops': 0.85, 'home_runs': 12}), 'OPS .850  12本');
  });
  test('塁打貢献は打撃結果ごとの塁打数と四球を合計する', () {
    final bands = contributionBands({
      'batting_stats': [
        {'player_key': 'a', 'name': 'A', 'home_runs': 2, 'triples': 1, 'doubles': 3, 'singles': 5, 'walks': 4, 'total_bases_walks': 26, 'rbi': 7}
      ]
    });
    expect(bands[1]['total'], 26);
    expect((bands[1]['players'] as List).single['parts'].map((p) => p['count']).toList(), [8, 3, 6, 5, 4]);
  });
  test('左右の投球回・打席は実数で集計し両打と不明を保持する', () {
    final team = {
      'roster': [
        {'player_key': 'a', 'throws': '左', 'bats': '両'},
        {'player_key': 'b', 'throws': '右', 'bats': '右'}
      ],
      'pitching_workload': [
        {'player_key': 'a', 'total_outs': 30},
        {'player_key': 'b', 'total_outs': 60}
      ],
      'batting_stats': [
        {'player_key': 'a', 'pa': 40},
        {'player_key': 'b', 'pa': 60}
      ]
    };
    expect(handednessBand(team, pitching: true)['total'], 90);
    expect((handednessBand(team, pitching: false)['players'] as List).first['name'], '両打');
  });
  test('エースは左右と役割を分けて選び守護神をリリーフから除く', () {
    final team = {
      'roster': [
        for (final id in ['s', 'r', 'c']) {'player_key': id, 'throws': '左'}
      ],
      'pitching_workload': [
        {'player_key': 's', 'starter_outs': 300, 'relief_outs': 0},
        {'player_key': 'r', 'starter_outs': 0, 'relief_outs': 120, 'holds': 20},
        {'player_key': 'c', 'starter_outs': 0, 'relief_outs': 180, 'holds': 22, 'saves': 30}
      ]
    };
    final selected = selectPitcherAces(team);
    expect(selected['SP_L']!.single['player_key'], 's');
    expect(selected['RP_L']!.single['player_key'], 'r');
    expect(selected['CL']!.single['player_key'], 'c');
    expect(selected['SP_R'], isNull);
  });
  testWidgets('札束グラフは左端を揃え年俸に比例して右へ伸びる', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 200,
                child: Column(children: [
                  SalaryMoneyBar(amount: 12500000, maximum: 25000000),
                  SalaryMoneyBar(amount: 25000000, maximum: 25000000),
                  SalaryMoneyBar(amount: 0, maximum: 0),
                ])))));
    final graphs = find.descendant(of: find.byType(SalaryMoneyBar), matching: find.byType(CustomPaint));
    final first = tester.getRect(graphs.at(0));
    final second = tester.getRect(graphs.at(1));
    expect(first.left, second.left);
    expect(first.width, second.width / 2);
    expect(tester.getSize(graphs.at(2)).width, 0);
    expect(find.bySemanticsLabel('年俸 1250万円'), findsOneWidget);
    expect(salaryAmount(12500000, 'JPY'), '1250万円');
    expect(tester.takeException(), isNull);
  });
  testWidgets('契約を共通年軸に描き、未確認の期間は帯にしない', (tester) async {
    final team = <String, dynamic>{
      'id_team': 1,
      'name_team': '球団A',
      'contracts': [
        {
          'player_key': 'a',
          'name': '選手A',
          'periods': [
            {'start_year': 2025, 'end_year': 2027, 'period': '2025–2027'},
            {'period': '終了年非公表', 'start_year': 2028}
          ],
          'salary_history': [
            {'year': 2026, 'amount': 12500000, 'currency': 'JPY'}
          ]
        }
      ]
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthContracts(team: team, year: 2026, comparisonTeams: [
      team,
      const {
        'id_team': 2,
        'name_team': '球団B',
        'roster': [
          {'name': '選手B', 'player_key': 'b'}
        ]
      }
    ]))));
    expect(find.text('2025–2027 '), findsOneWidget);
    expect(find.text('1250万円'), findsNWidgets(3));
    expect(find.text('球団B'), findsNWidgets(2));
    expect(find.textContaining('終了年非公表'), findsNothing);
    expect(find.text('2028 '), findsOneWidget);
    expect(find.text('2026 球団B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('契約は選択年度の年俸順で並び過去年俸だけの選手は最後', (tester) async {
    Map<String, dynamic> player(String id, int? current, int past) => {
          'player_key': id,
          'name': id,
          'salary_history': [
            {'year': 2025, 'amount': past},
            if (current != null) {'year': 2026, 'amount': current},
          ]
        };
    final a = <String, dynamic>{
      'id_team': 1,
      'name_team': '球団A',
      'contracts': [player('未確認', null, 900000000), player('低額', 10000000, 500000000)]
    };
    final b = <String, dynamic>{
      'id_team': 2,
      'name_team': '球団B',
      'contracts': [player('高額', 300000000, 1000000)]
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StrengthContracts(team: a, comparisonTeams: [a, b], year: 2026))));
    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y('高額'), lessThan(y('低額')));
    expect(y('低額'), lessThan(y('未確認')));
    await tester.tap(find.text('生涯年俸順'));
    await tester.pumpAndSettle();
    expect(y('未確認'), lessThan(y('低額')));
    expect(y('低額'), lessThan(y('高額')));
    await tester.tap(find.text('今年度年俸順'));
    await tester.pumpAndSettle();
    expect(y('高額'), lessThan(y('低額')));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StrengthContracts(team: a, comparisonTeams: [a, b], year: 2025))));
    expect(y('未確認'), lessThan(y('低額')));
    expect(y('低額'), lessThan(y('高額')));
    expect(tester.takeException(), isNull);
  });
  testWidgets('契約は選択年度まで自動スクロールし選手名列と見出しを固定する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final team = <String, dynamic>{
      'id_team': 1,
      'name_team': '球団A',
      'contracts': [
        for (var i = 0; i < 12; i++)
          {
            'player_key': '$i',
            'name': '選手$i',
            'periods': [
              {'start_year': 2010, 'end_year': 2030}
            ],
            'salary_history': [
              {'year': 2026, 'amount': 10000000}
            ]
          }
      ]
    };
    Widget screen(int year) => MaterialApp(home: Scaffold(body: StrengthContracts(team: team, year: year, comparisonTeams: [team])));
    await tester.pumpWidget(screen(2026));
    await tester.pumpAndSettle();
    final scroll = tester.widget<SingleChildScrollView>(find.byKey(const ValueKey('contract-horizontal-scroll'))).controller!;
    expect(scroll.offset, 16 * 160);
    expect(tester.getTopLeft(find.byKey(const ValueKey('contract-year-2026'))).dx, 340);
    final nameBefore = tester.getTopLeft(find.text('選手0'));
    final headingBefore = tester.getTopLeft(find.text('球団・選手'));
    scroll.jumpTo(0);
    await tester.pump();
    expect(tester.getTopLeft(find.text('選手0')), nameBefore);
    expect(tester.getTopLeft(find.text('球団・選手')), headingBefore);
    final chartBefore = tester.getTopLeft(find.byType(TeamSalaryChart)).dy;
    await tester.dragFrom(const Offset(200, 340), const Offset(0, -120));
    await tester.pumpAndSettle();
    final chartAfter = tester.getTopLeft(find.byType(TeamSalaryChart)).dy;
    final headerAfter = tester.getTopLeft(find.text('球団・選手')).dy;
    expect(chartAfter, lessThan(chartBefore));
    expect(headerAfter, lessThan(headingBefore.dy));
    // Once the summary is scrolled out, the timeline header stays visible.
    await tester.dragFrom(const Offset(200, 340), const Offset(0, -200));
    await tester.pumpAndSettle();
    final pinnedHeader = tester.getTopLeft(find.text('球団・選手')).dy;
    await tester.dragFrom(const Offset(200, 340), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('球団・選手')).dy, pinnedHeader);
    expect(scroll.offset, 0); // A rebuild must not undo the user's scroll.
    await tester.pumpWidget(screen(2025));
    await tester.pumpAndSettle();
    expect(scroll.offset, 15 * 160);
    expect(tester.getTopLeft(find.byKey(const ValueKey('contract-year-2025'))).dx, 340);
    expect(tester.takeException(), isNull);
  });

  testWidgets('表示設定を切り替えると選手マークに即時反映する', (tester) async {
    addTearDown(() => DisplaySettings.instance.value = {});
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PlayerStatCell(row: {'name_player': '選手', 'flg_under21': true, 'flg_rookie': true, 'stats': '.300'}))));
    expect(find.textContaining('🌱'), findsOneWidget);
    DisplaySettings.instance.setShown('flg_under21', false);
    await tester.pump();
    expect(find.textContaining('🌱'), findsNothing);
    expect(find.textContaining('🔰'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: DisplaySettingsPage()));
    expect(find.text('表示設定'), findsOneWidget);
    expect(tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).first.value, isFalse);
  });
}
