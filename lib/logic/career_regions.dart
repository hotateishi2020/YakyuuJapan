const japanRegions = {
  '北海道': ['北海道'],
  '東北': ['青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県'],
  '関東': ['茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県'],
  '中部': ['新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県', '静岡県', '愛知県'],
  '近畿': ['三重県', '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県'],
  '中国': ['鳥取県', '島根県', '岡山県', '広島県', '山口県'],
  '四国': ['徳島県', '香川県', '愛媛県', '高知県'],
  '九州': ['福岡県', '佐賀県', '長崎県', '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県'],
};

List<String> careerRegionPath(Map<String, dynamic> value) {
  final place =
      '${value['birth_place'] ?? value['area'] ?? value['prefecture'] ?? ''}'
          .trim();
  for (final region in japanRegions.entries) {
    for (final prefecture in region.value) {
      final short = prefecture.replaceFirst(RegExp(r'[都府県]$'), '');
      if (!place.startsWith(short)) continue;
      final rest = place
          .substring(
              place.startsWith(prefecture) ? prefecture.length : short.length)
          .trim();
      return ['日本', region.key, prefecture, if (rest.isNotEmpty) rest];
    }
  }
  final country = '${value['birth_country'] ?? value['country'] ?? ''}'.trim();
  return [if (country.isNotEmpty) country, if (place.isNotEmpty) place];
}

int? careerSchoolYear(Map<String, dynamic> player) {
  final birth = DateTime.tryParse('${player['date_birth']}');
  if (birth == null) return null;
  return birth.year -
      (birth.month < 4 || birth.month == 4 && birth.day == 1 ? 1 : 0);
}

int compareCareerAreas(String a, String b) {
  if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
  final regions = japanRegions.keys.toList();
  final prefectures = japanRegions.values.expand((v) => v).toList();
  int rank(String path, List<String> values) {
    final parts = path.split(' > ');
    final index = values.indexWhere(parts.contains);
    return index < 0 ? values.length : index;
  }

  final region = rank(a, regions).compareTo(rank(b, regions));
  if (region != 0) return region;
  final prefecture = rank(a, prefectures).compareTo(rank(b, prefectures));
  return prefecture != 0 ? prefecture : a.compareTo(b);
}
