import 'package:html/dom.dart';
import 'YahooTeamNames.dart';

/// 試合トップから読む速報。打撃・投球成績表や一球速報は参照しない。
Map<String, String> parseGameLiveBrief(Document doc, {required String home, required String away}) {
  final result = <String, String>{};
  String side(String label) {
    final name = YahooTeamNames.normalize(label.trim());
    if (name == YahooTeamNames.normalize(home.trim())) return 'home';
    if (name == YahooTeamNames.normalize(away.trim())) return 'away';
    return '';
  }
  for (final row in doc.querySelectorAll('#battery tr')) {
    final team = side(row.querySelector('th')?.text ?? '');
    final cell = row.querySelector('td');
    if (team.isEmpty || cell == null) continue;
    // バッテリー欄は「投手、投手 - 捕手、捕手」。最後の投手だけ残す。
    final pitching = cell.text.split(RegExp(r'\s+[-－–—]\s+')).first.trim();
    if (pitching == cell.text.trim()) continue;
    final name = pitching.split(RegExp(r'[、,]')).last.trim();
    if (name.isNotEmpty) result['name_current_pitcher_$team'] = name;
  }
  for (final row in doc.querySelectorAll('#homerun tr')) {
    final team = side(row.querySelector('th')?.text ?? '');
    final cell = row.querySelector('td');
    if (team.isEmpty || cell == null) continue;
    result['name_homerun_$team'] = cell.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  return result;
}
