/// Conservative relevance checks for channels that also publish non-baseball videos.
const baseballGuests = [
  '古田敦也',
  '谷繁元信',
  '矢野燿大',
  '城島健司',
  '阿部慎之助',
  '伊東勤',
  '中村武志',
  '達川光男',
  '真中満',
  '高橋由伸',
  '井端弘和',
  '荒木雅博',
  '井口資仁',
  '鳥谷敬',
  '今江敏晃',
  '福浦和也',
  '初芝清',
  '西岡剛',
  '清水直行',
  '渡辺俊介',
  '小林雅英',
  '小宮山悟',
  '薮田安彦',
  '成瀬善久',
  '大村三郎',
  'サブロー',
  '藤川球児',
  '上原浩治',
  '五十嵐亮太',
  '岡島秀樹',
  '斎藤隆',
  '松坂大輔',
  '杉内俊哉',
  '和田毅',
  '武田一浩',
  '工藤公康',
  '山本昌',
  '山﨑武司',
  '山崎武司',
  '岩瀬仁紀',
  '川上憲伸',
  '川崎宗則',
  '斎藤佑樹',
  '斉藤和巳',
  '摂津正',
  '攝津正',
  '新垣渚',
  '森福允彦',
  '松井稼頭央',
  '松井秀喜',
  '高橋尚成',
  '清原和博',
  '落合博満',
  '宮本慎也',
  '片岡篤史',
  '江川卓',
  '中畑清',
  '掛布雅之',
  '金本知憲',
  '新井貴浩',
  '前田智徳',
  '緒方孝市',
  '高木豊',
  '田尾安志',
  '仁志敏久',
  '石井琢朗',
  '佐々木主浩',
  '佐伯貴弘',
  '多村仁志',
  '内川聖一',
  '村田修一',
  '村田真一',
  '杉谷拳士',
  '稲葉篤紀',
  '新庄剛志',
  '小笠原道大',
  '田中幸雄',
  '田中賢介',
  '岩本勉',
  '建山義紀',
  '稲村亜美',
  '山本浩二',
  '大久保博元',
  'デーブ大久保',
  '大谷翔平',
  'イチロー',
  'ダルビッシュ',
  '山本由伸',
  '田中将大',
  '前田健太',
  '近藤健介',
  '柳田悠岐',
  '坂本勇人',
  '丸佳浩',
  '岡本和真',
  '村上宗隆',
  '中村剛也',
  '栗山巧',
  '浅村栄斗',
  '山田哲人',
  '菊池涼介',
  '秋山翔吾',
];
String _compact(String text) =>
    text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
bool isBaseballContent(String text) {
  final value = _compact(text);
  return RegExp(
              r'野球|ドラフト会議|二刀流|ベースボール|甲子園|球界|球団|投手|打者|本塁打|侍ジャパン|mlb|npb|wbc|メジャーリーグ|日本シリーズ|ジャイアンツ|タイガース|ベイスターズ|スワローズ|ドラゴンズ|ホークス|ファイターズ|マリーンズ|ライオンズ|バファローズ')
          .hasMatch(value) ||
      baseballGuests.any((name) => value.contains(name.toLowerCase()));
}

bool matchesVideoContent(String? filter, String title,
    {String description = ''}) {
  if (filter == null) return true;
  // Ignore channel-wide links/profile boilerplate at the bottom of descriptions.
  final text = _compact(
      '$title ${description.split(RegExp(r'https?://|【関連動画|チャンネル登録')).first}');
  if (filter == 'baseball') return isBaseballContent(text);
  if (filter == 'satozaki') {
    if (!RegExp(r'里崎|satozaki').hasMatch(text)) return false;
    return baseballGuests
            .where((name) => name != '稲村亜美')
            .any((name) => text.contains(name.toLowerCase())) ||
        RegExp(r'(ゲスト|対談|共演).{0,45}(プロ野球選手|元プロ野球|元メジャー)|(?:プロ野球選手|元プロ野球|元メジャー).{0,45}(ゲスト|対談|共演)')
            .hasMatch(text);
  }
  return false;
}
