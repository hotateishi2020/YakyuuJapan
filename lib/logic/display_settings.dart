import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../tools/browser_cookie.dart';

const playerMarkDescriptions = <String, (String, String)>{
  'flg_under21': ('🌱', '表示年の年末時点で21歳以下'),
  'flg_rookie': ('🔰', '新人資格のある選手（登録済みの資格判定）'),
  'flg_career_this_year': ('✨', '表示中の団体（NPB・MLB）で初年度'),
  'flg_age35': ('🍁', '表示年の年末時点で35歳以上'),
  'flg_retired': ('💐', '表示年に引退した選手'),
  'flg_injury': ('🤕', '故障情報が登録されている選手'),
  'flg_japan': ('🇯🇵', 'MLBの日本出身選手'),
  'flg_samurai': ('侍', '侍ジャパン選出歴（黒：WBC／赤：五輪／藍：プレミア12／灰：その他）'),
  'flg_saga': ('佐', '佐賀県出身の選手'),
};

class DisplaySettings extends ValueNotifier<Set<String>> {
  DisplaySettings._() : super(_read());
  static final instance = DisplaySettings._();
  static Set<String> _read() {
    Set<String> hidden;
    try {
      hidden = (jsonDecode(readBrowserCookie('koko_hidden_player_marks') ?? '[]')
              as List)
          .whereType<String>()
          .toSet();
    } catch (_) {
      hidden = {'flg_samurai'};
    }
    // Apply the requested reset once per browser, preserving other marks and
    // allowing users to enable the samurai mark again afterwards.
    if (readBrowserCookie('koko_samurai_hidden_reset_v1') != 'true') {
      hidden.add('flg_samurai');
      writeBrowserCookie('koko_hidden_player_marks', jsonEncode(hidden.toList()));
      writeBrowserCookie('koko_samurai_hidden_reset_v1', 'true');
    }
    return hidden;
  }

  bool shows(String key) => !value.contains(key);
  void setShown(String key, bool shown) {
    final hidden = {...value};
    if (shown) {
      hidden.remove(key);
    } else {
      hidden.add(key);
    }
    value = hidden;
    writeBrowserCookie('koko_hidden_player_marks', jsonEncode(value.toList()));
  }
}
