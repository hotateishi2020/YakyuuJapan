/// Yahoo 表示名 → DB の m_team.name_short への正規化。
class YahooTeamNames {
  static const Map<String, String> _aliases = {
    // MLB 短縮表記
    'Rソックス': 'レッドソックス',
    'Wソックス': 'ホワイトソックス',
    'Dバックス': 'ダイヤモンドバックス',
    'ブリュワーズ': 'ブルワーズ',
    'ダイヤモンドバックス': 'ダイヤモンドバックス',
    // NPB 互換（念のため）
    'DeNA': 'DeNA',
    'ＤｅＮＡ': 'DeNA',
  };

  static String normalize(String raw) {
    var text = raw.replaceAll(RegExp(r'\s+'), '').trim();
    if (text.isEmpty) return text;
    // 「ボストン・レッドソックス」→「レッドソックス」
    if (text.contains('・')) {
      final parts = text.split('・').where((e) => e.isNotEmpty).toList();
      if (parts.isNotEmpty) text = parts.last;
    }
    return _aliases[text] ?? text;
  }
}
