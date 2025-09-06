import 'package:flutter/material.dart';

class Tabs {
  // 画面切替タブ（ダミー表示）
  static Widget tabsBar(List<String> titles, double h_bar, Color colorBack, Color colorFont, double radius, double marginTabs, double paddingTabH, double paddingTabV) {
    return SizedBox(
      height: h_bar,
      child: Row(children: [
        for (final t in titles) ...[
          Container(
            margin: EdgeInsets.only(right: marginTabs),
            padding: EdgeInsets.symmetric(horizontal: paddingTabH, vertical: paddingTabV),
            decoration: BoxDecoration(color: colorBack, borderRadius: BorderRadius.circular(radius)),
            child: Text(t, style: TextStyle(fontSize: h_bar / 2)),
          ),
        ]
      ]),
    );
  }
}
