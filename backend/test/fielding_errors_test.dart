import 'package:test/test.dart';
import '../app/FieldingErrors.dart';

void main() {
  test('打席のない投手の失策を含め、重複行を加算せず試合・球団を分離する', () {
    final result = fieldingErrorsByGame([
      {
        'id_game': 3349,
        'id_team': 21,
        'name_full': 'ヘンダーソン',
        'int_error': 2,
        'int_batting': 0
      },
      {'id_game': 3349, 'id_team': 21, 'name_full': 'ヘンダーソン', 'int_error': 2},
      {'id_game': 3349, 'id_team': 22, 'name_full': '選手A', 'int_error': 1},
      {'id_game': 3350, 'id_team': 21, 'name_full': 'ヘンダーソン', 'int_error': 1},
      {'id_game': 3349, 'id_team': 21, 'name_full': '選手B', 'int_error': 0},
    ]);
    expect(result[3349], [
      {'id_team': 21, 'name': 'ヘンダーソン', 'count': 2},
      {'id_team': 22, 'name': '選手A', 'count': 1},
    ]);
    expect(result[3350]!.single['count'], 1);
  });
}
