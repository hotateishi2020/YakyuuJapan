import 'package:flutter/widgets.dart';
import 'auth_session.dart';

/// User predictions are opt-in and require a live authenticated session.
/// Listen here too: dialogs and retained tabs can outlive the page that opened them.
class ShowUserPredictions extends StatelessWidget {
  final bool value;
  final Widget child;

  const ShowUserPredictions({super.key, required this.value, required this.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PredictionVisibility>()?.value ?? false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthSession.instance,
    builder: (context, _) => _PredictionVisibility(
      value: value && AuthSession.instance.isLoggedIn,
      child: child,
    ),
  );
}

class _PredictionVisibility extends InheritedWidget {
  final bool value;
  const _PredictionVisibility({required this.value, required super.child});
  @override
  bool updateShouldNotify(_PredictionVisibility oldWidget) => value != oldWidget.value;
}
