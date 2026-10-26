import 'package:html/parser.dart';
import 'package:test/test.dart';
import '../app/LiveText.dart';

void main() {
  test('文章形式の継投と、打席重複除去で落ちた打席の継投を保持する', () {
    String item(String changes) => '''<li class="bb-liveText__item">
      <p class="bb-liveText__batter"><span class="bb-liveText__order">1番</span>
      <a class="bb-liveText__player">打者</a><span class="bb-liveText__state">無死</span></p>
      $changes<p class="bb-liveText__summary">空振り三振 1アウト</p></li>''';
    final parsed = LiveText.parse(parse('''<div id="text_live"><section class="bb-liveText">
      <h3 class="bb-liveText__inning">1回裏</h3><ul>
      ${item('<p class="bb-liveText__summary bb-liveText__summary--change"><span>ピッチャー</span><a>モイネロ</a><span>に代わって</span><a>松本裕</a><span>がマウンドにあがる　守備変更:</span><a>近藤</a><span>ライト→レフト</span></p>')}
      ${item('')}
      <li class="bb-liveText__item"><p class="bb-liveText__batter"><span class="bb-liveText__order">2番</span><a class="bb-liveText__player">次打者</a></p><p class="bb-liveText__summary">空振り三振</p></li>
      <li class="bb-liveText__item"><p class="bb-liveText__batter"><span class="bb-liveText__order">2番</span><a class="bb-liveText__player">次打者</a></p><p class="bb-liveText__summary">空振り三振</p></li>
      <li class="bb-liveText__item"><p class="bb-liveText__batter"><span class="bb-liveText__order">2番</span><a class="bb-liveText__player">次打者</a></p><p class="bb-liveText__summary bb-liveText__summary--change"><span>投手交代:</span><a>松本裕</a><span>→</span><a>鈴木豪</a></p><p class="bb-liveText__summary">空振り三振</p></li>
      </ul></section></div>'''));
    final events = parsed.halves.single.plates.expand((p) => p.events).toList();
    expect(events.where((e) => e.pitcherChange).map((e) => '${e.exitName}→${e.enterName}'), ['モイネロ→松本裕', '松本裕→鈴木豪']);
    expect(events.where((e) => e.result == 'CHANGE_POSITION').single.enterName, '近藤');
    expect(events.where((e) => e.result == 'STRIKE_OUT').length, 4);
  });
}
