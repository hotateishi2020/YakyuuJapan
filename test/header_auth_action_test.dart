import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/Headers.dart';
import 'package:Yakyuu_Japan/config/app_design.dart';

void main() {
  testWidgets('board load shows a spinner instead of Login', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeaderAuthAction(loggedIn: false, boardReady: false),
        ),
      ),
    );
    expect(find.text('Login'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('logout keeps the spinner until reload finishes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeaderAuthAction(loggedIn: false, boardReady: false),
        ),
      ),
    );
    expect(find.text('Login'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeaderAuthAction(loggedIn: false, boardReady: true),
        ),
      ),
    );
    expect(find.text('Login'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Login appears after the board is ready', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeaderAuthAction(loggedIn: false, boardReady: true),
        ),
      ),
    );
    expect(find.text('Login'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(find.widgetWithText(TextButton, 'Login')).height, TAB_BAR_H);
  });

  testWidgets('logged-in users see the account icon even while the board loads', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeaderAuthAction(loggedIn: true, boardReady: false),
        ),
      ),
    );
    expect(find.text('Login'), findsNothing);
    expect(find.byIcon(Icons.account_circle), findsOneWidget);
  });

  testWidgets('account menu offers password change', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeaderAuthAction(loggedIn: true, boardReady: true),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.account_circle));
    await tester.pumpAndSettle();
    expect(find.text('パスワード変更'), findsOneWidget);
  });
}
