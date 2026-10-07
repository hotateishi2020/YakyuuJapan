import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/game_dedupe.dart';

void main() {
  test('翌朝JSTの同一試合は1件にまとめる', () {
    final rows = dedupeSameDayMatchupRows([
      {
        'code_game': 'DS',
        'id_team_home': 1,
        'id_team_away': 2,
        'score_home': 0,
        'score_away': 3,
        'state': '試合終了',
        'date_game': '2026-10-03',
        'time_game': '🌙 17:00',
        'id_game': 3317,
      },
      {
        'code_game': 'DS',
        'id_team_home': 1,
        'id_team_away': 2,
        'score_home': 0,
        'score_away': 3,
        'state': '試合終了',
        'date_game': '2026-10-04',
        'time_game': '☀️ 02:00',
        'id_game': 643,
      },
      {
        'code_game': 'DS',
        'id_team_home': 1,
        'id_team_away': 2,
        'score_home': 3,
        'score_away': 4,
        'state': '試合終了',
        'date_game': '2026-10-05',
        'time_game': '🌙 21:00',
        'id_game': 3323,
      },
      {
        'code_game': 'DS',
        'id_team_home': 1,
        'id_team_away': 2,
        'score_home': 3,
        'score_away': 4,
        'state': '試合終了',
        'date_game': '2026-10-06',
        'time_game': '☀️ 06:00',
        'id_game': 649,
      },
    ]);
    expect(rows, hasLength(2));
    expect(gameNightDate(rows[0]), '2026-10-03');
    expect(gameNightDate(rows[1]), '2026-10-05');
  });

  test('同じ暦日の00:00重複と前後日の同スコアは1件にする', () {
    final rows = dedupeSameDayMatchupRows([
      {
        'code_game': 'DS',
        'id_team_home': 16,
        'id_team_away': 15,
        'score_home': 5,
        'score_away': 2,
        'state': '試合終了',
        'date_game': '2026-10-06',
        'time_game': '☀️ 09:00',
        'id_game': 650,
      },
      {
        'code_game': 'DS',
        'id_team_home': 16,
        'id_team_away': 15,
        'score_home': 5,
        'score_away': 2,
        'state': '試合終了',
        'date_game': '2026-10-06',
        'time_game': '🌙 00:00',
        'id_game': 3324,
      },
      {
        'code_game': 'DS',
        'id_team_home': 19,
        'id_team_away': 18,
        'score_home': 0,
        'score_away': 3,
        'state': '試合終了',
        'date_game': '2026-10-03',
        'id_game': 3317,
      },
      {
        'code_game': 'DS',
        'id_team_home': 19,
        'id_team_away': 18,
        'score_home': 0,
        'score_away': 3,
        'state': '試合終了',
        'date_game': '2026-10-04',
        'id_game': 643,
      },
    ]);
    expect(rows, hasLength(2));
    expect(rows.where((row) => row['id_team_home'] == 16), hasLength(1));
    expect(rows.where((row) => row['id_team_home'] == 19), hasLength(1));
  });

  test('スコアが違う連戦は同じ夜扱いになっても2試合残す', () {
    final rows = dedupeSameDayMatchupRows([
      {
        'code_game': 'DS',
        'id_team_home': 35,
        'id_team_away': 41,
        'score_home': 3,
        'score_away': 2,
        'state': '試合終了',
        'date_game': '2026-10-04',
        'time_game': '☀️ 09:30',
        'id_game': 646,
      },
      {
        'code_game': 'DS',
        'id_team_home': 35,
        'id_team_away': 41,
        'score_home': 3,
        'score_away': 2,
        'state': '試合終了',
        'date_game': '2026-10-04',
        'time_game': '🌙 00:30',
        'id_game': 3320,
      },
      {
        'code_game': 'DS',
        'id_team_home': 35,
        'id_team_away': 41,
        'score_home': 4,
        'score_away': 3,
        'state': '試合終了',
        'date_game': '2026-10-05',
        'time_game': '☀️ 05:00',
        'id_game': 647,
      },
      {
        'code_game': 'DS',
        'id_team_home': 35,
        'id_team_away': 41,
        'score_home': 4,
        'score_away': 3,
        'state': '試合終了',
        'date_game': '2026-10-04',
        'time_game': '🌙 20:00',
        'id_game': 3321,
      },
    ]);
    expect(rows, hasLength(2));
    final scores = rows.map((row) => '${row['score_home']}-${row['score_away']}').toSet();
    expect(scores, {'3-2', '4-3'});
  });

  test('未開始のYahooと歴史インポートは同じカードなら1件にする', () {
    final rows = dedupeSameDayMatchupRows([
      {
        'code_game': 'DS',
        'id_team_home': 41,
        'id_team_away': 35,
        'score_home': -1,
        'score_away': -1,
        'state': '予想先発',
        'date_game': '2026-10-07',
        'time_game': '☀️ 10:30',
        'id_game': 652,
        'name_pitcher_home': 'ニック・ピベッタ',
        'name_pitcher_away': 'ダスティン・メイ',
      },
      {
        'code_game': 'DS',
        'id_team_home': 41,
        'id_team_away': 35,
        'state': '試合前',
        'date_game': '2026-10-07',
        'time_game': '🌙 01:30',
        'id_game': 3326,
      },
    ]);
    expect(rows, hasLength(1));
    expect(rows.first['id_game'], 652);
  });

  test('進行中のYahoo試合は歴史の試合前より優先する', () {
    final rows = dedupeSameDayMatchupRows([
      {
        'code_game': 'DS',
        'id_team_home': 41,
        'id_team_away': 35,
        'score_home': 0,
        'score_away': 0,
        'state': '2回表',
        'date_game': '2026-10-07',
        'time_game': '☀️ 07:00',
        'id_game': 651,
      },
      {
        'code_game': 'DS',
        'id_team_home': 41,
        'id_team_away': 35,
        'state': '試合前',
        'date_game': '2026-10-07',
        'time_game': '🌙 22:00',
        'id_game': 3328,
      },
    ]);
    expect(rows, hasLength(1));
    expect(rows.single['id_game'], 651);
    expect(rows.single['state'], '2回表');
  });
}
