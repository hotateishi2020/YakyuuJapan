import 'dart:convert';
import 'dart:io';
import 'app/AwardValues.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'app/StrengthUsage.dart';
import 'app/HistoricalBaseballImporter.dart';

/// Official award recipients, including retired players absent from current rosters.
Future<void> main(List<String> args) async {
  final client = http.Client(), file = File('data/records.json');
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final last = DateTime.now().year - 1;
  final errors = <String>[];
  Future<String> get(String url) async {
    final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}');
    return utf8.decode(r.bodyBytes);
  }

  final npb = <Map<String, dynamic>>[];
  final jobs = [
    for (var year = 2006; year <= last; year++)
      for (final l in ['cl', 'pl']) (year, l)
  ];
  try {
    for (var i = 0; i < jobs.length; i += 4) {
      await Future.wait(jobs.skip(i).take(4).map((job) async {
        final url = 'https://npb.jp/award/${job.$1}/${job.$2}.html';
        try {
          final doc = html.parse(await get(url));
          final categories = <String, List<Map<String, dynamic>>>{};
          const aliases = {'最優秀選手賞': 'MVP', '最優秀新人賞': '新人王', '首位打者賞': '首位打者', '最多安打者賞': '最多安打', '最多本塁打者賞': '本塁打王', '最多打点者賞': '打点王', '最多盗塁者賞': '盗塁王', '最高出塁率者賞': '最高出塁率', '最優秀防御率投手賞': '最優秀防御率', '最多勝利投手賞': '最多勝利', '最多セーブ投手賞': '最多セーブ', '最優秀中継ぎ投手賞': '最優秀中継ぎ', '最多三振奪取投手賞': '最多奪三振', '勝率第一位投手賞': '最高勝率'};
          for (final a in doc.querySelectorAll('a[href*="/players/"]')) {
            final label = a.querySelector('h6')?.text.trim(), name = a.querySelector('.name')?.text.trim();
            if (label == null || name == null || name.isEmpty) continue;
            categories.putIfAbsent(aliases[label] ?? label, () => []).add({'name': name, 'team': a.querySelector('.team')?.text.trim(), 'value': '受賞', ...npbAwardValue(label, a.text), 'status': 'unknown', 'source': url});
          }
          if (categories.isEmpty) {
            throw const FormatException('No award recipients');
          }
          npb.add({
            'year': job.$1,
            'league': job.$2 == 'cl' ? 'セ・リーグ' : 'パ・リーグ',
            'provisional': false,
            'categories': [
              for (final e in categories.entries) {'label': e.key, 'players': e.value}
            ]
          });
        } catch (e) {
          errors.add('$url $e');
        }
      }));
    }
    final legacy = [
      for (var y = 1937; y < 2006; y++)
        for (final spec in HistoricalBaseballImporter.npbSourcesForYear(y)) (y, spec)
    ];
    for (var i = 0; i < legacy.length; i += 4) {
      await Future.wait(legacy.skip(i).take(4).map((job) async {
        try {
          final doc = html.parse(await get(job.$2.uri));
          final categories = <Map<String, dynamic>>[];
          for (final row in doc.querySelectorAll('tr')) {
            final cells = row.children.where((e) => e.localName == 'td').toList();
            if (cells.length < 3 || cells.first.classes.contains('leadersName') == false) {
              continue;
            }
            final raw = cells[0].text.trim();
            final label = const {'最優秀選手': 'MVP', '最優秀新人': '新人王'}[raw];
            if (label == null) continue;
            final phase = job.$2.phase;
            categories.add({
              'label': phase == null ? label : '$label（${phase == 'spring' ? '春' : '秋'}）',
              'players': [
                {'name': cells[1].text.trim(), 'team': cells[2].text.trim(), 'value': '受賞', 'status': 'unknown', 'source': job.$2.uri}
              ]
            });
          }
          if (categories.isNotEmpty) {
            final league = job.$1 < 1950
                ? '日本野球連盟'
                : job.$2.leagueId == 1
                    ? 'セ・リーグ'
                    : 'パ・リーグ';
            final existing = npb.where((r) => r['year'] == job.$1 && r['league'] == league).firstOrNull;
            if (existing != null) {
              (existing['categories'] as List).addAll(categories);
            } else {
              npb.add({'year': job.$1, 'league': league, 'provisional': false, 'categories': categories});
            }
          }
        } catch (e) {
          errors.add('${job.$2.uri} $e');
        }
      }));
    }
    final mlb = <String, Map<String, dynamic>>{};
    for (final l in ['AL', 'NL']) {
      for (final a in {'MVP': 'MVP', 'CY': 'サイ・ヤング賞', 'ROY': '新人王'}.entries) {
        final url = 'https://statsapi.mlb.com/api/v1/awards/$l${a.key}/recipients';
        try {
          final awards = usageMaps(jsonDecode(await get(url))['awards']);
          if (awards.isEmpty) {
            throw const FormatException('No award recipients');
          }
          for (final award in awards) {
            final y = usageInt(award['season']);
            if (y <= 0) continue;
            final league = l == 'AL' ? 'ア・リーグ' : 'ナ・リーグ';
            final s = mlb.putIfAbsent('$y:$l', () => {'year': y, 'league': league, 'provisional': false, 'categories': <Map<String, dynamic>>[]});
            final cs = s['categories'] as List<Map<String, dynamic>>;
            var c = cs.where((c) => c['label'] == a.value).firstOrNull;
            if (c == null) {
              c = {'label': a.value, 'players': <Map<String, dynamic>>[]};
              cs.add(c);
            }
            final player = usageMap(award['player']);
            (c['players'] as List).add({'name': player['nameFirstLast'] ?? player['fullName'], 'value': '受賞', 'status': 'unknown', 'source': url});
          }
        } catch (e) {
          errors.add('$url $e');
        }
      }
    }
    // Preserve older successful imports on any transient failure.
    for (final org in ['npb', 'mlb']) {
      final rows = org == 'npb' ? npb : mlb.values.toList();
      final merged = {for (final r in usageMaps(data[org]['awards'])) '${r['year']}:${r['league']}': r};
      for (final r in rows) {
        merged['${r['year']}:${r['league']}'] = r;
      }
      data[org]['awards'] = merged.values.toList()..sort((a, b) => usageInt(b['year']).compareTo(usageInt(a['year'])));
      print('$org: ${merged.length} year/league award grids');
    }
    final temp = File('${file.path}.tmp');
    temp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    temp.renameSync(file.path);
    for (final e in errors) {
      stderr.writeln(e);
    }
    if (errors.isNotEmpty) exitCode = 1;
  } finally {
    client.close();
  }
}
