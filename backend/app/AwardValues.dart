import 'package:html/dom.dart';

/// Preserve boundaries such as <br> between statistics and award history.
String awardCardText(Node node) => node is Text ? node.text : node.nodes.map(awardCardText).join(' ');

/// Extract only the statistic explicitly shown on a statistical award card.
Map<String, String> npbAwardValue(String label, String text) {
  final spec = switch (label) {
    String s when s.contains('防御率') => ('防御率', ''),
    String s when s.contains('中継ぎ') => ('ホールドポイント', 'HP'),
    String s when s.contains('セーブ') => ('セーブ', 'セーブ'),
    String s when s.contains('勝率') => ('勝率', ''),
    String s when s.contains('最多勝利') => ('勝利', '勝'),
    String s when s.contains('三振') => ('奪三振', '奪三振'),
    String s when s.contains('首位打者') => ('打率', ''),
    String s when s.contains('安打') => ('安打', '安打'),
    String s when s.contains('本塁打') => ('本塁打', '本'),
    String s when s.contains('打点') => ('打点', '打点'),
    String s when s.contains('盗塁') => ('盗塁', '盗塁'),
    String s when s.contains('出塁率') => ('出塁率', ''),
    _ => null,
  };
  if (spec == null) return {};
  final match = RegExp('${spec.$1}\\s+([0-9]*\\.[0-9]+|[0-9]+)').firstMatch(text);
  if (match == null) return {};
  final value = match.group(1)!;
  return {'value': value.startsWith('.') ? '0$value' : value, 'unit': spec.$2};
}
