import 'package:html/parser.dart' as html;
import 'StrengthUsage.dart';

const salaryTeamSlugs = {'巨人': 'giants', '阪神': 'hanshin', '中日': 'dragons', 'DeNA': 'baystars', 'ヤクルト': 'swallows', '広島': 'carp', 'ソフトバンク': 'hawks', '西武': 'lions', '楽天': 'eagles', 'オリックス': 'buffaloes', '日本ハム': 'fighters', 'ロッテ': 'marines'};
int? parseYen(String raw) {
  final text = raw.replaceAll(',', '');
  final oku = RegExp(r'([\d.]+)億').firstMatch(text);
  final man = RegExp(r'([\d.]+)万').firstMatch(text);
  if (oku == null && man == null) {
    return RegExp(r'^\d+円$').hasMatch(text) ? int.tryParse(text.replaceAll('円', '')) : null;
  }
  return ((double.tryParse(oku?[1] ?? '0') ?? 0) * 100000000 + (double.tryParse(man?[1] ?? '0') ?? 0) * 10000).round();
}

Map<String, dynamic> parseContractHistory(String source, String url, String name, String key) {
  final doc = html.parse(source);
  final history = <Map<String, dynamic>>[];
  for (final row in doc.querySelectorAll('.npbsd-history-card')) {
    final year = int.tryParse(RegExp(r'\d{4}').firstMatch(row.querySelector('.npbsd-history-year')?.text ?? '')?[0] ?? '');
    final amount = parseYen(row.querySelector('.npbsd-history-salary')?.text ?? '');
    if (year == null || amount == null) continue;
    history.add({'year': year, 'amount': amount, 'currency': 'JPY', 'team': row.querySelector('.npbsd-history-team-name')?.text.trim(), 'estimated': true, 'source_url': row.querySelector('.npbsd-mobile-source a')?.attributes['href'] ?? url});
  }
  final periods = <Map<String, dynamic>>[];
  for (final row in doc.querySelectorAll('.npbsd-player-contract-row')) {
    final period = row.querySelector('.npbsd-player-contract-period')?.text.trim() ?? '';
    final years = RegExp(r'\d{4}').allMatches(period).map((m) => int.parse(m[0]!)).toList();
    periods.add({'period': period, 'start_year': years.firstOrNull, 'end_year': years.length > 1 ? years[1] : null, 'team': row.querySelector('.npbsd-responsive-text--mobile')?.text.trim(), 'detail': row.querySelector('.npbsd-player-contract-duration')?.text.trim(), 'total_label': row.querySelector('.npbsd-player-contract-amount')?.text.trim(), 'source_url': row.querySelector('.npbsd-player-contract-sources a')?.attributes['href'] ?? url});
  }
  if (history.isEmpty) throw StateError('年俸履歴がありません: $url');
  return {'player_key': key, 'name': name, 'salary_history': history, 'periods': periods, 'source_url': url, 'retrieved_at': DateTime.now().toUtc().toIso8601String()};
}

String salaryPlayerKey(String name, List<Map<String, dynamic>> roster, String url) {
  final n = usageName(name);
  var matches = roster.where((p) => usageName('${p['name']}') == n).toList();
  if (matches.isEmpty) {
    matches = roster.where((p) {
      final r = usageName('${p['name']}');
      return r.length >= 3 && (n.endsWith(r) || r.endsWith(n));
    }).toList();
  }
  return matches.length == 1 ? '${matches.single['player_key']}' : 'salary:${Uri.parse(url).path.split('/').where((s) => s.isNotEmpty).last}';
}
