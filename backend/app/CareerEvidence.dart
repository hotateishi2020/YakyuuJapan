import 'package:html/parser.dart' as html;
import 'StrengthUsage.dart';
import 'PlayerAchievements.dart';

String evidenceName(String s) => usageName(s).replaceAll('髙', '高').replaceAll('﨑', '崎').replaceAll('海', '海');

String? careerCategory(String name) {
  if (name.contains('シニア')) return 'シニア';
  if (name.contains('リトル')) return 'リトル';
  if (RegExp(r'^(四国|BC|日本海|関西|北海道|九州|ベイサイド|さわかみ|ルートイン)・').hasMatch(name)) {
    return '独立';
  }
  if (RegExp(r'大学|大$|大.+(学部|キャンパス|校|オホーツク)|カレッジ').hasMatch(name)) return '大学';
  if (RegExp(r'高$|高校|高等学校|高専$|商$|工$|農$|実$|商工$|セカンダリースクール$').hasMatch(name)) {
    return '高校';
  }
  if (RegExp(r'^(JR|NTT|JFE|JX|ENEOS|ホンダ|Honda|トヨタ|三菱|新日鉄|日本製鉄|日本製紙)|製作所|製鉄所|ガス$|電力$|運輸$|生命$|日本通運|セガサミー|ヤマハ|^王子$|^TDK$|ミキハウス|ロキテクノ|伯和ビクトリーズ|ハナマウイ|硬式野球クラブ|^CLUB REBASE$').hasMatch(name)) {
    return '社会人';
  }
  return null; // Do not turn unclassified professional overseas clubs into amateur teams.
}

String careerTeamName(String s) => switch (s) {
      'JX-ENEOS' || '新日本石油ENEOS' => 'ENEOS',
      'ホンダ' => 'Honda',
      'ホンダ鈴鹿' => 'Honda鈴鹿',
      'ホンダ熊本' => 'Honda熊本',
      'BC・富山' => '日本海・富山',
      'BC・石川' => '日本海・石川',
      _ => s,
    };
Map<String, dynamic> npbCareerEvidence(String source, String url) {
  final doc = html.parse(source), fields = <String, String>{};
  for (final row in doc.querySelectorAll('#pc_bio tr')) {
    final key = row.querySelector('th')?.text.trim();
    if (key != null) fields[key] = row.querySelector('td')?.text.trim() ?? '';
  }
  // Older profiles have the same labeled rows without pc_bio.
  if (!fields.containsKey('経歴')) {
    for (final row in doc.querySelectorAll('tr')) {
      final key = row.querySelector('th')?.text.trim();
      if (['経歴', 'ドラフト'].contains(key)) {
        fields[key!] = row.querySelector('td')?.text.trim() ?? '';
      }
    }
  }
  final history = <Map<String, dynamic>>[];
  for (final raw in (fields['経歴'] ?? '').split(RegExp(r'\s+-\s+'))) {
    final category = careerCategory(raw);
    if (category == null) continue;
    final name = careerTeamName(raw);
    if (history.any((h) => h['team'] == name)) continue;
    history.add({'category': category, 'team': name, 'source_url': url, 'detail': 'NPB公式プロフィールの経歴。${raw != name ? '掲載名：$raw。' : ''}在籍期間は未確認。'});
  }
  final draft = RegExp(r'(\d{4})年(育成(?:選手)?)?ドラフト1位').firstMatch(fields['ドラフト'] ?? '');
  return {
    if (history.isNotEmpty) 'career_history': history,
    'badges': [if (draft != null) achievement(draft[2] == null ? 'ドラフト1位' : '育成ドラフト1位', int.parse(draft[1]!), url, kind: 'draft', detail: fields['ドラフト']!)],
  };
}

List<Map<String, dynamic>> namedAwardEvidence(String source, int year, String url, {bool glove = false}) {
  final result = <Map<String, dynamic>>[];
  for (final unit in html.parse(source).querySelectorAll('.player_unit_1')) {
    final name = unit.querySelector('.name')?.text.trim();
    final title = unit.querySelector('h6')?.text.trim();
    if (name == null || title == null) continue;
    final id = RegExp(r'/players/(\d+)\.html').firstMatch(unit.attributes['href'] ?? '')?[1];
    result.add({'name': name, if (id != null) 'player_key': 'npb:$id', 'badge': achievement(glove ? 'ゴールデングラブ賞（$title）' : title.replaceAll('沢村栄治賞', '沢村賞'), year, url, kind: 'title', detail: unit.querySelector('.comment')?.text.trim() ?? '')});
  }
  return result;
}
