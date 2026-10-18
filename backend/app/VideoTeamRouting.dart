import 'VideoChannels.dart';
import 'VideoClassification.dart';

// IDs for display groups, not YouTube channels.
const mlbVideoTeams = <String, List<String>>{
  'dodgers': ['ドジャース', 'dodgers'],
  'yankees': ['ヤンキース', 'yankees'],
  'red-sox': ['レッドソックス', 'red sox'],
  'blue-jays': ['ブルージェイズ', 'blue jays'],
  'orioles': ['オリオールズ', 'orioles'],
  'rays': ['レイズ', 'rays'],
  'white-sox': ['ホワイトソックス', 'white sox'],
  'guardians': ['ガーディアンズ', 'guardians'],
  'twins': ['ツインズ', 'twins'],
  'royals': ['ロイヤルズ', 'royals'],
  'tigers': ['デトロイト・タイガース', 'デトロイトタイガース', 'detroit tigers'],
  'astros': ['アストロズ', 'astros'],
  'mariners': ['マリナーズ', 'mariners'],
  'rangers': ['レンジャーズ', 'rangers'],
  'athletics': ['アスレチックス', 'athletics'],
  'angels': ['エンゼルス', 'エンジェルス', 'angels'],
  'mets': ['メッツ', 'mets'],
  'phillies': ['フィリーズ', 'phillies'],
  'braves': ['ブレーブス', 'braves'],
  'marlins': ['マーリンズ', 'marlins'],
  'nationals': ['ナショナルズ', 'nationals'],
  'cubs': ['カブス', 'cubs'],
  'brewers': ['ブルワーズ', 'brewers'],
  'cardinals': ['カージナルス', 'cardinals'],
  'pirates': ['パイレーツ', 'pirates'],
  'reds': ['レッズ', 'reds'],
  'padres': ['パドレス', 'padres'],
  'diamondbacks': ['ダイヤモンドバックス', 'diamondbacks'],
  'rockies': ['ロッキーズ', 'rockies'],
  'giants': ['サンフランシスコ・ジャイアンツ', 'サンフランシスコジャイアンツ', 'san francisco giants'],
};

/// Return a destination only for an explicitly named single-club subject.
String? expertVideoTeam(String title) {
  var text = title.toLowerCase().replaceAll('ｄｅｎａ', 'dena');
  if (RegExp(r'12球団|１２球団|30球団|全球団|順位予想|順位予測|全チーム').hasMatch(text)) return null;
  if (videoOrganizations(title).length > 1) return null;
  final teams = <String>{};
  bool contains(String word) => RegExp(r'^[a-z ]+$').hasMatch(word)
      ? RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(text)
      : text.contains(word);
  for (final entry in mlbVideoTeams.entries) {
    if (entry.value.any(contains)) {
      teams.add('mlb-team-${entry.key}');
      // Prevent full MLB club names from also matching Japanese namesakes.
      for (final word in entry.value) { text = text.replaceAll(word, ''); }
    }
  }
  if (RegExp(r'\bmlb\b|メジャー|大リーグ').hasMatch(text)) {
    for (final entry in {'ジャイアンツ': 'giants', 'タイガース': 'tigers'}.entries) {
      if (text.contains(entry.key) && !text.contains('阪神') && !text.contains('読売')) {
        teams.add('mlb-team-${entry.value}');
        text = text.replaceAll(entry.key, '');
      }
    }
  }
  for (final entry in teamVideoKeywords.entries) {
    if (entry.value.any((w) => text.contains(w.toLowerCase()))) teams.add(entry.key);
  }
  return teams.length == 1 ? teams.single : null;
}
