import 'package:flutter/material.dart';

import '../config/app_design.dart';
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
    Widget? titleTrailing,
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
      padding: EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                // 文字の見た目が上に寄るので、ヘッダー中央よりほんの少し下へ。
                Transform.translate(
                  offset: Offset(0, paddingVertical * 0.3),
                  child: _titleLogo(h, title),
                ),
                if (titleTrailing != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: titleTrailing),
                ],
              ],
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

/// logo_yakyuu_japan.png は 1024×341 で、白い文字は余白の中にある。
/// 文字の高さがヘッダーの約7割になるよう、文字の範囲だけを切り出す。
const _logoTextLeft = 61.0;
const _logoTextTop = 82.0;
const _logoTextW = 942.0;
const _logoTextH = 162.0;
const _logoImgW = 1024.0;
const _logoImgH = 341.0;

Widget _titleLogo(double headerH, String title) {
  final textH = headerH * 0.7;
  final scale = textH / _logoTextH;
  return SizedBox(
    width: _logoTextW * scale,
    height: textH,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        maxWidth: _logoImgW * scale,
        minHeight: 0,
        maxHeight: _logoImgH * scale,
        child: Transform.translate(
          offset: Offset(-_logoTextLeft * scale, -_logoTextTop * scale),
          child: Image.asset(
            'backend/assets/images/logo_yakyuu_japan.png',
            width: _logoImgW * scale,
            height: _logoImgH * scale,
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            semanticLabel: title,
          ),
        ),
      ),
    ),
  );
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, TAB_BAR_H),
        maximumSize: const Size(double.infinity, TAB_BAR_H),
        fixedSize: const Size.fromHeight(TAB_BAR_H),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TAB_RADIUS)),
      ),
      child: const Text('Login', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}
