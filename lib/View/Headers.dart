import 'package:flutter/material.dart';

import '../logic/auth_session.dart';
import 'AccountDialogs.dart';
import 'AuthDialogs.dart';

class Headers {
  static Widget globalHeader(
    BuildContext context,
    double h,
    Color color,
    String title,
    double paddingVertical,
    double paddingHorizontal, {
    VoidCallback? onAuthChanged,
    List<Widget> actions = const [],
    bool authReady = true,
  }) {
    final loggedIn = AuthSession.instance.isLoggedIn;

    return Container(
      height: h,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFE10600), Color(0xFFFF9800)],
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: paddingVertical),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'backend/assets/images/logo_yakyuu_japan.png',
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                semanticLabel: title,
              ),
            ),
          ),
          ...actions,
          HeaderAuthAction(
            loggedIn: loggedIn,
            boardReady: authReady,
            onAuthChanged: onAuthChanged,
          ),
        ],
      ),
    );
  }
}

/// 初期の試合・順位・成績の読み込みが終わるまで Login を出さない。
class HeaderAuthAction extends StatelessWidget {
  const HeaderAuthAction({
    super.key,
    required this.loggedIn,
    required this.boardReady,
    this.onAuthChanged,
  });

  final bool loggedIn;
  final bool boardReady;
  final VoidCallback? onAuthChanged;

  @override
  Widget build(BuildContext context) {
    if (loggedIn) {
      return Builder(
        builder: (iconContext) {
          return IconButton(
            tooltip: 'アカウント',
            onPressed: () => showAccountMenu(iconContext, onChanged: onAuthChanged),
            icon: const Icon(Icons.account_circle, color: Colors.white, size: 28),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          );
        },
      );
    }
    if (!boardReady) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      );
    }
    return TextButton(
      onPressed: () async {
        final ok = await showLoginDialog(context);
        if (ok) onAuthChanged?.call();
      },
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black38,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('Login', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}
