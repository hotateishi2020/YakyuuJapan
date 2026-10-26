import 'package:test/test.dart';
import '../app/PostseasonForm.dart';
import '../../lib/logic/postseason_homers.dart';

void main() {
  test('CSと日本シリーズのみ同年度・当該試合より前の本塁打を通算する', () {
    final game = <String, dynamic>{'code_game': 'JS', 'date_game': '2026-10-25', 'time_game': '18:00', 'id_team_home': 1, 'id_team_away': 2};
    final records = [
      for (final r in [
        ['2026-09-01 18:00', 'S', 30],
        ['2026-10-10 18:00', 'CS1', 1],
        ['2026-10-17 18:00', 'CSF', 2],
        ['2026-10-24 18:00', 'JS', 1],
        ['2026-10-25 18:00', 'JS', 2],
        ['2026-10-26 18:00', 'JS', 1],
        ['2025-10-24 18:00', 'JS', 5],
      ]) <String, dynamic>{'id_player': 10, 'name_full': '打者', 'current_team': 1, 'start': r[0], 'code_game': r[1], 'int_homerun': r[2]},
    ];
    attachFormsFromRecords([game], records, []);
    expect((game['postseason_homers_before'] as List).single['homers'], 4);
  });
  test('複数本を順に採番し既存のシーズン号数と置き換える', () {
    const plays = '1回表40号ソロホームラン^左|hr/rbi1 三振|out 8回表2ランホームラン^中|hr/rbi2';
    final numbered = numberPostseasonHomers(plays, 4);
    expect(numbered, '1回表PS5号ソロホームラン^左|hr/rbi1 三振|out 8回表PS6号2ランホームラン^中|hr/rbi2');
    expect(numberPostseasonHomers(numbered, 4), numbered);
    expect(numberPostseasonHomers('ソロホームラン|hr', 0), 'PS1号ソロホームラン|hr');
  });
}
