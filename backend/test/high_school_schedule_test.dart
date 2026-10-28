import 'dart:convert';
import 'package:test/test.dart';
import '../app/HighSchoolSchedule.dart';

void main() {
  late Map<String, dynamic> seed;
  setUp(() {
    seed = jsonDecode(jsonEncode(HighSchoolSchedule.snapshot()));
    for (final game in seed['kyushu']['matches']) {
      game.remove('score_home');
      game.remove('score_away');
      if (game['round'] > 0) {
        game['home'] = '${game['slot'] * 2 + 1}組の勝者';
        game['away'] = '${game['slot'] * 2 + 2}組の勝者';
      }
    }
  });
  List<Map<String, dynamic>> firstRoundResults() => [
        for (final m in seed['kyushu']['matches'])
          if (m['round'] == 0)
            {
              'round': 0,
              'slot': m['slot'],
              'home': schoolName(m['home']),
              'away': schoolName(m['away']),
              'score_home': m['slot'] == 2 || m['slot'] == 5 ? 0 : 2,
              'score_away': m['slot'] == 2 || m['slot'] == 5 ? 2 : 0,
            }
      ];

  test('確定結果で次の対戦校と県名を更新し、敗退校の条件付き予定を消す', () {
    final next = updateHighSchoolSchedule(
        seed, firstRoundResults(), 'source', DateTime.utc(2026, 10, 28));
    final tournament = next['calendar']['tournaments'][0];
    final quarter = tournament['matches'][11];
    expect(quarter['home'], '沖縄尚学');
    expect(quarter['away'], '佐賀北');
    expect(quarter['away_prefecture'], '佐賀');
    expect(quarter.containsKey('conditional'), false);
    expect(quarter.containsKey('candidate_schools'), false);
    expect(
        tournament['matches'][13]['candidate_schools'], isNot(contains('大分')));
    expect(tournament['matches'][13]['away'], '沖縄尚学／佐賀北の勝者');
  });

  test('未終了・同点・別チームのスコアでは勝ち上がりを決めない', () {
    final matches = seed['kyushu']['matches'];
    matches[0].remove('score_home');
    matches[0].remove('score_away');
    final rows = firstRoundResults();
    rows[0].remove('score_home');
    rows[0].remove('score_away');
    rows[1]['score_home'] = rows[1]['score_away'];
    rows[2]['home'] = '別の高校';
    final next = updateHighSchoolSchedule(
        seed, rows, 'source', DateTime.utc(2026, 10, 28));
    final games = next['kyushu']['matches'];
    expect(games[8]['home'], matches[8]['home']);
    expect(games[8]['away'], matches[8]['away']);
    expect(games[9]['home'], matches[9]['home']);
  });

  test('ホームとアウェイの逆順を補正して準決勝まで勝者を引き継ぐ', () {
    final rows = firstRoundResults();
    rows.add({
      'round': 1,
      'slot': 0,
      'home': '早稲田佐賀',
      'away': '祐誠',
      'score_home': 6,
      'score_away': 7
    });
    final next = updateHighSchoolSchedule(
        seed, rows, 'source', DateTime.utc(2026, 10, 28));
    expect(next['kyushu']['matches'][8]['score_home'], 7);
    expect(schoolName(next['kyushu']['matches'][12]['home']), '祐誠');
  });

  test('HTMLの試合終了だけを採用し、試合中の得点や別年・欠落HTMLを拒否', () {
    final body = '<h1>秋季九州大会 2026</h1>${List.generate(4, (r) => '<div class="gdw-round"><h4 class="gdw-rh">${highSchoolRounds[r]}</h4>${List.generate(8 >> r, (s) => '<div class="gdw-m ${s == 0 ? 'gdw-m--finished' : 'gdw-m--live'}" data-no="${s + 1}">'
        '<div class="gdw-s"><span class="gdw-name">A</span><span class="gdw-score">2</span></div>'
        '<div class="gdw-s"><span class="gdw-name">B</span><span class="gdw-score">1</span></div>'
        '<span class="gdw-court">10月29日（木） 9:00</span></div>').join()}</div>').join()}';
    final rows = parseHighSchoolResults(body, 2026);
    expect(rows.first['score_home'], 2);
    expect(rows[1]['score_home'], isNull);
    expect(rows.first['date'], '10/29');
    expect(() => parseHighSchoolResults(body, 2027), throwsFormatException);
    expect(() => parseHighSchoolResults('<h1>2026</h1>', 2026),
        throwsFormatException);
  });
}
