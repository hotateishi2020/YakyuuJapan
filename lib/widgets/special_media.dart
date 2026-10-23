import 'package:flutter/material.dart';
import '../logic/auth_session.dart';

/// Do not mount or fetch restricted images for guests or ordinary users.
/// Listen directly so logout also clears images in retained pages and dialogs.
class SpecialMedia extends StatelessWidget {
  const SpecialMedia({super.key, required this.child, this.fallback = const SizedBox.shrink()});
  final Widget child, fallback;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthSession.instance,
    builder: (_, __) => AuthSession.instance.showSpecialMedia ? child : fallback,
  );
}
