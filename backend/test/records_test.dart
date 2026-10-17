import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../app/Records.dart';
import '../app/MlbRecordStreaks.dart';
import '../app/RecordCatalog.dart';
import '../app/RecordSources.dart';
import '../app/RecordStreaks.dart';
import '../app/OrgLeague.dart';

Map<String, dynamic> team(int year, int id, int rank) => {'year': year, 'id_team': id, 'id_league': 1, 'int_rank': rank, 'int_win': 80, 'int_lose': 60, 'int_draw': 3, 'name': '球団$id'};
Map<String, dynamic> game(int id, {bool loaded = true}) => {'id': id, 'id_team_home': 1, 'id_team_away': 2, 'flg_stats_loaded': loaded};
Map<String, dynamic> box(int game, int player, {String decision = '', int runs = 0, int hits = 0, int walks = 0, int ab = 1}) => {'id_game': game, 'id_player': player, 'name': '選手$player', 'int_batting': ab, 'int_hit1': hits, 'int_fourball': walks, 'int_pitch': decision.isEmpty ? 0 : 20, 'int_runs': runs, 'code_result_pitcher': decision};
void main() {
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
