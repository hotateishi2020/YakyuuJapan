/// Classify individual titles, never the channel as a whole. Explicit league
/// context takes priority over player names and historical club references.
Set<String> videoOrganizations(String title) {
  final text =
      title.toLowerCase().replaceAll('ｍｌｂ', 'mlb').replaceAll('ｎｐｂ', 'npb');
  // WBC belongs to the NPB tab even when MLB clubs/players are named.
  if (isWbcVideo(title)) return {'npb'};
  final explicit = <String>{
    if (RegExp(r'\bmlb\b|メジャーリーグ|メジャー挑戦|メジャー移籍|大リーグ|ワールドシリーズ').hasMatch(text))
      'mlb',
    if (RegExp(r'\bnpb\b|日本プロ野球|日本球界|日本シリーズ|セ・?リーグ|パ・?リーグ').hasMatch(text))
      'npb',
  };
  if (explicit.isNotEmpty) return explicit;
  const mlbTeams = [
    'ドジャース',
    'ヤンキース',
    'レッドソックス',
    'ブルージェイズ',
    'オリオールズ',
    'レイズ',
    'ホワイトソックス',
    'ガーディアンズ',
    'ツインズ',
    'ロイヤルズ',
    'デトロイト',
    'アストロズ',
    'マリナーズ',
    'レンジャーズ',
    'アスレチックス',
    'エンゼルス',
    'エンジェルス',
    'メッツ',
    'フィリーズ',
    'ブレーブス',
    'マーリンズ',
    'ナショナルズ',
    'カブス',
    'ブルワーズ',
    'カージナルス',
    'パイレーツ',
    'レッズ',
    'パドレス',
    'ダイヤモンドバックス',
    'ロッキーズ',
    'サンフランシスコ',
    'dodgers',
    'yankees',
    'red sox',
    'blue jays',
    'orioles',
    'rays',
    'white sox',
    'guardians',
    'twins',
    'royals',
    'detroit',
    'astros',
    'mariners',
    'rangers',
    'athletics',
    'angels',
    'mets',
    'phillies',
    'braves',
    'marlins',
    'nationals',
    'cubs',
    'brewers',
    'cardinals',
    'pirates',
    'reds',
    'padres',
    'diamondbacks',
    'rockies',
    'san francisco',
  ];
  const npbTeams = [
    '巨人',
    '読売',
    '阪神',
    'dena',
    'ベイスターズ',
    'カープ',
    'ヤクルト',
    'スワローズ',
    '中日',
    'ドラゴンズ',
    'ソフトバンク',
    'ホークス',
    '日本ハム',
    '日ハム',
    'ファイターズ',
    'ロッテ',
    'マリーンズ',
    '楽天',
    'イーグルス',
    'オリックス',
    'バファローズ',
    '西武',
    'ライオンズ',
  ];
  bool mentions(String keyword) => RegExp(r'^[a-z ]+$').hasMatch(keyword)
      ? RegExp('\\b${RegExp.escape(keyword)}\\b').hasMatch(text)
      : text.contains(keyword);
  final clubs = <String>{
    if (mlbTeams.any(mentions)) 'mlb',
    if (npbTeams.any(mentions)) 'npb',
  };
  if (clubs.isNotEmpty) return clubs;
  // Used only without an explicit league or club, so e.g. an NPB-era Ohtani
  // feature is not moved to MLB because it happens to mention his name.
  const mlbSubjects = [
    '大谷翔平',
    '大谷',
    '佐々木朗希',
    '山本由伸',
    '鈴木誠也',
    '今永昇太',
    'ダルビッシュ',
    '菊池雄星',
    '千賀滉大',
    'アーロン・ジャッジ',
    'ジャッジ',
    'ゲレーロjr',
    'ゲレーロｊｒ',
    'マチャド',
    'リンドーア',
    'タティス',
    'スキーンズ',
    'ミジオロウスキ',
    'ケテル・マルテ',
    'コントレラス',
    'ブーン監督',
    'マーモル監督',
    'アロンゾ',
    'pca',
  ];
  if (mlbSubjects.any(mentions)) return {'mlb'};
  return {}; // Unknown is not implicitly NPB.
}

/// Includes abbreviations, full-width lettering and Japanese/English names.
bool isWbcVideo(String title) {
  final text = title.toLowerCase().replaceAll('ｗｂｃ', 'wbc');
  return RegExp(
    r'(^|[^a-z])w[\s.・]*b[\s.・]*c(?=$|[^a-z])|ワールド[\s・･-]*ベースボール[\s・･-]*クラシック|world[\s-]+baseball[\s-]+classic',
  ).hasMatch(text);
}
