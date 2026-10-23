import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/season_titles.dart';
import 'package:Yakyuu_Japan/View/season_titles_table.dart';

void main() {
  final data = <String, dynamic>{
    'season_awards': {'pages': {'series': [
      {'key': 'series_entrants', 'name': '横浜DeNAベイスターズ', 'team': '', 'detail': '', 'confirmed': true},
      {'key': 'series_entrants', 'name': '福岡ソフトバンクホークス', 'team': '', 'detail': '', 'confirmed': true},
    ]}},
    'season_award_supplement': [
      {'key': 'series_entrants', 'name': '横浜DeNAベイスターズ', 'team': '横浜DeNAベイスターズ', 'detail': 'セ・リーグ CS優勝', 'confirmed': true},
      {'key': 'series_entrants', 'name': '福岡ソフトバンクホークス', 'team': '福岡ソフトバンクホークス', 'detail': 'パ・リーグ CS優勝', 'confirmed': true},
      {'key': 'series_entrants', 'name': 'ソフトバンク', 'detail': '日本シリーズ進出', 'confirmed': true},
    ],
  };
  test('出典・説明・球団名表記が異なってもCS優勝は同一球団を一度だけ採用する', () {
    final rows = buildSeasonTitles(data, 2026)['series_entrants']!;
    expect(rows.map((r) => r['name']), ['横浜DeNAベイスターズ', '福岡ソフトバンクホークス']);
  });
  for (final portrait in [false, true]) {
    testWidgets('CS優勝セルは各リーグの球団を一度だけ表示 portrait=$portrait', (tester) async {
      await tester.binding.setSurfaceSize(Size(portrait ? 375 : 1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final table = SeasonTitlesTable(groups: buildSeasonTitles(data, 2026), year: 2026);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: table.leagueAwards(portrait ? 375 : 1400, portrait: portrait))));
      await tester.pumpAndSettle();
      expect(find.text('横浜DeNAベイスターズ'), findsOneWidget);
      expect(find.text('福岡ソフトバンクホークス'), findsOneWidget);
      expect(find.text('ソフトバンク'), findsNothing);
      expect(find.text('CS優勝'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
