import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

/// Generate /tmp/koko-expanded-draft.json for review; never overwrite the asset.
/// Usage (repository root): dart run backend/tool_expand_draft.dart
Future<void> main() async {
  final client = http.Client();
  try {
    final file = File('backend/assets/data/draft_2026.json');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final players = (data['players'] as List).map((p) => Map<String, dynamic>.from(p)).toList();
    final names = players.map((p) => p['name']).toSet();
    final catalogs = {8724: ('高校生', '投手'), 8725: ('高校生', '野手'), 8726: ('大学生', '投手'), 8727: ('大学生', '野手'), 8728: ('社会人', ''), 8729: ('独立リーグ', '')};
    for (final entry in catalogs.entries) {
      final url = 'https://dir.sp.baseball.findfriends.jp/yakyumatome/detail.html?no=${entry.key}';
      final response = await client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}: $url');
      }
      final doc = html.parse(utf8.decode(response.bodyBytes));
      for (final h in doc.querySelectorAll('h3')) {
        final heading = RegExp(r'^([^（(]+)[（(]([^）)]+)[）)]').firstMatch(h.text.trim());
        if (heading == null) continue;
        final name = heading[1]!.replaceAll(RegExp(r'\s+'), '');
        if (names.contains(name)) continue;
        final team = heading[2]!;
        // NPB farm-only clubs are not independent-league teams.
        if (['オイシックス', 'ハヤテ'].contains(team)) continue;
        final fields = <String, String>{};
        String? profile;
        for (var node = h.nextElementSibling; node != null && node.localName != 'h3' && node.localName != 'h2'; node = node.nextElementSibling) {
          profile ??= node.querySelector('figcaption a')?.attributes['href'];
          for (final row in node.querySelectorAll('tr')) {
            final k = row.querySelector('th')?.text.trim(), v = row.querySelector('td')?.text.trim();
            if (k != null && v != null) fields[k] = v;
          }
        }
        final size = RegExp(r'(\d+)cm\s*(\d+)kg').firstMatch(fields['身長体重'] ?? '');
        if (size == null || fields['投打'] == null) continue;
        final speed = fields['最速'];
        final position = fields['ポジション'] ?? (speed != null ? '投手' : entry.value.$2);
        final type = (fields['選手タイプ'] ?? fields['タイプ'] ?? '').split('・').last.trim();
        final traits = <String>[];
        if (speed != null) traits.add('最速${speed.replaceAll('キロ', 'km/h')}');
        if (['先発', '救援', 'マルチ', '俊足', '巧打', '長距離', '強打', '長打'].contains(type)) {
          traits.add(switch (type) { '先発' => '先発型の投手', '救援' => 'リリーフ型の投手', 'マルチ' => '複数の役割を担える投手', '俊足' => '走力が注目される選手', '巧打' => 'ミート力が注目される打者', _ => '長打力が注目される打者' });
        }

        if (traits.isEmpty) traits.add('${fields['投打']}の$position');
        final career = (fields['経歴'] ?? '').replaceAll(RegExp(r'\s+'), '').replaceAll('[甲]', '').replaceAll('→', ' → ');
        players.add({
          'category': entry.value.$1,
          'name': name,
          'team': team,
          'position': position,
          'height': int.parse(size[1]!),
          'weight': int.parse(size[2]!),
          'hand': fields['投打'],
          // School attendance alone does not establish a player's tournament participation.
          // Verified year/season/results are added as career_facts of kind koshien.
          'achievement': career,
          'features': '${traits.join('。')}。',
          'sources': [if (profile != null) profile.split('?').first, url]
        });
        names.add(name);
      }
    }
    data['players'] = players;
    File('/tmp/koko-expanded-draft.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(data)}\n');
    for (final category in ['高校生', '大学生', '社会人', '独立リーグ']) {
      final selected = players.where((p) => p['category'] == category).toList();
      print('$category ${selected.length}人');
      for (final p in selected) {
        print('${p['name']} / ${p['team']} / ${p['position']} / ${p['features']}');
      }
    }
  } finally {
    client.close();
  }
}
