import 'package:test/test.dart';
import '../app/PlayerAchievements.dart';

void main() {
  test('オールスター選出は年と公式選手IDで重複を除く', () {
    final result = npbAllStarEntries(
        '<table><tr><td><a href="/bis/players/123.html">選手</a></td></tr><tr><td><a href="/bis/players/123.html">選手</a></td></tr></table>',
        2026,
        'https://npb.jp/allstar/2026/roster.html');
    expect(result.keys, ['npb:123']);
    expect(result['npb:123']!.single['label'], 'オールスター選出');
    expect(result['npb:123']!.single['year'], 2026);
  });
}
