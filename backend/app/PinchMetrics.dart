import 'package:html/parser.dart' as html;
import 'StrengthUsage.dart';

Map<String, int?> classifyPinchResult(String raw) {
  final play = raw.replaceAll(RegExp(r'[\s①-⑳]'), '');
  if (play.isEmpty) return {'ab': 0, 'hit': 0};
  final hit = RegExp(r'^[一二三遊左右中投捕](前|越|線|中|エ|バ)?(安|２|３|本)$').hasMatch(play);
  final noAb = RegExp(r'^(四球|敬遠|敬遠四|死球|打妨|[一二三遊左右中投捕]犠(打|飛))$').hasMatch(play);
  final out = RegExp(r'^(三振|振逃|[一二三遊左右中投捕](ゴロ|飛|直|邪飛|併打|失|選|併|邪直|ゴ失|飛失|野選))$').hasMatch(play);
  return {
    'ab': hit || out
        ? 1
        : noAb
            ? 0
            : null,
    'hit': hit
        ? 1
        : noAb || out
            ? 0
            : null
  };
}

List<Map<String, dynamic>> parseNpbPinch(String source, String url) {
  if (parseNpbUsageGame(source, url).isEmpty) return [];
  final doc = html.parse(source), result = <Map<String, dynamic>>[];
  for (final side in ['top', 'bottom'])
    for (final tr in doc.querySelectorAll('#table_${side}_b tbody tr')) {
      final c = tr.children;
      if (c.length < 9 || c[0].text.trim().isNotEmpty || !c[1].text.trim().startsWith('打')) {
        continue;
      }
      final id = RegExp(r'/players/(\d+)\.html').firstMatch(c[2].querySelector('a')?.attributes['href'] ?? '')?[1];
      if (id == null) throw StateError('代打選手IDがありません');
      final plays = c.skip(8).map((e) => e.text.replaceAll(RegExp(r'\s+'), '')).where((v) => v.isNotEmpty && v != '-');
      final play = plays.firstOrNull ?? '';
      result.add({'source_player_id': id, 'name': c[2].text.trim(), 'usage': 1, ...classifyPinchResult(play), 'play': play});
    }
  return result;
}
