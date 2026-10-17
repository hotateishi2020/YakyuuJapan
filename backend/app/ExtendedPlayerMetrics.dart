import 'package:html/parser.dart' as html;
import 'StrengthUsage.dart';

Map<String, dynamic> metric(String title, num? value, {bool pitcher = false, int digits = 0, String? note, String? display}) => {'title': title, 'numeric_value': value, 'stats': display ?? (value == null ? '—' : value.toStringAsFixed(digits)), 'flg_pitcher': pitcher, if (note != null) 'note': note};
List<Map<String, dynamic>> parseExtendedNpb(String source, {required String kind, required String url}) {
  final result = <Map<String, dynamic>>[];
  for (final tr in html.parse(source).querySelectorAll('tr')) {
    final c = tr.querySelectorAll('td');
    if (c.isEmpty) continue;
    final link = c.first.querySelector('a[href*="/players/"]');
    final id = RegExp(r'/players/(\d+)\.html').firstMatch(link?.attributes['href'] ?? '')?[1];
    final name = (link?.text ?? c.first.text).replaceAll(RegExp(r'[\s*+]'), '');
    if (name.isEmpty || nonnumeric(c)) continue;
    num? n(int i) => i < c.length ? num.tryParse(c[i].text.trim()) : null;
    final metrics = <Map<String, dynamic>>[];
    if (kind == 'bat' && c.length >= 23) {
      metrics.add(metric('打席数', n(2)));
    }
    if (kind == 'pitch' && c.length >= 24) {
      final outs = inningsToOuts(c[12].text), games = n(1), bb = n(15), hbp = n(17);
      metrics.addAll([metric('登板回数', games, pitcher: true), metric('投球回数', outs / 3, pitcher: true, display: '${outs ~/ 3}${outs % 3 == 0 ? '' : ' ${outs % 3}/3'}'), metric('平均投球回', games != null && games > 0 ? outs / 3 / games : null, pitcher: true, digits: 2, note: '投球回÷全登板数（先発・救援を含む）。小数表記。'), metric('BB/9', outs > 0 && bb != null ? bb * 27 / outs : null, pitcher: true, digits: 2, note: '四球×9÷投球回。死球を含まない。'), metric('四死球/9', outs > 0 && bb != null && hbp != null ? (bb + hbp) * 27 / outs : null, pitcher: true, digits: 2, note: '（四球＋死球）×9÷投球回。')]);
    }
    if (kind == 'pitch') {
      for (final m in metrics) {
        m['outs'] = inningsToOuts(c[12].text);
        m['appearances'] = n(1);
      }
    }
    if (kind == 'field' && c.length == 9) {
      metrics.add(metric('盗塁阻止率', n(8), digits: 3, note: '公式公表値。盗塁阻止÷盗塁企図。'));
    }
    if (metrics.isNotEmpty) {
      result.add({'org': 'npb', 'source_player_id': id, 'name': name, 'source': url, 'metrics': metrics});
    }
  }
  return result;
}

bool nonnumeric(dynamic cells) => cells.length < 2 || num.tryParse(cells[1].text.trim()) == null;
