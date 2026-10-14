import 'package:html/parser.dart';
import 'package:test/test.dart';

import '../app/BoxScore.dart';
import '../app/LiveText.dart';
import '../app/PlayLabel.dart';
import '../app/Value.dart';

void main() {
  test('独立した失策を打点へ付けず、安打後の失策で打撃結果を上書きしない', () {
    // 2026/10/13 LAD-MILの得点経過を要約したYahoo形式。
    final entries = [
      (1, false, 1, 'T.ヘルナンデス', ['センターへの犠牲フライ MIL 0-1 LAD']),
      (1, true, 1, 'W.コントレラス', ['レフトへのタイムリーヒット MIL 1-1 LAD']),
      (
        3,
        false,
        1,
        'T.ヘルナンデス',
        ['失策: <a class="bb-liveText__player">L.ヘンダーソン</a> MIL 1-2 LAD', 'サードゴロ']
      ),
      (3, true, 1, 'C.イエリチ', ['センターへのタイムリーヒット MIL 3-2 LAD']),
      (
        5,
        false,
        1,
        'T.エドマン',
        [
          '送りバント成功 さらにピッチャーが悪送球 MIL 3-3 LAD',
          '失策: <a class="bb-liveText__player">L.ヘンダーソン</a> MIL 3-3 LAD'
        ]
      ),
      (5, false, 2, 'F.フリーマン', ['レフトへの犠牲フライ MIL 3-4 LAD']),
      (5, true, 1, 'W.コントレラス', ['ホームラン MIL 4-4 LAD']),
      (6, true, 1, 'W.コントレラス', ['レフトへのタイムリーヒット MIL 5-4 LAD']),
      (8, true, 1, 'B.チュラング', ['ライトへのタイムリーヒット MIL 6-4 LAD']),
      (
        8,
        true,
        2,
        'J.バウアーズ',
        [
          'センターへのタイムリーヒット MIL 7-4 LADさらにセンターがエラー',
          '失策: <a class="bb-liveText__player">A.パヘス</a> MIL 7-4 LAD'
        ]
      ),
    ];
    final parsed = LiveText.parse(parse('''
      <span class="bb-scoreList__state">試合終了</span>
      <div id="text_live">
        ${entries.map((entry) => '''<section class="bb-liveText">
          <div class="bb-liveText__inning">${entry.$1}回${entry.$2 ? '裏' : '表'}</div>
          <li class="bb-liveText__item"><p class="bb-liveText__batter">
            <span class="bb-liveText__order">${entry.$3}番</span>
            <a class="bb-liveText__player">${entry.$4}</a>
            <span class="bb-liveText__state">一死走者なし</span>
          </p>${entry.$5.map((text) => '<p class="bb-liveText__summary">$text</p>').join()}</li>
        </section>''').join()}
      </div>
    '''));
    expect(parsed.finished, isTrue);
    final notes = boxLiveNotes(
      parsed,
      idTeamHome: 35,
      idTeamAway: 40,
      idPitcherHome: 1,
      idPitcherAway: 2,
      playerId: (_, __) => 0,
      resolveScore: (event, _, __, ___) => event.scoreLeft == null
          ? null
          : (home: event.scoreLeft!, away: event.scoreRight!),
    );
    final grounder =
        notes.singleWhere((note) => note.inning == 3 && !note.bottom);
    expect(grounder.battingResult, Value.CodeGameResult.OUT_GROUND);
    expect(grounder.runs, 0);
    expect(grounder.extras.single.runs, 1);
    expect(grounder.extras.single.enterName, 'L.ヘンダーソン');
    final bunt = notes.singleWhere((note) => note.batterName == 'T.エドマン');
    expect(bunt.battingResult, Value.CodeGameResult.SACRIFICE_BUNT);
    expect(bunt.runs, 0);
    expect(bunt.extras.single.runs, 1);
    final hit = notes.singleWhere((note) => note.batterName == 'J.バウアーズ');
    expect(hit.battingResult, Value.CodeGameResult.HIT_SINGLE);
    expect(hit.runs, 1);
    expect(hit.extras.single.runs, 0);
    expect(
        notes
            .where((note) => !note.bottom)
            .fold<int>(0, (sum, note) => sum + note.runs),
        2);
    expect(
        notes
            .where((note) => note.bottom)
            .fold<int>(0, (sum, note) => sum + note.runs),
        7);
  });

  test('牽制失策の得点は後続ゴロに青いrunだけを付ける', () {
    final rows = [
      {
        'id': 1,
        'int_inning': 3,
        'flg_bottom': false,
        'int_batting_order': 3,
        'cnt_out': 1,
        'code_result': 'ERROR_RUNNING',
        'int_runs': 1
      },
      {
        'id': 2,
        'int_inning': 3,
        'flg_bottom': false,
        'int_batting_order': 3,
        'cnt_out': 1,
        'code_result': 'OUT_GROUND',
        'code_direction_batting': 'THIRD',
        'int_runs': 0
      },
    ];
    expect(formatPlayLabels(rows), '三ゴロ|out/run');
  });
}
