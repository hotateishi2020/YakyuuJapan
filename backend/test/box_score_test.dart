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
}
