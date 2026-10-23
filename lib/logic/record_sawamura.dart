import 'record_awards.dart';

// Historical recipient facts; 2007 onward cross-checked against cached NPB awards.
// https://www.my-favorite-giants.net/npb/title/pitcher_sawamura.htm
// https://npb.jp/award/2025/shosawa.html
const _recipients = '''
1947 別所昭 南海
1948 中尾碩志 巨人
1949 藤本英雄 巨人
1950 真田重男 松竹
1951 杉下茂 名古屋
1952 杉下茂 名古屋
1953 大友工 巨人
1954 杉下茂 中日
1955 別所毅彦 巨人
1956 金田正一 国鉄
1957 金田正一 国鉄
1958 金田正一 国鉄
1959 村山実 大阪
1960 堀本律雄 巨人
1961 権藤博 中日
1962 小山正明 阪神
1963 伊藤芳明 巨人
1964 G.バッキー 阪神
1965 村山実 阪神
1966 村山実 阪神
1966 堀内恒夫 巨人
1967 小川健太郎 中日
1968 江夏豊 阪神
1969 高橋一三 巨人
1970 平松政次 大洋
1972 堀内恒夫 巨人
1973 高橋一三 巨人
1974 星野仙一 中日
1975 外木場義郎 広島
1976 池谷公二郎 広島
1977 小林繁 巨人
1978 松岡弘 ヤクルト
1979 小林繁 阪神
1981 西本聖 巨人
1982 北別府学 広島
1983 遠藤一彦 大洋
1985 小松辰雄 中日
1986 北別府学 広島
1987 桑田真澄 巨人
1988 大野豊 広島
1989 斎藤雅樹 巨人
1990 野茂英雄 近鉄
1991 佐々岡真司 広島
1992 石井丈裕 西武
1993 今中慎二 中日
1994 山本昌広 中日
1995 斎藤雅樹 巨人
1996 斎藤雅樹 巨人
1997 西口文也 西武
1998 川崎憲次郎 ヤクルト
1999 上原浩治 巨人
2001 松坂大輔 西武
2002 上原浩治 巨人
2003 井川慶 阪神
2003 斉藤和巳 ダイエー
2004 川上憲伸 中日
2005 杉内俊哉 ソフトバンク
2006 斉藤和巳 ソフトバンク
2007 ダルビッシュ有 日本ハム
2008 岩隈久志 楽天
2009 涌井秀章 西武
2010 前田健太 広島
2011 田中将大 楽天
2012 攝津正 ソフトバンク
2013 田中将大 楽天
2014 金子千尋 オリックス
2015 前田健太 広島
2016 K.ジョンソン 広島
2017 菅野智之 巨人
2018 菅野智之 巨人
2020 大野雄大 中日
2021 山本由伸 オリックス
2022 山本由伸 オリックス
2023 山本由伸 オリックス
2025 伊藤大海 日本ハム
''';

final _byYear = <int, List<Map<String, dynamic>>>{
  for (final year in _recipients.trim().split('\n').map((line) => int.parse(line.split(' ').first)).toSet())
    year: [for (final line in _recipients.trim().split('\n'))
      if (line.startsWith('$year ')) {
        'name': line.split(' ')[1], 'team': line.split(' ')[2], 'value': '受賞',
        'source': year >= 2007 ? 'https://npb.jp/award/$year/shosawa.html'
            : 'https://www.my-favorite-giants.net/npb/title/pitcher_sawamura.htm',
      }],
};

/// Fill historical gaps only. An API-provided award, including no recipient,
/// always takes precedence. League ownership is the team at the time of award.
List<Map<String, dynamic>> withRecordSawamura(List<Map<String, dynamic>> seasons) => [
  for (final season in seasons) () {
    final categories = normalizeRecordAwards([
      for (final category in season['categories'] as List? ?? const [])
        Map<String, dynamic>.from(category as Map),
    ]);
    if (!categories.any((c) => c['label'] == '沢村賞')) {
      final year = int.tryParse('${season['year']}');
      final league = '${season['league']}'.replaceAll(RegExp(r'[・\s]'), '');
      final players = (_byYear[year] ?? const <Map<String, dynamic>>[]).where((p) {
        if (year! < 1950) return league == '日本野球連盟';
        final pacific = const {'近鉄', '西武', 'ダイエー', 'ソフトバンク', '日本ハム', '楽天', 'オリックス'}.contains(p['team']);
        return league == (pacific ? 'パリーグ' : 'セリーグ');
      }).toList();
      categories.add({'label': '沢村賞', 'players': players});
    }
    return {...season, 'categories': categories};
  }(),
];
