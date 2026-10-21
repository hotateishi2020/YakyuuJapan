class VideoChannel {
  const VideoChannel(this.id, this.name, this.category, this.sourceUrl,
      {this.tabLabel,
      this.contentFilter,
      this.unknownToNpb = false,
      this.daily = false,
      this.league,
      this.videoOrg,
      this.color,
      this.teamIds = const [],
      this.keywords = const [],
      this.includeStreams = false,
      this.lookbackDays = 1,
      this.minimumVideos = 0});
  final String? contentFilter;
  final bool unknownToNpb;
  final String id;
  final String name;
  final String category;
  final String sourceUrl;
  final String? tabLabel;
  final bool daily;
  final String? league;
  final String? videoOrg;
  final String? color;
  final bool includeStreams;
  final int lookbackDays;
  final int minimumVideos;
  final List<String> teamIds;
  final List<String> keywords;
  VideoChannel forVideoOrg(String org) =>
      VideoChannel(id, name, category, sourceUrl,
          videoOrg: org,
          contentFilter: contentFilter,
          unknownToNpb: unknownToNpb,
          tabLabel: tabLabel,
          daily: daily,
          league: league,
          color: color,
          teamIds: teamIds,
          keywords: keywords,
          includeStreams: includeStreams,
          lookbackDays: lookbackDays,
          minimumVideos: minimumVideos);
  int get limit => category == 'tver' ||
          category == 'teams' ||
          category == 'related' ||
          category == 'broadcast'
      ? 30
      : ['media', 'program', 'fan'].contains(category)
          ? 10
          : 4;
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        if (league != null) 'league': league,
        if (color != null) 'color': color,
        'tab_label': tabLabel ?? name,
        'display_mode': category == 'tver'
            ? 'all'
            : daily
                ? 'recent'
                : 'latest',
        'display_limit': limit,
        if (daily) 'lookback_days': lookbackDays,
        if (minimumVideos > 0) 'minimum_videos': minimumVideos,
        'url': category == 'tver'
            ? sourceUrl
            : 'https://www.youtube.com/channel/$id',
        if (category == 'tver') 'platform': 'tver',
      };
}

// Official channel identities verified on 2026-10-18. sourceUrl records provenance.
const videoChannels = <VideoChannel>[
  VideoChannel('UCiLrlqt9mfRGeAugoYqON7g', '工藤公康 official YouTubeチャンネル', 'ob', 'https://www.youtube.com/@kimiyasukudo_official', tabLabel: '工藤公康', videoOrg: 'npb', unknownToNpb: true, contentFilter: 'baseball'),
  VideoChannel('UCwPaG8zQJvsCwiTstXcx8ng', 'B-モレル B桑', 'fan', 'https://www.youtube.com/channel/UCwPaG8zQJvsCwiTstXcx8ng', videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UCIgvsl9EWxnXzSm9aoXp-lQ', 'ギー太 ホークス応援チャンネル', 'fan', 'https://www.youtube.com/channel/UCIgvsl9EWxnXzSm9aoXp-lQ', videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UCchbZjsjbnsk1RYSam4_OAg', 'クラチくんch【西武ライオンズ】', 'fan', 'https://www.youtube.com/channel/UCchbZjsjbnsk1RYSam4_OAg', videoOrg: 'npb', unknownToNpb: true),
  VideoChannel("UC0v-pxTo1XamIDE-f__Ad0Q", "(パーソル パ・リーグTV公式)PacificLeagueTV",
      "league", "https://www.pacificleague.jp/service/",
      daily: true, includeStreams: true, lookbackDays: 2, minimumVideos: 10),
  VideoChannel(
      "UCXxg0igSYUp0tqdd6luPEnQ", "読売ジャイアンツ", "teams", "https://www.giants.jp/",
      tabLabel: '巨人', league: 'central', color: '#F58220'),
  VideoChannel("UCqm35j3ustKFyXQVnX5tlXw", "阪神タイガース 公式", "teams",
      "https://hanshintigers.jp/",
      tabLabel: '阪神', league: 'central', color: '#FFE100'),
  VideoChannel("UChJI9KrjSgPzv_kfX6yuqhA", "横浜DeNAベイスターズ公式チャンネル", "teams",
      "https://www.baystars.co.jp/",
      tabLabel: 'DeNA', league: 'central', color: '#0079C2'),
  VideoChannel("UC0VGvOEN22JcprH7pZrCwiw", "広島東洋カープ公式", "teams",
      "https://www.carp.co.jp/",
      tabLabel: '広島', league: 'central', color: '#C91427'),
  VideoChannel("UCt7cNctKXoKece38M9gJV7A", "東京ヤクルトスワローズ", "teams",
      "https://www.yakult-swallows.co.jp/",
      tabLabel: 'ヤクルト', league: 'central', color: '#006837'),
  VideoChannel("UC57LcTUKgjDg_K_VJXnmCTg", "中日ドラゴンズ公式チャンネル", "teams",
      "https://dragons.jp/",
      tabLabel: '中日', league: 'central', color: '#005BAC'),
  VideoChannel("UCbDAmhyRx9bakv-0Gucglgg", "福岡ソフトバンクホークス公式", "teams",
      "https://www.softbankhawks.co.jp/",
      tabLabel: 'ソフトバンク', league: 'pacific', color: '#F8C800'),
  VideoChannel("UCIEmSQYznT9cuTZzBN-x3SQ", "北海道日本ハムファイターズ", "teams",
      "https://www.fighters.co.jp/",
      tabLabel: '日本ハム', league: 'pacific', color: '#008ACB'),
  VideoChannel("UC6qnjAoknKc6nUwhxVYL_DA", "千葉ロッテマリーンズ", "teams",
      "https://www.marines.co.jp/",
      tabLabel: 'ロッテ', league: 'pacific', color: '#333333'),
  VideoChannel("UC7DjQdai62xSVfCUhiP5Oiw", "東北楽天ゴールデンイーグルス", "teams",
      "https://www.rakuteneagles.jp/",
      tabLabel: '楽天', league: 'pacific', color: '#870010'),
  VideoChannel("UCE_pCd9bB79Tf8eC_QZHkpA", "BsTV - オリックス・バファローズ 公式", "teams",
      "https://www.buffaloes.co.jp/",
      tabLabel: 'オリックス', league: 'pacific', color: '#12234A'),
  VideoChannel("UChLK3zS3-kR21JVTaNovPIg", "埼玉西武ライオンズ", "teams",
      "https://www.seibulions.jp/",
      tabLabel: '西武', league: 'pacific', color: '#17345B'),
  VideoChannel("UCGynN2H7DcNjpN7Qng4dZmg", "上原浩治の雑談魂", "ob",
      "https://www.youtube.com/channel/UCGynN2H7DcNjpN7Qng4dZmg",
      tabLabel: '上原浩治'),
  VideoChannel("UCFCtAX45lgHcf4s0vAgAxww", "Satozaki Channel", "ob",
      "https://www.youtube.com/channel/UCFCtAX45lgHcf4s0vAgAxww",
      tabLabel: '里崎智也', daily: true),
  VideoChannel("UCJ9WGtPvQCu-OsoXKDK6FLg", "和田毅ラボ", "ob",
      "https://www.youtube.com/channel/UCJ9WGtPvQCu-OsoXKDK6FLg",
      tabLabel: '和田毅'),
  VideoChannel("UCgr5CkgytiVfdnk4C0M42nQ", "高木 豊 Takagi Yutaka", "ob",
      "https://www.youtube.com/channel/UCgr5CkgytiVfdnk4C0M42nQ",
      tabLabel: '高木豊', daily: true),
  VideoChannel("UC7CeOxGzcmmxbf_Oacxf7sg", "岩本勉チャンネル", "ob",
      "https://www.youtube.com/channel/UC7CeOxGzcmmxbf_Oacxf7sg",
      tabLabel: '岩本勉', daily: true),
  VideoChannel('UCDtT1H9LRU5xKea65hImTUw', 'イガちゃんねる 〜五十嵐亮太の人生は旅だ〜', 'ob',
      'https://www.youtube.com/@IGA-CHANNEL53',
      tabLabel: '五十嵐亮太'),
  VideoChannel('UCbf6IAYfPy8CwHVgcHbxmNw', 'フルタの方程式【古田敦也 公式チャンネル】', 'ob',
      'https://www.tv-asahi.co.jp/furuta/index.html',
      tabLabel: '古田敦也'),
  VideoChannel('UCar_QGP908qB3NJ2nLWdczA', '解体慎書【宮本慎也公式YouTubeチャンネル】', 'ob',
      'https://www.youtube.com/channel/UCar_QGP908qB3NJ2nLWdczA',
      tabLabel: '宮本慎也'),
  VideoChannel('UCWQ1geKrJNGuYgYU4QEiuhA', 'こんちゃんBASE', 'ob',
      'https://www.youtube.com/@konchanbase',
      tabLabel: '近藤健介'),
  VideoChannel('UCP4ORJd6Knja3kAL40F6YXg', '【公式】落合博満のオレ流チャンネル', 'ob',
      'https://www.youtube.com/channel/UCP4ORJd6Knja3kAL40F6YXg',
      tabLabel: '落合博満'),
  VideoChannel('UChjL85TQGI-6EYRkevIOgeA', '熱スギヤch【杉谷拳士 公式】', 'ob',
      'https://www.youtube.com/@sugiyanoyoutube',
      tabLabel: '杉谷拳士'),
  VideoChannel('UCKa1VlSq1WwdSQWv4JFdgxg', 'デーブ大久保チャンネル', 'ob',
      'https://www.youtube.com/@daveokubo',
      tabLabel: '大久保博元', daily: true),
  VideoChannel('UCSFE1o0ihc5mfODf2FybeuA', '片岡篤史チャンネル', 'ob',
      'https://www.youtube.com/channel/UCSFE1o0ihc5mfODf2FybeuA',
      tabLabel: '片岡篤史', daily: true),
  VideoChannel('UCrmppJ31jdU7GDVupoSbl0Q', '江川卓のたかされ', 'ob',
      'https://www.youtube.com/channel/UCrmppJ31jdU7GDVupoSbl0Q',
      tabLabel: '江川卓'),
  VideoChannel('UC64uGOYi7v1ClET3GJVlYyA', '谷繁ベースボールチャンネル', 'ob',
      'https://www.youtube.com/channel/UC64uGOYi7v1ClET3GJVlYyA',
      tabLabel: '谷繁元信'),
  VideoChannel('UCXvYPXTrbyjr0uCIWOrH6Mw', '武田一浩チャンネル', 'ob',
      'https://www.youtube.com/channel/UCXvYPXTrbyjr0uCIWOrH6Mw',
      tabLabel: '武田一浩'),
  VideoChannel('UCy-DO_rrnnlOydRPsG7aDyA', 'KBCホークス', 'related',
      'https://www.youtube.com/channel/UCy-DO_rrnnlOydRPsG7aDyA',
      teamIds: ['UCbDAmhyRx9bakv-0Gucglgg']),
  VideoChannel('UCgb9SfbNBjqCeacvWQ9LeXw', 'みてちょてれび【CBCアナウンサー公式】', 'program',
      'https://www.youtube.com/channel/UCgb9SfbNBjqCeacvWQ9LeXw',
      contentFilter: 'baseball', videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UCQ9r8J_1aX9kIt0k_eQ2vgQ', 'ももスポ【TNCテレビ西日本】', 'related',
      'https://www.tnc.co.jp/sns/',
      teamIds: ['UCbDAmhyRx9bakv-0Gucglgg'],
      keywords: ['ホークス', 'ソフトバンク', 'ももスポ', 'sbhawks']),
  VideoChannel('UC4dDdVZGKxNTUF_jdlinfUA', '鷹BAKA軍団', 'related',
      'https://www.sportslive-plus.com/release/230306/',
      teamIds: ['UCbDAmhyRx9bakv-0Gucglgg']),
  VideoChannel('UCODSPVjWI7uaaXxhmaOCLTA', '虎バン【ABCテレビ】', 'related',
      'https://www.asahi.co.jp/toraban/',
      teamIds: ['UCqm35j3ustKFyXQVnX5tlXw']),
  VideoChannel('UC2G0uq2KGFkonnG8yWeNZ_Q', 'ドラHOTpress', 'related',
      'https://www.tokai-tv.com/drahotplus/',
      teamIds: ['UC57LcTUKgjDg_K_VJXnmCTg']),
  VideoChannel('UCUQ0AtI3k10_CyLYcu4WRVA', '東海テレビ ニュースONE', 'broadcast',
      'https://www.youtube.com/channel/UCUQ0AtI3k10_CyLYcu4WRVA',
      teamIds: ['UC57LcTUKgjDg_K_VJXnmCTg']),
  VideoChannel('UCfjDQXxizH9OOdGGJcZ9uEQ', 'おじさんだけど、遊んでもいいですか？', 'program',
      'https://www.youtube.com/channel/UCfjDQXxizH9OOdGGJcZ9uEQ',
      contentFilter: 'baseball', videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UCWt0yfrBaUk148rxaOp4b4w', '日テレスポーツ【公式】', 'broadcast',
      'https://www.youtube.com/channel/UCWt0yfrBaUk148rxaOp4b4w'),
  VideoChannel('UCI-w8qGuG4PlmZ25m9x_Q_A', 'テレビ朝日スポーツ【公式】', 'broadcast',
      'https://www.youtube.com/@tvasahi_sports'),
  VideoChannel('UCePu9zCrsJ7fRx1b2l07nMA', 'テレ玉', 'broadcast',
      'https://www.teletama.jp/',
      teamIds: ['UChLK3zS3-kR21JVTaNovPIg']),
  VideoChannel('UCW7uiApbFl_E852MGqNILDw', 'テレ玉NEWS', 'broadcast',
      'https://www.teletama.jp/newsrelease/pdf/21081601.pdf',
      teamIds: ['UChLK3zS3-kR21JVTaNovPIg']),
  VideoChannel("UC4KLQM7RLAQyIXU88mPlZIQ", "Baseball inc. / ベースボールインク", "media",
      "https://www.youtube.com/@baseballinc",
      tabLabel: "Baseball inc."),
  VideoChannel("UCgxdkQmUjKLWjh058Pl4dAQ", "MNsports", "media",
      "https://www.youtube.com/@mnsports",
      videoOrg: 'npb'),
  VideoChannel('tver', 'TVer', 'tver', 'https://tver.jp/search/野球',
      videoOrg: 'npb'),
  VideoChannel('UCKDNkN3a6zF1CyEJHBKmy-w', '野球いっかん！', 'program',
      'https://www.youtube.com/@yakyuikkan',
      videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UC67Dybo-Sy1jsAWr39RXrBw', 'ダグアウト!!!', 'program',
      'https://www.youtube.com/channel/UC67Dybo-Sy1jsAWr39RXrBw',
      videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UCSzd2tlFW_DvVPp44JmaUrg', 'プロ野球 ドラフトちゃんねる', 'program',
      'https://www.youtube.com/channel/UCSzd2tlFW_DvVPp44JmaUrg',
      videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UCQhxtM_x7tu0Nm35zBAaLfA', 'スポーツナビ 野球チャンネル', 'program',
      'https://www.youtube.com/@sportsnavi_baseball',
      videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UCDLxLZnFeZcu822vGZ43CqQ', '白鶴酒造公式チャンネル【里崎・野球対談】', 'program',
      'https://www.youtube.com/channel/UCDLxLZnFeZcu822vGZ43CqQ',
      contentFilter: 'satozaki', videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UC8yHePe_RgUBE-waRWy6olw', 'PIVOT【野球関連】', 'program',
      'https://www.youtube.com/@pivot00',
      contentFilter: 'baseball', videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UCJ_jf8BIsLasf31SxRbQTXQ', '熱闘ベースボールレコード', 'media',
      'https://www.youtube.com/@user-baseballrecord',
      videoOrg: 'npb', unknownToNpb: true),
  VideoChannel('UC3A5dHSeD2Eyvdnn2q2yKzA', '4タコ【野球解説チャンネル】', 'media',
      'https://www.youtube.com/@tako4baseball',
      videoOrg: 'npb', unknownToNpb: true),
];

// MLB sources plus per-video MLB filtering for the shared MNsports channel.
final mlbVideoChannels = <VideoChannel>[
  const VideoChannel('UCJ-l-sMQFHogSy8KXRyMIRA', 'SPOTV NOW', 'league',
      'https://prtimes.jp/main/html/rd/p/000000026.000075946.html',
      daily: true),
  const VideoChannel('UCoLrcjPV5PbUrUyXq5mjc_A', 'MLB公式', 'league',
      'https://www.youtube.com/@MLB',
      daily: true),
  const VideoChannel('UCgxdkQmUjKLWjh058Pl4dAQ', 'MNsports', 'media',
      'https://www.youtube.com/@mnsports',
      videoOrg: 'mlb'),
  ...videoChannels
      .where(
          (c) => c.category == 'ob' || c.category == 'tver' || c.unknownToNpb)
      .map((c) => c.forVideoOrg('mlb')),
];

// Shared baseball channels are assigned only when a title explicitly names a team.
const teamVideoKeywords = <String, List<String>>{
  'UCXxg0igSYUp0tqdd6luPEnQ': ['巨人', 'ジャイアンツ'],
  'UCqm35j3ustKFyXQVnX5tlXw': ['阪神', 'タイガース'],
  'UChJI9KrjSgPzv_kfX6yuqhA': ['DeNA', 'ベイスターズ'],
  'UC0VGvOEN22JcprH7pZrCwiw': ['広島', 'カープ'],
  'UCt7cNctKXoKece38M9gJV7A': ['ヤクルト', 'スワローズ'],
  'UC57LcTUKgjDg_K_VJXnmCTg': ['中日', 'ドラゴンズ'],
  'UCbDAmhyRx9bakv-0Gucglgg': ['ソフトバンク', 'ホークス'],
  'UCIEmSQYznT9cuTZzBN-x3SQ': ['日本ハム', '日ハム', 'ファイターズ'],
  'UC6qnjAoknKc6nUwhxVYL_DA': ['ロッテ', 'マリーンズ'],
  'UC7DjQdai62xSVfCUhiP5Oiw': ['楽天', 'イーグルス'],
  'UCE_pCd9bB79Tf8eC_QZHkpA': ['オリックス', 'バファローズ'],
  'UChLK3zS3-kR21JVTaNovPIg': ['西武', 'ライオンズ'],
};

/// General broadcasters also cover non-baseball sports and local news.
/// Distinctive club names suffice; ambiguous city/company names need context.
Set<String> broadcastVideoTeams(VideoChannel channel, String title) {
  final text = title.toLowerCase().replaceAll('ｄｅｎａ', 'dena');
  final matchup = teamVideoKeywords.values
              .where((words) =>
                  words.any((word) => text.contains(word.toLowerCase())))
              .length >=
          2 &&
      RegExp(r'vs|対|×').hasMatch(text);
  final baseball = matchup ||
      RegExp(r'プロ野球|npb|セ・?リーグ|パ・?リーグ|交流戦|日本シリーズ|クライマックス|球団|投手|投球|打線|打撃|打席|本塁打|ホームラン|適時打|安打|完封|先発|登板|ドラフト|入団|春季キャンプ|秋季キャンプ|オープン戦|ペナント|始球式|野球')
          .hasMatch(text);
  const ambiguous = {'巨人', '阪神', '広島', '中日', '楽天', '西武', 'ソフトバンク', 'オリックス'};
  final result = <String>{};
  for (final entry in teamVideoKeywords.entries) {
    if (channel.teamIds.isNotEmpty && !channel.teamIds.contains(entry.key)) {
      continue;
    }
    if (entry.value.any((word) {
      final keyword = word.toLowerCase();
      if (!text.contains(keyword)) return false;
      return !ambiguous.contains(word) ||
          baseball ||
          text.contains('【$keyword】') ||
          text.contains('【$keyword・') ||
          text.contains('[$keyword]');
    })) {
      result.add(entry.key);
    }
  }
  // Program title used by TV Saitama, including English-only editions.
  if (channel.teamIds.contains('UChLK3zS3-kR21JVTaNovPIg') &&
      RegExp(r'lions\s*channel|ライオンズチャンネル').hasMatch(text)) {
    result.add('UChLK3zS3-kR21JVTaNovPIg');
  }
  return result;
}
