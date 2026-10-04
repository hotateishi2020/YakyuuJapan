import 'package:flutter/widgets.dart';

/// ログイン済みのときだけユーザー予想・SCORE・予想色などを表示する。
class ShowUserPredictions extends InheritedWidget {
  final bool value;

  const ShowUserPredictions({
    super.key,
    required this.value,
    required super.child,
  });

  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShowUserPredictions>();
    return scope?.value ?? true;
  }

  @override
  bool updateShouldNotify(ShowUserPredictions oldWidget) => value != oldWidget.value;
}
