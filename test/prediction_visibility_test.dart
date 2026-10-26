import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/logic/prediction_visibility.dart';
import 'package:Yakyuu_Japan/logic/show_user_predictions.dart';

void main() {
  final session = AuthSession.instance;
  tearDown(() { session.user = null; session.token = null; });

  test('API and saved board data lose picks and nested indicators without changing public stats', () {
    final stats = {'name_player': '選手', 'stats': 16, 'colors_user': '/blue/', 'id_users': '/1/2/', 'flg_today': true, 'color_today': 'blue'};
    final original = {
      'predict_team': [{'username': '立石', 'id_team': 1}],
      'predict_player': [{'username': '江島', 'id_player': 2}],
      'orgs': {'npb': {'predictions': [1], 'playerStats': [2], 'playerStatsActual': [stats]}},
      'stats_player': [stats],
      'stats_team': [{'team_name_tateishi': '阪神', 'flg_atari_ejima': true, 'wins': 80, 'color_back': 'yellow'}],
      'games': [{'colors_pitcher_home': 'blue', 'colors_pitcher_away': 'red', 'summary': [{'titles_predict': '立石：最多勝', 'colors_summary': 'blue', 'flg_predict': true, 'name': '選手'}]}],
    };
    final clean = publicPredictionData(original) as Map;
    expect(clean['predict_team'], isNull);
    expect(clean['predict_player'], isNull);
    expect(clean['orgs']['npb']['predictions'], isNull);
    expect(clean['orgs']['npb']['playerStats'], isNull);
    expect(clean['stats_player'], [{'name_player': '選手', 'stats': 16}]);
    expect(clean['stats_team'], [{'wins': 80, 'color_back': 'yellow'}]);
    expect(clean['games'], [{'summary': [{'name': '選手'}]}]);
    expect(publicPredictionData(clean), clean);
    expect(stats['colors_user'], '/blue/');
  });

  test('legacy JSON text summaries are sanitized too', () {
    final result = publicPredictionData({'summaries': '[{"name":"選手","titles_predict":"立石","colors_summary":"blue"}]'}) as Map;
    expect(jsonDecode(result['summaries']), [{'name': '選手'}]);
  });

  testWidgets('scope defaults to hidden and an open dialog-style scope updates on logout', (tester) async {
    Widget label() => Builder(builder: (context) => Text(ShowUserPredictions.of(context) ? '予想あり' : '予想なし'));
    await tester.pumpWidget(MaterialApp(home: label()));
    expect(find.text('予想なし'), findsOneWidget);
    session.user = AuthUser.fromJson({'id': 3});
    session.token = 'authenticated';
    await tester.pumpWidget(MaterialApp(home: ShowUserPredictions(value: true, child: label())));
    expect(find.text('予想あり'), findsOneWidget);
    session.token = null;
    await tester.pump();
    expect(find.text('予想なし'), findsOneWidget);
    session.user = null;
    await tester.pump();
    expect(find.text('予想あり'), findsNothing);
  });
}
