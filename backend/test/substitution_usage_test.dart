import 'package:test/test.dart';
import '../app/StrengthUsage.dart';

void main() {
  test('途中出場の最初の役割で集計し先発の守備変更と投手交代を除外', () {
    String batter(String order, String pos, int id) =>
        '<tr><td>$order</td><td>$pos</td><td><a href="/bis/players/$id.html">選手$id</a></td></tr>';
    final source = '<div class="game_info">試合終了</div>'
        '${[
      for (final side in ['top', 'bottom'])
        "<div id=\"table_${side}_p\"><table><tbody><tr><td></td><td><a href=\"/bis/players/99.html\">投手</a></td><td></td><td></td><td>9</td></tr></tbody></table></div><div id=\"table_${side}_b\"><table><tbody>${batter('1', '(中)左', 1)}${batter('', '打中', 2)}${batter('', '走二', 3)}${batter('', '捕', 4)}${batter('', '投', 5)}</tbody></table></div>"
    ].join()}';
    final rows = parseNpbSubstitutions(
        source, 'https://npb.jp/scores/2026/1001/t-g-25/box.html');
    expect(rows.length, 6);
    expect(rows.take(3).map((p) => p['role']), ['PH', 'PR', 'DEF']);
    expect(rows.first['team_code'], 'g');
    expect(rows.last['team_code'], 't');
    final game = {
      'game_key': 'one',
      'substitutions': [...rows, rows.first]
    };
    final bands = substitutionBands([game, game], 'g');
    expect(bands.map((b) => b['total']), [1, 1, 1]);
    expect(usageMaps(bands.first['players']).first['player_key'], 'npb:2');
  });
  test('MLBは交代打順と最初の守備位置から途中出場を判定', () {
    final rows = parseMlbSubstitutions({
      'teams': {
        for (final side in ['home', 'away'])
          side: {
            'team': {'id': side},
            'players': {
              for (final item in [
                ('100', 'CF'),
                ('101', 'PH'),
                ('201', 'PR'),
                ('301', 'SS'),
                ('901', 'P')
              ])
                item.$1: {
                  'person': {'id': item.$1, 'fullName': item.$1},
                  'battingOrder': item.$1,
                  'allPositions': [
                    {'abbreviation': item.$2}
                  ]
                }
            }
          }
      }
    });
    expect(rows.length, 6);
    expect(rows.take(3).map((p) => p['role']), ['PH', 'PR', 'DEF']);
  });
}
