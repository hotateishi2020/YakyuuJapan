import 'package:Yakyuu_Japan/View/LeagueLogo.dart';
import 'package:Yakyuu_Japan/View/PostseasonBracket.dart';
import 'package:Yakyuu_Japan/View/MlbPostseasonBracket.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/widgets/special_media.dart';
import 'package:Yakyuu_Japan/View/PredictGroupBoard.dart';

void main() {
  final session = AuthSession.instance;
  tearDown(() {
    session.user = null;
    session.token = null;
  });
  for (final item in <String, Widget>{
    'リーグ': const LeagueLogo(asset: 'backend/assets/images/k-central.webp', height: 24),
    'NPBトーナメント': const PostseasonBracket(standings: [], games: []),
    'MLBトーナメント': const MlbPostseasonBracket(standings: [], games: []),
  }.entries) {
    testWidgets('${item.key}のリーグ・シリーズ画像は特別ユーザーだけ表示', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: item.value)));
      expect(find.byType(Image), findsNothing);
      session.token = 'test';
      session.user = AuthUser.fromJson({'id': 3, 'flg_special': true});
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      session.user = AuthUser.fromJson({'id': 1, 'flg_special': false});
      await tester.pump();
      expect(find.byType(Image), findsWidgets);
      session.user = AuthUser.fromJson({'id': 3, 'flg_special': true});
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      session.user = AuthUser.fromJson({'id': 2, 'flg_special': false});
      await tester.pump();
      expect(find.byType(Image), findsWidgets);
      session.token = null;
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      if (item.key == 'NPBトーナメント') expect(find.text('日本シリーズ'), findsOneWidget);
      if (item.key == 'MLBトーナメント') expect(find.text('WORLD SERIES'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  test('special flag defaults to false and survives serialization', () {
    expect(AuthUser.fromJson({'id': 1}).special, isFalse);
    final user = AuthUser.fromJson({'id': 2, 'flg_special': true});
    expect(AuthUser.fromJson(user.toJson()).special, isTrue);
  });
  testWidgets('media is mounted only with special user and active session', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SpecialMedia(fallback: Text('name'), child: Text('restricted'))));
    expect(find.text('restricted'), findsNothing);
    session.user = AuthUser.fromJson({'id': 1, 'flg_special': false});
    await tester.pump();
    expect(find.text('restricted'), findsNothing);
    session.token = 'test';
    await tester.pump();
    expect(find.text('restricted'), findsOneWidget);
    session.user = AuthUser.fromJson({'id': 3, 'flg_special': true});
    await tester.pump();
    expect(find.text('restricted'), findsNothing);
    session.user = AuthUser.fromJson({'id': 2, 'flg_special': false});
    await tester.pump();
    expect(find.text('restricted'), findsOneWidget);
    session.token = null;
    await tester.pump();
    expect(find.text('restricted'), findsNothing);
  });
  testWidgets('prediction keeps team name and hides logo on logout', (tester) async {
    session.user = AuthUser.fromJson({'id': 1, 'flg_special': false});
    session.token = 'test';
    await tester.pumpWidget(MaterialApp(home: predictTeamLabels('巨人', const TextStyle())));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('巨人'), findsOneWidget);
    session.user = null;
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('巨人'), findsOneWidget);
  });
}
