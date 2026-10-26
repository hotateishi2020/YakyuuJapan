import 'package:html/parser.dart' as awardHtml;
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../app/Records.dart';
import '../app/AwardValues.dart';
import '../app/MlbRecordStreaks.dart';
import '../app/RecordCatalog.dart';
import '../app/RecordSources.dart';
import '../app/RecordStreaks.dart';
import '../app/OrgLeague.dart';

Map<String, dynamic> team(int year, int id, int rank) => {'year': year, 'id_team': id, 'id_league': 1, 'int_rank': rank, 'int_win': 80, 'int_lose': 60, 'int_draw': 3, 'name': '球団$id'};
Map<String, dynamic> game(int id, {bool loaded = true}) => {'id': id, 'id_team_home': 1, 'id_team_away': 2, 'flg_stats_loaded': loaded};
Map<String, dynamic> box(int game, int player, {String decision = '', int runs = 0, int hits = 0, int walks = 0, int ab = 1}) => {'id_game': game, 'id_player': player, 'name': '選手$player', 'int_batting': ab, 'int_hit1': hits, 'int_fourball': walks, 'int_pitch': decision.isEmpty ? 0 : 20, 'int_runs': runs, 'code_result_pitcher': decision};
void main() {
  test('event streak batches preserve cross-batch runs and missing-game resets', () {
    final games = [for (var i = 1; i <= 7; i++) game(i, loaded: i != 4)];
    final boxes = [for (final i in [1, 2, 3, 5, 6, 7]) box(i, 1, hits: 1)];
    final events = [for (final i in [1, 2, 3, 5, 6, 7])
      {'id_game': i, 'id_batter': 1, 'id_pitcher': 2,
       'flg_bottom': true, 'code_result': 'HIT1'}];
    final expected = buildEventStreaks(games, boxes, events, 2026);
    expect(expected['hit_pa']!.single['value'], 3);
    for (final size in [1, 2, 3, 5]) {
      final accumulator = EventStreakAccumulator(2026);
      for (var offset = 0; offset < games.length; offset += size) {
        final batch = games.skip(offset).take(size).toList();
        final ids = batch.map((g) => g['id']).toSet();
        accumulator.addGames(batch,
            boxes.where((r) => ids.contains(r['id_game'])).toList(),
            events.where((r) => ids.contains(r['id_game'])).toList());
      }
      expect(accumulator.result(), expected);
    }
  });
  test('近鉄の監督はオリックスや近畿日本と区別して全55年度を照合する', () {
    final catalog = jsonDecode(File('data/timeline-managers-npb.json').readAsStringSync())['clubs'];
    for (final name in ['近鉄パールス', '近鉄バファロー', '近鉄バファローズ', '大阪近鉄バファローズ']) {
      expect(timelineManagerClubKey({'name': name, 'manager_team_url': 'https://npb.jp/bis/teams/rst_b.html'}), 'bu');
    }
    expect(timelineManagerClubKey({'name': '近畿日本', 'manager_team_name': 'ソフトバンク'}), 'h');
    expect(timelineManagerClubKey({'name': 'オリックス・バファローズ', 'manager_team_name': 'オリックス'}), 'b');
    final years = catalog['bu']['years'] as Map;
    expect(years.keys.toSet(), {for (var year = 1950; year <= 2004; year++) '$year'});
    expect(years['1979'], '西本幸雄');
    expect(years['1989'], '仰木彬');
    expect(years['2001'], '梨田昌孝');
  });
  test('年表の順位セル用にその年度の監督名を保持する', () {
    final result = buildRecordStandings([
      {...team(2025, 1, 1), 'manager': '当年監督'},
      {...team(2024, 1, 1), 'manager': '前年監督'},
    ], [], OrgKind.npb);
    expect(result.first['leagues'][0]['teams'][0]['manager'], '当年監督');
    expect(result.last['leagues'][0]['teams'][0]['manager'], '前年監督');
  });

  test('partial game streaks remain visible with explicit coverage and scope', () {
    final result = seasonStreakPresentation(
      observed: [{'name': '選手', 'value': 4}], official: false,
      completedGames: 471, loadedGames: 21);
    expect(result['current'], [{'name': '選手', 'value': 4}]);
    expect(result['current_status'], 'partial');
    expect(result['current_label'], contains('取得済み区間'));
    expect(result['current_message'], contains('21／471'));
  });
  test('verified season snapshots remain visible independently of local coverage', () {
    final leaders = [{'name': '選手', 'value': 143}];
    final result = seasonStreakPresentation(observed: leaders, official: true,
      completedGames: 471, loadedGames: 21);
    expect(result['current'], leaders);
    expect(result.containsKey('current_status'), isFalse);
  });
  test('audited unavailable categories never expose partial DB maxima', () {
    final result = seasonStreakPresentation(
      observed: [{'name': '不完全な集計', 'value': 15}], official: true,
      completedGames: 471, loadedGames: 21,
      audit: {'status': 'unavailable', 'note': '全打席の順序が未確認', 'sources': []});
    expect(result['current'], isEmpty);
    expect(result['current_status'], 'unavailable');
    expect(result['current_message'], contains('全打席の順序が未確認'));
    expect(result['current_label'], '今シーズン記録');
  });
  test('audited category retains ties and current-season sources', () {
    final leaders = [{'name': '甲', 'value': 12}, {'name': '乙', 'value': 12}];
    final result = seasonStreakPresentation(observed: leaders, official: true,
      completedGames: 471, loadedGames: 21,
      audit: {'status': 'verified', 'sources': ['https://npb.jp/']});
    expect(result['current'], leaders);
    expect(result['current_status'], 'verified');
    expect(result['current_sources'], ['https://npb.jp/']);
  });

  test('公式の春秋順位は合算せず優勝・順位・球団IDを季別に保持する', () {
    final phases = (jsonDecode(File('data/npb_split_standings.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final annual = [for (final year in [1939, 1938, 1937]) {
      'year': year, 'champion': '年間合算', 'leagues': [{'teams': [
        {'id_team': 1, 'name': '東京巨人', 'logo_url': 'giants'},
        {'id_team': 2, 'name': '大阪タイガース'},
        {'id_team': 3, 'name': 'ライオン'},
      ]}]
    }];
    final result = applySplitRecordStandings(annual, phases);
    expect(result.map((s) => '${s['year']}-${s['phase']}'),
      ['1939-null', '1938-spring', '1938-fall', '1937-spring', '1937-fall']);
    expect(result.skip(1).map((s) => s['champion']),
      ['大阪タイガース', '東京巨人', '東京巨人', '大阪タイガース']);
    final spring = result[3]['leagues'][0]['teams'] as List;
    expect(spring.first['id_team'], 1);
    expect(spring.first['logo_url'], 'giants');
    expect(spring.first['wins'], 41);
    expect(spring.first['losses'], 13);
    expect(spring.first['champion'], true);
    expect(spring.firstWhere((t) => t['name'] == '大東京')['id_team'], 3);
    expect(result[2]['leagues'][0]['teams'], hasLength(9));
  });
  test('MLB league champion is the LCS winner, not the standings leader', () {
    final rows = [
      {...team(2026,13,1),'id_league':3},
      {...team(2026,14,2),'id_league':3},
    ];
    final result=buildRecordStandings(rows,[
      for(var i=0;i<4;i++) {'year':2026,'id_team_home':14,'id_team_away':13,'score_home':2,'score_away':1,'state':'終了','code_game':'LCS'}
    ],OrgKind.mlb);
    final teams=(result.single['leagues'] as List).single['teams'] as List;
    expect(teams[0]['league_champion'],false);
    expect(teams[1]['league_champion'],true);
    expect(teams[1]['champion'],false);
  });

  test('season holds use stored totals, include ties and combine traded players once per team', () {
    Map<String,dynamic> snapshot(int team, List<Map<String,dynamic>> pitchers) => {
      'id_team':team,'team':'T$team','payload':{'pitchers':{'relievers':pitchers,'closers':pitchers}}
    };
    Map<String,dynamic> pitcher(String id,int holds) => {'player_key':id,'name':id,'holds':holds,'saves':99};
    final result = seasonHoldLeaders([
      snapshot(1,[pitcher('a',20),pitcher('b',33)]),
      snapshot(2,[pitcher('a',13),pitcher('c',30)]),
    ],2026);
    expect(result.map((p)=>p['name']), ['a','b']);
    expect(result.map((p)=>p['value']), ['33','33']);
    expect(result.first['unit'],'ホールド');
    expect(result.first['year'],2026);
    expect(seasonHoldLeaders([],2026),isEmpty);
  });

  test('save streak ends at a non-save appearance', () {
    final decisions = ['SAVE','SAVE','HOLD','SAVE'];
    final r = buildSummaryStreaks([for(var i=1;i<=4;i++) game(i)],
      [for(var i=1;i<=4;i++) box(i,1,decision:decisions[i-1])],2026);
    expect(r['saves']!.single['value'],2);
  });
  test('home-run PA streak crosses games and a walk interrupts it', () {
    final codes = ['HOMERUN','HOMERUN','WALK','HOMERUN'];
    final r = buildEventStreaks([for(var i=1;i<=4;i++) game(i)],
      [for(var i=1;i<=4;i++) box(i,1,ab:i==3?0:1,walks:i==3?1:0)],
      [for(var i=1;i<=4;i++) {'id_game':i,'id_batter':1,'code_result':codes[i-1]}],2026);
    expect(r['hr_pa']!.single['value'],2);
  });

  test('表彰カードから受賞回数ではなく成績を取り出す', () {
    final card = awardHtml.parseFragment('<dd>本塁打　37<br>2年連続6度目</dd>');
    expect(npbAwardValue('最多本塁打者賞', awardCardText(card))['value'], '37');
    expect(npbAwardValue('首位打者賞', '首位打者賞 選手 打率 .316 初受賞'), {'value': '0.316', 'unit': ''});
    expect(npbAwardValue('最優秀中継ぎ投手賞', 'ホールドポイント 43 2年ぶり3度目'), {'value': '43', 'unit': 'HP'});
    expect(npbAwardValue('最優秀防御率', '防御率 1.38 初受賞')['value'], '1.38');
    expect(npbAwardValue('MVP', '4年ぶり3度目'), isEmpty);
    expect(npbAwardValue('最多勝利', '初受賞'), isEmpty);
  });
  test('受賞者に同年度・同リーグ・同タイトルの記録値を引き継ぐ', () {
    final statistical = [
      {'year': 2025, 'league': 'セ・リーグ', 'categories': [
        {'label': '本塁打王', 'players': [
          {'id_player': 1, 'name': '選手太郎', 'value': '40', 'unit': '本'},
          {'id_player': 2, 'name': '選手次郎', 'value': '40', 'unit': '本'},
        ]},
        {'label': '首位打者', 'players': [
          {'name': '別人', 'value': '0.350', 'unit': ''},
        ]},
      ]},
    ];
    final awards = [
      {'year': 2025, 'league': 'セ・リーグ', 'categories': [
        {'label': '最多本塁打者賞', 'players': [
          {'name': '選手 太郎', 'value': '受賞'},
          {'id_player': 2, 'name': '登録名変更', 'value': ''},
        ]},
        {'label': '首位打者', 'players': [{'name': '公式選手', 'value': '受賞'}]},
        {'label': 'MVP', 'players': [{'name': '選手太郎', 'value': '受賞'}]},
      ]},
      {'year': 2024, 'league': 'セ・リーグ', 'categories': [
        {'label': '本塁打王', 'players': [{'name': '選手太郎', 'value': '受賞'}]},
      ]},
    ];
    final result = mergeRecordAwards(statistical, awards, 2025);
    final categories = result.first['categories'] as List;
    expect(categories[0]['players'].map((p) => p['value']), ['40', '40']);
    expect(categories[0]['players'].map((p) => p['unit']), ['本', '本']);
    expect(categories[1]['players'][0]['value'], '受賞');
    expect(categories[2]['players'][0]['value'], '受賞');
    expect(result.last['categories'][0]['players'][0]['value'], '受賞');
  });
  test('MLB career includes ties at rank 50 and excludes rank 52', () {
    final metric = recordMetrics.firstWhere((m) => m.key == 'hr');
    final result = parseMlbRecord({'stats': [{'splits': [
      for (var i = 0; i < 52; i++) {'player': {'fullName': 'Player $i'}, 'stat': {metric.mlb: i == 50 ? 951 : 1000 - i}}
    ]}]}, metric, career: true);
    expect(result.length, 51);
    expect(result.last['rank'], 50);
  });
  test('award colors use the award year and spaced historical team names', () {
    final result = colorRecordTitles([{'year': 1988, 'categories': [{'players': [
      {'name': '選手', 'team': '(南　海)'}, {'name': '別選手', 'team': ''},
      {'name': '第三選手', 'team': '南海ホークス', 'id_team': 1}
    ]}]}], [
      {'year': 1988, 'id_team': 1, 'short_name': '南海', 'color_back': '#006600', 'color_font': '#ffffff'},
      {'year': 2026, 'id_team': 1, 'short_name': 'ソフトバンク', 'color_back': '#ffff00'},
      {'year': 1988, 'id_team': 2, 'short_name': '阪急'}
    ], [{'year': 1988, 'name': '別選手', 'id_team': 2, 'color_back': '#000033', 'color_font': '#eeeeee'}]);
    final players = result.first['categories'][0]['players'];
    expect(players[0]['color_back'], '#006600');
    expect(players[0]['color_font'], '#ffffff');
    expect(players[1]['color_back'], '#000033');
    expect(players[0]['team'], '南海');
    expect(players[1]['team'], '阪急');
    expect(players[2]['team'], '南海');
  });
  test('official game logs exclude postseason and distinguish sacrifice fly from bunt', () {
    final result = mlbGameLogStreaks([
      {
        'id': 1,
        'fullName': '打者',
        'active': true,
        'stats': [
          {
            'group': {'displayName': 'hitting'},
            'splits': [
              {
                'date': '2026-05-01',
                'gameType': 'R',
                'stat': {'hits': 1, 'atBats': 1, 'plateAppearances': 1}
              },
              {
                'date': '2026-05-02',
                'gameType': 'R',
                'stat': {'hits': 0, 'atBats': 0, 'sacBunts': 1, 'plateAppearances': 1}
              },
              {
                'date': '2026-05-03',
                'gameType': 'R',
                'stat': {'hits': 1, 'atBats': 1, 'plateAppearances': 1}
              },
              {
                'date': '2026-05-04',
                'gameType': 'R',
                'stat': {'hits': 0, 'atBats': 0, 'sacFlies': 1, 'plateAppearances': 1}
              },
              {
                'date': '2026-05-05',
                'gameType': 'R',
                'stat': {'hits': 1, 'atBats': 1, 'plateAppearances': 1}
              },
              {
                'date': '2026-10-01',
                'gameType': 'W',
                'stat': {'hits': 1, 'atBats': 1, 'plateAppearances': 1}
              },
            ]
          }
        ]
      }
    ], 2026);
    expect(result['hit_games']!.single['value'], 2);
    expect(result['onbase_games']!.single['value'], 1);
    expect(result['hit_games']!.single['status'], 'active');
  });
  test('verified award replaces inferred statistical title and excludes future years', () {
    final result = mergeRecordAwards([
      {
        'year': 2025,
        'league': 'セ・リーグ',
        'categories': [
          {
            'label': '首位打者',
            'players': [
              {'name': '旧'}
            ]
          }
        ]
      }
    ], [
      {
        'year': 2025,
        'league': 'セ・リーグ',
        'categories': [
          {
            'label': '首位打者',
            'players': [
              {'name': '公式'}
            ]
          },
          {
            'label': 'MVP',
            'players': [
              {'name': '受賞者'}
            ]
          }
        ]
      },
      {'year': 2027, 'league': 'セ・リーグ', 'categories': []}
    ], 2026);
    expect(result, hasLength(1));
    expect(result.single['categories'], hasLength(2));
    expect(result.single['categories'][0]['players'][0]['name'], '公式');
  });

  test('同じ球団IDでも年度別の旧名称を保持する', () {
    final result = buildRecordStandings([
      {...team(1988, 7, 1), 'name': '南海ホークス', 'short_name': '南海', 'historical_identity': true},
      {...team(2004, 7, 1), 'name': '福岡ダイエーホークス', 'short_name': 'ダイエー', 'historical_identity': true},
      {...team(2005, 7, 1), 'name': '福岡ソフトバンクホークス', 'short_name': 'ソフトバンク', 'historical_identity': false},
    ], [], OrgKind.npb);
    final teams = result.map((s) => (s['leagues'] as List).first['teams'][0]).toList();
    expect(teams.map((t) => t['short_name']), ['ソフトバンク', 'ダイエー', '南海']);
    expect(teams.last['name'], '南海ホークス');
    expect(teams.last['historical_identity'], true);
  });

  test('1936〜1949年のNPBは1位を日本一とし1950年以降とMLBには適用しない', () {
    final rows = [for (final year in [1935,1936,1949,1950])
      for (final rank in [1,2]) {'year':year,'id_team':rank,'id_league':1,
        'int_rank':rank,'name':'球団$rank'}];
    final npb = buildRecordStandings(rows, [], OrgKind.npb);
    for (final season in npb) {
      expect(season['champion'], [1936,1949].contains(season['year']) ? '球団1' : null);
    }
    final mlb = buildRecordStandings([for (final r in rows) {...r,'id_league':3}], [], OrgKind.mlb);
    expect(mlb.every((s) => s['champion'] == null), isTrue);
  });
  test('standings are newest first and champions need the series winning threshold', () {
    final playoffs = [
      for (var i = 0; i < 3; i++) {'year': 2025, 'id_team_home': 1, 'id_team_away': 2, 'score_home': 3, 'score_away': 0, 'code_game': 'JS', 'state': '試合終了'}
    ];
    var result = buildRecordStandings([team(2024, 1, 1), team(2025, 1, 2), team(2025, 2, 1)], playoffs, OrgKind.npb);
    expect(result.first['year'], 2025);
    expect(result.first['champion'], isNull);
    expect(result.first['leagues'][0]['teams'][0]['name'], '球団2');
    playoffs.add({...playoffs.first});
    result = buildRecordStandings([team(2025, 1, 2), team(2025, 2, 1)], playoffs, OrgKind.npb);
    expect(result.first['champion'], '球団1');
    expect(result.first['leagues'][0]['teams'][1]['postseason'], isTrue);
  });
  test('best of nine World Series requires five wins', () {
    final p = [
      for (var i = 0; i < 4; i++) {'year': 1903, 'id_team_home': 1, 'id_team_away': 2, 'score_home': 3, 'score_away': 0, 'code_game': 'WS', 'state': '試合終了'}
    ];
    final t = {...team(1903, 1, 1), 'id_league': 3};
    expect(buildRecordStandings([t], p, OrgKind.mlb).first['champion'], isNull);
    p.add({...p.first});
    expect(buildRecordStandings([t], p, OrgKind.mlb).first['champion'], '球団1');
  });
  test('current records preserve ties and lower ERA wins', () {
    final metric = recordMetrics.firstWhere((m) => m.key == 'era');
    final rows = [
      for (var i = 1; i <= 3; i++) {'year': 2026, 'id_stats': 9, 'id_player': i, 'value': i == 1 ? 2.1 : 1.9}
    ];
    final result = currentLeaders(rows, metric, 2026);
    expect(result.map((p) => p['id_player']), [2, 3]);
    expect(result.first['value'], '1.90');
    expect(currentLeaders(rows, metric, 2025), isEmpty);
  });
  test('same year and league title holders share one category', () {
    final rows = [
      for (var i = 1; i <= 2; i++) {'year': 2025, 'id_league': 1, 'id_stats': 3, 'id_player': i, 'value': 40}
    ];
    final result = buildRecordTitles(rows, OrgKind.npb);
    expect(result.single['categories'].single['players'], hasLength(2));
    expect(result.single['provisional'], isFalse);
  });
  test('wins skip no decisions but a loss ends the streak', () {
    final result = buildSummaryStreaks([for (var i = 1; i <= 5; i++) game(i)], [box(1, 1, decision: 'WIN'), box(2, 1, decision: 'HOLD'), box(3, 1, decision: 'WIN'), box(4, 1, decision: 'LOSE'), box(5, 1, decision: 'WIN')], 2026);
    expect(result['wins']!.single['value'], 2);
  });
  test('unloaded games cannot join runs; runs allowed include unearned runs', () {
    final result = buildSummaryStreaks([game(1), game(2, loaded: false), game(3)], [box(1, 1, decision: 'HOLD'), box(3, 1, decision: 'HOLD', runs: 1)], 2026);
    expect(result['holds']!.single['value'], 1);
    expect(result['scoreless_games']!.single['value'], 1);
  });
  test('unrelated missing games preserve streaks but same-team gaps break them', () {
    Map<String, dynamic> fixture(int id, int home, int away, {bool loaded = true}) => {...game(id, loaded: loaded), 'id_team_home': home, 'id_team_away': away};
    final boxes = [box(1, 1, hits: 1), box(3, 1, hits: 1)];
    final events = [for (final id in [1, 3]) {'id_game': id, 'id_batter': 1, 'id_pitcher': 2, 'flg_bottom': true, 'code_result': 'HIT1'}];
    for (final sameTeam in [false, true]) {
      final games = [fixture(1, 10, 20), fixture(2, sameTeam ? 10 : 30, 40, loaded: false), fixture(3, 10, 20)];
      final expected = sameTeam ? 1 : 2;
      expect(buildSummaryStreaks(games, boxes, 2026)['hit_games']!.single['value'], expected);
      expect(buildEventStreaks(games, boxes, events, 2026)['hit_pa']!.single['value'], expected);
    }
  });
  test('game hit streak continues through walk-only games; PA streak does not', () {
    final boxes = [box(1, 1, hits: 1), box(2, 1, walks: 1, ab: 0), box(3, 1, hits: 1)];
    final games = [game(1), game(2), game(3)];
    expect(buildSummaryStreaks(games, boxes, 2026)['hit_games']!.single['value'], 2);
    final events = [
      for (var i = 1; i <= 3; i++) {'id_game': i, 'id_batter': 1, 'id_pitcher': 2, 'code_result': i == 2 ? 'WALK' : 'HIT1'}
    ];
    final result = buildEventStreaks(games, boxes, events, 2026);
    expect(result['hit_pa']!.single['value'], 1);
    expect(result['onbase_pa']!.single['value'], 3);
  });
  test('steal streak credits the runner, and non-PA events do not break hitting streaks', () {
    final events = [
      {'id_game': 1, 'id_batter': 1, 'id_pitcher': 2, 'code_result': 'HIT1'},
      {'id_game': 1, 'id_batter': 4, 'id_player_enter': 1, 'id_pitcher': 2, 'code_result': 'STEAL_BASE_SAFE'}
    ];
    final r = buildEventStreaks([game(1)], [box(1, 1, hits: 1)], events, 2026);
    expect(r['steals']!.single['id_player'], 1);
    expect(r['hit_pa']!.single['value'], 1);
  });
  test('incomplete play-by-play never creates a record', () {
    final r = buildEventStreaks([
      game(1)
    ], [
      box(1, 1, ab: 4)
    ], [
      {'id_game': 1, 'id_batter': 1, 'code_result': 'HIT1'}
    ], 2026);
    expect(r['hit_pa'], isEmpty);
  });
  test('official parsers preserve active marker and tied season leaders', () {
    const body = '<table><tr class="hilist"><td>1</td><td>*</td><td class="hiplayer">現役</td><td>123</td><td>2000-2026</td></tr></table>';
    expect(parseNpbRecord(body, career: true).single['status'], 'active');
    final metric = recordMetrics.firstWhere((m) => m.key == 'hr');
    final data = {
      'stats': [
        {
          'splits': [
            for (var i = 0; i < 3; i++)
              {
                'stat': {'homeRuns': i == 2 ? 72 : 73},
                'player': {'fullName': 'Player$i', 'active': false},
                'season': '2001'
              }
          ]
        }
      ]
    };
    expect(parseMlbRecord(data, metric, career: false), hasLength(2));
  });
  test('bundled records cover both leagues and carry sources for all verified holders', () {
    final data = jsonDecode(File('data/records.json').readAsStringSync());
    for (final org in ['npb', 'mlb']) {
      for (final section in ['season', 'career', 'streaks']) {
        expect(data[org][section].length, greaterThanOrEqualTo(12));
        for (final row in data[org][section]) {
          expect(row['sources'], isNotEmpty);
          expect(row['checked_at'], isNotEmpty);
        }
      }
    }
  });
}
