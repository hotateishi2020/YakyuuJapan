import 'package:flutter/material.dart';
import 'package:Yakyuu_Japan/logic/high_school_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/View/EventCalendar.dart';

void main() {
  tearDown(() {
    AuthSession.instance.user = null;
    AuthSession.instance.token = null;
  });
  testWidgets(
      'calendar follows favorite school and removes personal events on logout',
      (tester) async {
    await tester.runAsync(loadHighSchoolCalendar);
    AuthSession.instance.token = 'test';
    AuthSession.instance.user =
        AuthUser.fromJson({'id': 3, 'favorite_high_school': '佐賀北'});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EventCalendar(
      events: const [],
      initialMonth: DateTime(2026, 10),
    ))));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.textContaining('佐賀北'), findsWidgets);
    expect(find.textContaining('早稲田佐賀'), findsWidgets);
    AuthSession.instance.user =
        AuthUser.fromJson({'id': 3, 'favorite_high_school': '長野日大'});
    await tester.pumpAndSettle();
    expect(find.textContaining('佐賀北'), findsNothing);
    expect(find.textContaining('早稲田佐賀'), findsNothing);
    AuthSession.instance.user = null;
    await tester.pumpAndSettle();
    expect(find.textContaining('九州大会'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
