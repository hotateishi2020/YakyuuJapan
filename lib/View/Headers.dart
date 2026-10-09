import 'dart:math' as math;

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
    double? titleTrailingWidth,
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final logoNat = _logoNaturalWidth(h);
                final scoreNat = titleTrailing == null ? 0.0 : (titleTrailingWidth ?? logoNat);
                const gap = 8.0;
                final room = math.max(0.0, constraints.maxWidth - (titleTrailing == null ? 0.0 : gap));
                var logoW = logoNat;
                var scoreW = scoreNat;
                if (titleTrailing != null && logoNat + scoreNat > room) {
                  var overflow = logoNat + scoreNat - room;
                  final logoMin = logoNat * 0.5;
                  final logoCut = math.min(overflow, math.max(0.0, logoNat - logoMin));
                  logoW = logoNat - logoCut;
                  overflow -= logoCut;
                  scoreW = math.max(0.0, scoreNat - overflow);
                  if (logoW + scoreW > room && room > 0) {
                    final scale = room / (logoW + scoreW);
                    logoW *= scale;
                    scoreW *= scale;
                  }
                }
                return Row(
                  children: [
                    Transform.translate(
                      offset: Offset(0, paddingVertical * 0.3),
                      child: _titleLogo(h, title, maxWidth: logoW),
                    ),
                    if (titleTrailing != null) ...[
                      const Spacer(),
                      const SizedBox(width: gap),
                      SizedBox(width: scoreW, child: titleTrailing),
                    ],
                  ],
                );
              },
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

double _logoNaturalWidth(double headerH) {
  return _logoTextW * (headerH * 0.7) / _logoTextH;
}

Widget _titleLogo(double headerH, String title, {double? maxWidth}) {
  final textH = headerH * 0.7;
  var scale = textH / _logoTextH;
  if (maxWidth != null && maxWidth > 0) {
    final naturalW = _logoTextW * scale;
    if (naturalW > maxWidth) scale *= maxWidth / naturalW;
  }
  return SizedBox(
    width: _logoTextW * scale,
    height: _logoTextH * scale,
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
