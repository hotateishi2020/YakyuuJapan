import 'package:html/parser.dart';
import 'package:test/test.dart';

import '../app/BoxScore.dart';
import '../app/LiveText.dart';
import '../app/Value.dart';

void main() {
  test('出場成績の打順とイニング別の結果を正本にする', () {
    final doc = parse('''
      <div id="async-gameBatterStats"><table><tbody>
        <tr>
          <td>(右)</td><td><a>平山 功太</a></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">空三振</div></td>
          <td class="bb-statsTable__data--inning"></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">遊ゴロ</div></td>
        </tr>
        <tr>
          <td>(左)</td><td><a>笹原 操希</a></td>
          <td class="bb-statsTable__data--inning"></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">二ゴロ</div></td>
          <td class="bb-statsTable__data--inning"></td>
        </tr>
        <tr>
          <td>走左</td><td><a>緒方 理貢</a></td>
          <td class="bb-statsTable__data--inning"></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">遊飛</div></td>
          <td class="bb-statsTable__data--inning"></td>
        </tr>
        <tr>
          <td></td><td><a>丸 佳浩</a></td>
          <td class="bb-statsTable__data--inning"></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">故意四</div></td>
          <td class="bb-statsTable__data--inning"></td>
        </tr>
        <tr>
          <td>(投)</td><td><a>山﨑 伊織</a></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">見三振</div></td>
          <td class="bb-statsTable__data--inning"></td>
          <td class="bb-statsTable__data--inning"></td>
        </tr>
        <tr>
          <td></td><td><a>石塚 裕惺</a></td>
          <td class="bb-statsTable__data--inning"></td>
          <td class="bb-statsTable__data--inning"></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">右飛</div></td>
        </tr>
        <tr><th>合計</th></tr>
        <tr>
          <td>(遊)</td><td><a>長岡 秀樹</a></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">中２</div></td>
          <td class="bb-statsTable__data--inning"></td>
          <td class="bb-statsTable__data--inning"></td>
        </tr>
      </tbody></table></div>
    ''');
    final plates = parseBoxPlates(doc, 1, 4);
    expect(plates.map((plate) => '${plate.order}${plate.name}${plate.inning}${plate.label}').toList(), [
      '1平山功太1空三振',
      '1平山功太3遊ゴロ',
      '2笹原操希2二ゴロ',
      '2緒方理貢2遊飛',
      '2丸佳浩2故意四',
      '3山﨑伊織1見三振',
      '3石塚裕惺3右飛',
      '1長岡秀樹1中２',
    ]);
    final ishika = plates.firstWhere((plate) => plate.name == '石塚裕惺');
    expect(ishika.order, 3);
    expect(ishika.result, Value.CodeGameResult.OUT_FLY);
    expect(ishika.direction, Value.CodePosition.RF);
    expect(ishika.bottom, isFalse);
    final nagaoka = plates.last;
    expect(nagaoka.bottom, isTrue);
    expect(nagaoka.teamId, 4);
    expect(nagaoka.result, Value.CodeGameResult.HIT_DOUBLE);
    expect(nagaoka.direction, Value.CodePosition.CF);
    expect(plates.firstWhere((plate) => plate.name == '丸佳浩').result, Value.CodeGameResult.WALK_BALL);
    final starters = parseBoxStarters(doc, 1, 4);
    expect(starters.map((starter) => '${starter.order}${starter.name}${starter.position}').toList(), [
      '1平山功太右',
      '2笹原操希左',
      '3山﨑伊織投',
      '1長岡秀樹遊',
    ]);
  });

  test('複合守備バッジは先発位置を取り、途中移籍の末尾位置を使わない', () {
    final doc = parse('''
      <div id="async-gameBatterStats"><table><tbody>
        <tr>
          <td>(右一)</td><td><a>澤井 廉</a></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">左安</div></td>
        </tr>
        <tr>
          <td>走一</td><td><a>赤羽 由紘</a></td>
          <td class="bb-statsTable__data--inning"></td>
        </tr>
        <tr>
          <td>(中)</td><td><a>並木 秀尊</a></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">中飛</div></td>
        </tr>
        <tr>
          <td>(一)</td><td><a>山田 哲人</a></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">右飛</div></td>
        </tr>
        <tr>
          <td>右</td><td><a>丸山 和郁</a></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">四球</div></td>
        </tr>
      </tbody></table></div>
    ''');
    final plates = parseBoxPlates(doc, 1, 2);
    final sawai = plates.firstWhere((plate) => plate.name == '澤井廉');
    final yamada = plates.firstWhere((plate) => plate.name == '山田哲人');
    final maruyama = plates.firstWhere((plate) => plate.name == '丸山和郁');
    expect(sawai.order, 1);
    expect(sawai.position, '右');
    expect(yamada.order, 3);
    expect(yamada.position, '一');
    expect(maruyama.order, 3);
    expect(maruyama.position, '右');
  });

  test('速報の打点が違う結果は打席を増やさず、盗塁だけ足す', () {
    final doc = parse('''
      <div id="async-gameBatterStats"><table><tbody>
        <tr>
          <td>(遊)</td><td>泉口 友汰</td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">三ゴロ</div></td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">四球</div></td>
        </tr>
      </tbody></table></div>
    ''');
    final plates = parseBoxPlates(doc, 1, 4);
    final extras = attachLiveNotes(plates, [
      LivePlateNote(
        inning: 1,
        bottom: false,
        teamId: 1,
        batterName: '泉口友汰',
        battingOrder: 3,
        outs: 0,
        runnerFirst: false,
        runnerSecond: false,
        runnerThird: false,
        battingResult: Value.CodeGameResult.OUT_GROUND,
        runs: 0,
        homerNumber: 0,
        stateScore: '',
        goodbye: false,
        direction: '',
        scoreHome: 0,
        scoreAway: 0,
        pitcherId: 9,
        extras: const [],
      ),
      LivePlateNote(
        inning: 1,
        bottom: false,
        teamId: 1,
        batterName: '大城卓三',
        battingOrder: 4,
        outs: 1,
        runnerFirst: true,
        runnerSecond: false,
        runnerThird: false,
        battingResult: Value.CodeGameResult.HOME_RUN,
        runs: 2,
        homerNumber: 12,
        stateScore: 'FIRST',
        goodbye: false,
        direction: 'LEFT',
        scoreHome: 0,
        scoreAway: 0,
        pitcherId: 9,
        extras: const [
          LiveExtra(result: 'STEAL_BASE_OUT', category: 'RUNNING_BASE', enterName: '泉口友汰'),
        ],
      ),
    ]);
    expect(plates, hasLength(2));
    expect(plates.first.matched, isTrue);
    expect(plates.first.outs, 0);
    expect(plates.last.matched, isFalse);
    expect(extras, hasLength(1));
    expect(extras.single.extra.result, 'STEAL_BASE_OUT');
    expect(extras.single.outs, 1);
  });

  test('セーフティバントの次の先制タイムリーを打席として残す', () {
    String plate(int order, String name, String summary) {
      return '''
        <li class="bb-liveText__item">
          <p class="bb-liveText__batter"><span class="bb-liveText__order">$order番</span><a class="bb-liveText__player">$name</a><span class="bb-liveText__state">無死走者なし</span></p>
          <p class="bb-liveText__summary"><span>$summary</span></p>
        </li>
      ''';
    }

    final doc = parse('''
      <div id="text_live">
        <section class="bb-liveText">
          <div class="bb-liveText__inning">1回表</div>
          ${plate(1, '柳田', 'レフト前ヒット')}
          ${plate(2, '周東', 'センター前ヒット')}
          ${plate(3, '牧原', 'ライト前ヒット')}
          ${plate(4, '今宮', 'レフト前ヒット')}
        </section>
        <section class="bb-liveText">
          <div class="bb-liveText__inning">2回表</div>
          ${plate(5, '柳町', 'ショートへの内野安打')}
          ${plate(6, '川瀬', 'フォアボールを選ぶ')}
          ${plate(7, '牧原大成', 'ランナー一二塁から一塁側へセーフティバントを試み、一塁セーフ 満塁')}
          ${plate(8, '海野隆司', '0アウト満塁の1-2からレフトへのタイムリーヒットでソフトバンク先制！ ロ 0-1 ソ 満塁')}
        </section>
      </div>
    ''');
    final live = LiveText.parse(doc);
    final second = live.halves.where((half) => half.inning == 2 && !half.bottom).single;
    final unno = second.plates.where((plate) => plate.batterName.contains('海野'));
    expect(unno, hasLength(1));
    final hit = unno.single.events.single;
    expect(hit.result, Value.CodeGameResult.HIT_SINGLE);
    expect(hit.timely, isTrue);
    expect(hit.stateScore, Value.CodeStateScore.FIRST);
    expect(hit.linguisticRuns, 1);
  });

  test('MLBの適時打と逆転サヨナラを読み分ける', () {
    final doc = parse('''
      <div id="text_live">
        <section class="bb-liveText">
          <div class="bb-liveText__inning">9回裏</div>
          <li class="bb-liveText__item">
            <p class="bb-liveText__batter"><span class="bb-liveText__order">1番</span><a class="bb-liveText__player">J.チョウリオ</a><span class="bb-liveText__state">一死二三塁</span></p>
            <p class="bb-liveText__summary"><span>センターへの逆転サヨナラ2点適時打！ MIL 4-3 CHC</span></p>
          </li>
        </section>
      </div>
    ''');
    final hit = LiveText.parse(doc).halves.single.plates.single.events.single;
    expect(hit.result, Value.CodeGameResult.HIT_SINGLE);
    expect(hit.timely, isTrue);
    expect(hit.stateScore, Value.CodeStateScore.REVERSE);
    expect(hit.goodbye, isTrue);
    expect(hit.scoreLeft, 4);
    expect(hit.scoreRight, 3);
    expect(hit.linguisticRuns, 2);
  });

  test('MLBのタイムリーヒットとサヨナラを本文どおり読む', () {
    final doc = parse('''
      <div id="text_live">
        <section class="bb-liveText">
          <div class="bb-liveText__inning">9回裏</div>
          <li class="bb-liveText__item">
            <p class="bb-liveText__batter"><span class="bb-liveText__order">1番</span><a class="bb-liveText__player">J.チョウリオ</a><span class="bb-liveText__state">一死二三塁</span></p>
            <p class="bb-liveText__summary"><span>6球目を打ってセンターへのタイムリーヒット MIL 4-3 SD サヨナラ！</span></p>
          </li>
        </section>
      </div>
    ''');
    final hit = LiveText.parse(doc).halves.single.plates.single.events.single;
    expect(hit.result, Value.CodeGameResult.HIT_SINGLE);
    expect(hit.timely, isTrue);
    expect(hit.goodbye, isTrue);
    expect(hit.direction, Value.CodePosition.CF);
    expect(hit.scoreLeft, 4);
    expect(hit.scoreRight, 3);
    expect(hit.linguisticRuns, 2);
  });

  test('略称の速報打者をフルネームの出場成績へ写す', () {
    final plates = [
      BoxPlate(
        teamId: 102,
        bottom: true,
        order: 1,
        name: 'ジャクソン・チョウリオ',
        position: '中',
        inning: 9,
        label: '中安',
        result: Value.CodeGameResult.HIT_SINGLE,
        direction: Value.CodePosition.CF,
        totalBases: 1,
        seq: 0,
      ),
    ];
    attachLiveNotes(plates, [
      LivePlateNote(
        inning: 9,
        bottom: true,
        teamId: 102,
        batterName: 'J.チョウリオ',
        battingOrder: 1,
        outs: 1,
        runnerFirst: false,
        runnerSecond: true,
        runnerThird: true,
        battingResult: Value.CodeGameResult.HIT_SINGLE,
        runs: 2,
        homerNumber: 0,
        stateScore: Value.CodeStateScore.REVERSE,
        goodbye: true,
        direction: Value.CodePosition.CF,
        scoreHome: 4,
        scoreAway: 3,
        pitcherId: 0,
        extras: const [],
      ),
    ]);
    expect(plates.single.matched, isTrue);
    expect(plates.single.runs, 2);
    expect(plates.single.goodbye, isTrue);
    expect(plates.single.stateScore, Value.CodeStateScore.REVERSE);
  });

  test('得点推移から本文にない逆転状況を補う', () {
    expect(
      scoreStateFromTransition(
        bottom: true,
        beforeHome: 2,
        beforeAway: 3,
        afterHome: 4,
        afterAway: 3,
      ),
      Value.CodeStateScore.REVERSE,
    );
    expect(
      scoreStateFromTransition(
        bottom: false,
        beforeHome: 2,
        beforeAway: 1,
        afterHome: 2,
        afterAway: 2,
      ),
      Value.CodeStateScore.TIE,
    );
  });

  test('MLB のチーム別テーブルは合計行なしでも先攻後攻を分ける', () {
    final doc = parse('''
      <div id="async-gameBatterStats">
        <table class="bb-statsTable">
          <thead><tr><th>位置</th><th>選手名</th></tr></thead>
          <tbody>
            <tr>
              <td class="bb-statsTable__data--bat">(指)</td>
              <td>ベン・ライス</td>
              <td class="bb-statsTable__data--inning"></td>
              <td class="bb-statsTable__data--inning"></td>
              <td class="bb-statsTable__data--inning"></td>
              <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">右本</div></td>
            </tr>
          </tbody>
        </table>
        <table class="bb-teamScoreTable"><tbody><tr><th>計</th></tr></tbody></table>
        <table class="bb-statsTable">
          <thead><tr><th>位置</th><th>選手名</th></tr></thead>
          <tbody>
            <tr>
              <td class="bb-statsTable__data--bat">(中)</td>
              <td>ヨナタン・アランダ</td>
              <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">中安</div></td>
            </tr>
          </tbody>
        </table>
      </div>
    ''');
    final plates = parseBoxPlates(doc, 10, 30);
    final rice = plates.firstWhere((plate) => plate.name == 'ベン・ライス');
    expect(rice.teamId, 10);
    expect(rice.bottom, isFalse);
    expect(rice.inning, 4);
    expect(rice.result, Value.CodeGameResult.HOME_RUN);
    final aranda = plates.firstWhere((plate) => plate.name == 'ヨナタン・アランダ');
    expect(aranda.teamId, 30);
    expect(aranda.bottom, isTrue);
    expect(aranda.inning, 1);
  });

  test('B.モンゴメリーの速報をフル名の出場成績へ写す', () {
    final doc = parse('''
      <div id="async-gameBatterStats"><table><tbody>
        <tr>
          <td>(左)</td><td>ブレーデン・モンゴメリー</td>
          <td class="bb-statsTable__data--inning"><div class="bb-statsTable__dataDetail">右安</div></td>
        </tr>
      </tbody></table></div>
    ''');
    final plates = parseBoxPlates(doc, 1, 2);
    attachLiveNotes(plates, [
      LivePlateNote(
        inning: 1,
        bottom: false,
        teamId: 1,
        batterName: 'B.モンゴメリー',
        battingOrder: 1,
        outs: 0,
        runnerFirst: false,
        runnerSecond: true,
        runnerThird: false,
        battingResult: Value.CodeGameResult.HIT_SINGLE,
        runs: 1,
        homerNumber: 0,
        stateScore: '',
        goodbye: false,
        direction: '',
        scoreHome: 0,
        scoreAway: 0,
        pitcherId: 9,
        extras: const [],
      ),
    ]);
    expect(plates.single.matched, isTrue);
    expect(plates.single.runs, 1);
  });

  test('打妨と野選を打席結果にする', () {
    expect(classifyBoxPlay('打妨')?.result, Value.CodeGameResult.INTERFERENCE_BATTING);
    expect(classifyBoxPlay('遊野選')?.result, Value.CodeGameResult.FIELDERS_CHOICE);
    expect(classifyBoxPlay('遊野選')?.direction, Value.CodePosition.SS);
  });

  test('新しいイニングが先に来るMLB速報でもツーランホームランを残す', () {
    String plate(int order, String name, String state, String summary) {
      return '''
        <li class="bb-liveText__item">
          <p class="bb-liveText__batter"><span class="bb-liveText__order">$order番</span><a class="bb-liveText__player">$name</a><span class="bb-liveText__state">$state</span></p>
          <p class="bb-liveText__summary"><span>$summary</span></p>
        </li>
      ''';
    }

    String half(String title, String body) {
      return '''
        <section class="bb-liveText">
          <div class="bb-liveText__inning">$title</div>
          $body
        </section>
      ''';
    }

    String lineup(String title, List<String> names) {
      final items = [
        for (var i = 0; i < names.length; i++)
          plate(i + 1, names[i], '無死走者なし', '空振り三振'),
      ].join();
      return half(title, items);
    }

    const early = ['M.ベッツ', 'F.フリーマン', 'T.ヘルナンデス', 'W.スミス', '大谷', 'M.ロハス'];
    const late = ['A.パヘス', 'K.タッカー', 'E.ヘルナンデス'];
    final doc = parse('''
      <div id="text_live">
        ${half('4回表', [
          plate(3, 'T.ヘルナンデス', '二死走者なし', 'レフトフライ　攻撃終了'),
          plate(2, 'F.フリーマン', '二死走者なし', 'ホームラン！　ドジャース得点！ ATL 0-3 LAD'),
          plate(9, 'E.ヘルナンデス', '一死走者1塁', 'ツーランホームラン！　ドジャース得点！ ATL 0-2 LAD'),
          plate(8, 'K.タッカー', '無死走者1塁', 'セカンドライナー　1アウト'),
          plate(7, 'A.パヘス', '無死走者なし', 'レフトへのヒット　ランナー：1塁'),
        ].join())}
        ${lineup('3回表', early)}
        ${lineup('2回表', late)}
        ${lineup('1回表', early)}
      </div>
    ''');
    final live = LiveText.parse(doc);
    final fourth = live.halves.where((half) => half.inning == 4 && !half.bottom).single;
    final hr = fourth.plates.where((plate) => plate.batterName == 'E.ヘルナンデス').single.events.single;
    expect(hr.result, Value.CodeGameResult.HOME_RUN);
    expect(hr.linguisticRuns, 2);
    expect(hr.scoreLeft, 0);
    expect(hr.scoreRight, 2);
  });

  test('速報が無い本塁打でも走者から先制2ランにする', () {
    BoxPlate plate({
      required int seq,
      required int inning,
      required int order,
      required String name,
      required String result,
      required String label,
    }) {
      return BoxPlate(
        teamId: 1,
        bottom: false,
        order: order,
        name: name,
        position: '二',
        inning: inning,
        label: label,
        result: result,
        direction: Value.CodePosition.LF,
        totalBases: result == Value.CodeGameResult.HOME_RUN ? 4 : 1,
        seq: seq,
      );
    }

    final plates = [
      plate(seq: 0, inning: 3, order: 6, name: 'ミゲル・ロハス', result: Value.CodeGameResult.STRIKE_OUT, label: '空三振'),
      plate(seq: 10, inning: 4, order: 1, name: 'ムーキー・ベッツ', result: Value.CodeGameResult.OUT_GROUND, label: '三ゴ'),
      plate(seq: 11, inning: 4, order: 2, name: 'フレディ・フリーマン', result: Value.CodeGameResult.HOME_RUN, label: '右本'),
      plate(seq: 16, inning: 4, order: 7, name: 'アンディ・パヘス', result: Value.CodeGameResult.HIT_SINGLE, label: '左安'),
      plate(seq: 17, inning: 4, order: 8, name: 'カイル・タッカー', result: Value.CodeGameResult.OUT_LINE_DRIVE, label: '二直'),
      plate(seq: 18, inning: 4, order: 9, name: 'エンリケ・ヘルナンデス', result: Value.CodeGameResult.HOME_RUN, label: '左本'),
    ];
    applyBoxPlateScoring(plates);
    final hr = plates.singleWhere((row) => row.name.contains('エンリケ'));
    expect(hr.runs, 2);
    expect(hr.stateScore, Value.CodeStateScore.FIRST);
    expect(hr.runnerFirst, isTrue);
    final freeman = plates.singleWhere((row) => row.name.contains('フリーマン'));
    expect(freeman.runs, 1);
    expect(freeman.stateScore, isEmpty);
  });

  test('E.ヘルナンデスの速報をエンリケの出場成績へ写す', () {
    final plates = [
      BoxPlate(
        teamId: 1,
        bottom: false,
        order: 9,
        name: 'エンリケ・ヘルナンデス',
        position: '二',
        inning: 4,
        label: '左本',
        result: Value.CodeGameResult.HOME_RUN,
        direction: Value.CodePosition.LF,
        totalBases: 4,
        seq: 0,
      ),
    ];
    attachLiveNotes(plates, [
      LivePlateNote(
        inning: 4,
        bottom: false,
        teamId: 1,
        batterName: 'E.ヘルナンデス',
        battingOrder: 9,
        outs: 1,
        runnerFirst: true,
        runnerSecond: false,
        runnerThird: false,
        battingResult: Value.CodeGameResult.HOME_RUN,
        runs: 2,
        homerNumber: 0,
        stateScore: Value.CodeStateScore.FIRST,
        goodbye: false,
        direction: Value.CodePosition.LF,
        scoreHome: 0,
        scoreAway: 0,
        pitcherId: 0,
        extras: const [],
      ),
    ]);
    expect(plates.single.matched, isTrue);
    expect(plates.single.runs, 2);
    expect(plates.single.stateScore, Value.CodeStateScore.FIRST);
  });

  test('ツーラン本文と走者1塁はスコア差1より優先する', () {
    expect(
      preferredLiveRuns(
        result: Value.CodeGameResult.HOME_RUN,
        linguisticRuns: 2,
        runnerFirst: true,
        runnerSecond: false,
        runnerThird: false,
        scoreDelta: 1,
      ),
      2,
    );
    expect(
      preferredLiveRuns(
        result: Value.CodeGameResult.HOME_RUN,
        linguisticRuns: 1,
        runnerFirst: true,
        runnerSecond: false,
        runnerThird: false,
        scoreDelta: 0,
      ),
      2,
    );
  });

  test('読み済みの先制2ランは弱い再計算で上書きしない', () {
    expect(richerStateScore(Value.CodeStateScore.FIRST, ''), Value.CodeStateScore.FIRST);
    expect(richerStateScore(Value.CodeStateScore.FIRST, Value.CodeStateScore.GO_AHEAD), Value.CodeStateScore.FIRST);
    expect(resumeHalfOrd(storedCounts: {2: 9, 4: 6}, boxCounts: {2: 9, 4: 6, 6: 2}), 6);
    expect(resumeHalfOrd(storedCounts: {}, boxCounts: {2: 3}), 0);
  });
}
