import 'package:test/test.dart';
import '../app/LowerLevelUsage.dart';

void main() {
  test('farm schedules include completed games only, and deduplicate links',
      () {
    const done =
        '<tr><td><div class="score1">2</div><div class="score2">1</div><a href="/scores_farm/2026/0901/g-b-01/">結果</a></td></tr>';
    expect(
        farmGameUrls(
            '<table>$done$done<tr><td><a href="/scores_farm/2026/0902/g-b-02/">中止</a></td></tr></table>',
            2026),
        ['https://npb.jp/scores_farm/2026/0901/g-b-01/box.html']);
  });
  test('farm-only opponent IDs are not required; substitutes and changes count',
      () {
    const source = '''<p class="game_info">試合終了</p>
      <div id="table_top_p"><table><tbody>
      <tr><td></td><td><a href="/bis/players/1.html">先発</a></td><td></td><td></td><td>3</td></tr>
      <tr><td></td><td><a href="/bis/players/2.html">救援</a></td><td></td><td></td><td>1</td></tr>
      </tbody></table></div>
      <div id="table_top_b"><table><tbody>
      <tr><td>1</td><td>(左)中</td><td><a href="/bis/players/3.html">野手</a></td></tr>
      <tr><td></td><td>走右</td><td><a href="/bis/players/4.html">途中</a></td></tr>
      <tr><td></td><td>打</td><td><a href="/bis/players/5.html">代打</a></td></tr>
      </tbody></table></div>''';
    final players = parseFarmGame(
        source, 'https://npb.jp/scores_farm/2026/0901/v-g-01/box.html');
    final game = {'game_key': 'g1', 'players': players};
    final result = aggregateLowerUsage([game, game], 'g');
    expect(result['npb:1']!['starts'], 1);
    expect(result['npb:2']!['relief'], 1);
    expect(result['npb:3']!['positions'], {'LF': 1, 'CF': 1});
    expect(result['npb:4']!['positions'], {'RF': 1});
    expect(result['npb:5']!['positions'], isEmpty);
    expect(result['npb:3']!['appearances'], 1);
    expect(aggregateLowerUsage([game], 'b'), isEmpty);
  });
}
