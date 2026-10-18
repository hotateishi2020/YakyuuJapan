import 'app/CatcherCounts.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/ClubData.dart';
import 'app/ExtendedPlayerMetrics.dart';
import 'app/StrengthUsage.dart';
import 'app/StatcastProfiles.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first), client = http.Client();
  final players = <String, Map<String, dynamic>>{};
  void add(Map<String, dynamic> p) {
    final key = '${p['org']}:${p['source_player_id'] ?? p['name']}';
    final target = players.putIfAbsent(key, () => {...p, 'metrics': <Map<String, dynamic>>[]});
    for (final m in usageMaps(p['metrics'])) {
      final list = target['metrics'] as List<Map<String, dynamic>>;
      final previous = list.where((v) => v['title'] == m['title']).firstOrNull;
      if (previous != null && p['org'] == 'npb') {
        final a = previous['numeric_value'] as num?, b = m['numeric_value'] as num?;
        if (['打席数', '登板回数', '投球回数', '盗塁阻止数'].contains(m['title']) && a != null && b != null) {
          m['numeric_value'] = a + b;
          m['stats'] = m['title'] == '投球回数' ? '${((a + b) * 3).round() ~/ 3}${((a + b) * 3).round() % 3 == 0 ? '' : ' ${((a + b) * 3).round() % 3}/3'}' : '${(a + b).round()}';
        } else if (['BB/9', '四死球/9', '平均投球回'].contains(m['title']) && a != null && b != null) {
          final field = m['title'] == '平均投球回' ? 'appearances' : 'outs';
          final aw = previous[field] as num, bw = m[field] as num;
          m['numeric_value'] = aw + bw > 0 ? (a * aw + b * bw) / (aw + bw) : null;
          m['stats'] = (m['numeric_value'] as num?)?.toStringAsFixed(2) ?? '—';
        } else {
          m['numeric_value'] = null;
          m['stats'] = '—';
          m['note'] = '複数球団の分母を確認できないため未計算';
        }
        for (final k in ['outs', 'appearances']) {
          if (m[k] != null && previous[k] != null) {
            m[k] = (m[k] as num) + (previous[k] as num);
          }
        }
        m['note'] = '${m['note'] ?? ''} 複数球団の公式値を合算。';
      }
      list.removeWhere((v) => v['title'] == m['title']);
      list.add({...m, 'source': m['source'] ?? p['source']});
    }
  }

  Future<String> get(String url) async {
    final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 40));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}: $url');
    return utf8.decode(r.bodyBytes);
  }

  try {
    for (final code in npbClubNames.keys) {
      for (final pair in [('bat', 'idb1'), ('pitch', 'idp1'), ('field', 'idf1')]) {
        final url = 'https://npb.jp/bis/$year/stats/${pair.$2}_$code.html';
        for (final p in parseExtendedNpb(await get(url), kind: pair.$1, url: url)) {
          add(p);
        }
      }
      print('$code: completed');
    }
    for (final group in ['hitting', 'pitching', 'fielding']) {
      final url = 'https://statsapi.mlb.com/api/v1/stats?stats=season&group=$group&season=$year&sportIds=1&playerPool=ALL&limit=5000';
      final data = usageMap(jsonDecode(await get(url)));
      for (final block in usageMaps(data['stats']))
        for (final split in usageMaps(block['splits'])) {
          // Totals are supplied by the league-wide endpoint, including multi-team players.
          final s = usageMap(split['stat']), p = usageMap(split['player']);
          num? n(String k) => num.tryParse('${s[k]}');
          final metrics = <Map<String, dynamic>>[];
          if (group == 'hitting') {
            metrics.add(metric('打席数', n('plateAppearances')));
          }
          if (group == 'pitching') {
            final outs = inningsToOuts('${s['inningsPitched']}'), games = n('gamesPitched') ?? n('gamesPlayed'), bb = n('baseOnBalls'), hbp = n('hitBatsmen');
            metrics.addAll([metric('登板回数', games, pitcher: true), metric('投球回数', outs / 3, pitcher: true, display: '${outs ~/ 3}${outs % 3 == 0 ? '' : ' ${outs % 3}/3'}'), metric('平均投球回', games != null && games > 0 ? outs / 3 / games : null, pitcher: true, digits: 2, note: '全登板の平均・小数表記'), metric('BB/9', outs > 0 && bb != null ? bb * 27 / outs : null, pitcher: true, digits: 2), metric('四死球/9', outs > 0 && bb != null && hbp != null ? (bb + hbp) * 27 / outs : null, pitcher: true, digits: 2)]);
          }
          if (group == 'fielding' && usageMap(split['position'])['abbreviation'] == 'C') {
            final cs = n('caughtStealing');
            metrics.add(metric('盗塁阻止数', cs));
          }
          if (metrics.isNotEmpty) {
            add({'org': 'mlb', 'source_player_id': '${p['id']}', 'name': p['fullName'], 'source': url, 'metrics': metrics});
          }
        }
    }
    await refreshNpbCatcherCounts(year, players.values.toList(), get);
    final profiles = await fetchStatcastProfiles(year, get, add);
    final profileFile = File('data/player-profiles-$year.json');
    final old = readClubFile('player-profiles-$year.json');
    final merged = {for (final p in usageMaps(old['players'])) '${p['org']}:${p['source_player_id']}': p};
    for (final p in profiles) {
      final key = '${p['org']}:${p['source_player_id']}';
      merged[key] = {...?merged[key], ...p};
    }
    await File('${profileFile.path}.tmp').writeAsString(const JsonEncoder.withIndent('  ').convert({'year': year, 'players': merged.values.toList()}));
    await File('${profileFile.path}.tmp').rename(profileFile.path);
    final out = File('data/player-metrics-$year.json');
    final tmp = File('${out.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({'year': year, 'checked_at': DateTime.now().toUtc().toIso8601String(), 'players': players.values.toList()}));
    await tmp.rename(out.path);
    print('${players.length} players saved');
  } finally {
    client.close();
  }
}
