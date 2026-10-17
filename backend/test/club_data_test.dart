import 'package:test/test.dart';
import '../app/ClubData.dart';

void main() {
  final teams = <Map<String, dynamic>>[
    {'id': 1, 'name_short': '巨人', 'name_shortest': '巨', 'id_league': 1},
    {'id': 2, 'name_short': '阪神', 'name_shortest': '神', 'id_league': 1}
  ];
  final fixture = <String, dynamic>{
    'date': '2026-10-16',
    'home_code': 'g',
    'away_code': 't',
    'regular': true,
    'finished': false
  };
  test('球団コードをURLまたは正式略称から解決', () {
    expect(
        clubKey(
            {'url_npb_players': 'https://npb.jp/bis/2026/teams/rst_db.html'}),
        'db');
    expect(clubKey({'name_short': '福岡ソフトバンクホークス'}), 'h');
    expect(clubKey({'name_shortest': 'NYM'}), 'NYM');
  });
  test('終了と雨天中止を反映し、未開始データで確定結果を消さない', () {
    var games = mergeSeasonSchedule(teams, [
      fixture
    ], [
      {
        'datetime_start': '2026-10-16 18:00:00',
        'id_team_home': 1,
        'id_team_away': 2,
        'state': '試合中止'
      }
    ]);
    expect(games.single['state'], '試合中止');
    games = mergeSeasonSchedule(teams, [
      {...fixture, 'finished': true, 'score_home': 3, 'score_away': 1}
    ], [
      {
        'datetime_start': '2026-10-16 18:00:00',
        'id_team_home': 1,
        'id_team_away': 2,
        'state': '試合前'
      }
    ]);
    expect(games.single['score_home'], 3);
    expect(games.single['finished'], true);
  });
  test('ダブルヘッダーを残し、UTC開始時刻が一致する1試合だけ更新', () {
    final fixtures = [
      {...fixture, 'game_number': 1, 'time': '2026-10-17T00:00:00Z'},
      {...fixture, 'game_number': 2, 'time': '2026-10-17T03:00:00Z'}
    ];
    final games = mergeSeasonSchedule(teams, fixtures, [
      {
        'datetime_start': '2026-10-17T00:00:00Z',
        'id_team_home': 1,
        'id_team_away': 2,
        'state': '試合終了',
        'score_home': 4,
        'score_away': 2
      }
    ]);
    expect(games.length, 2);
    expect(games.first['date'], '2026-10-16');
    expect(games.first['score_home'], 4);
    expect(games.last['finished'], false);
  });
  test('2026の公式データは12球団分の監督を持つ', () {
    final data = readClubFile('club-hub-npb-2026.json');
    final clubs = data['clubs'] as List;
    expect(clubs.length, 12);
    for (final c in clubs) {
      expect(
          (c['staff'] as List).where((s) => s['category'] == '監督'), isNotEmpty);
      expect(
          (c['staff'] as List)
              .every((s) => s['source'].toString().startsWith('https://')),
          true);
    }
  });
  test('日程データの公式戦にクライマックスシリーズを含めない', () {
    final data = readClubFile('schedule-2026.json');
    final games = data['npb'] as List;
    expect(
        games
            .where((g) => g['date'] == '2026-10-15')
            .every((g) => g['regular'] == false),
        true);
    expect(
        games
            .where((g) => g['date'] == '2026-03-27')
            .every((g) => g['regular'] == true),
        true);
  });
}
