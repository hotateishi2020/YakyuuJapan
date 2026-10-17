import '../tools/json_utils.dart';
import 'strength_usage.dart';
import 'strength_analytics.dart';

const analysisCategories = ['打撃', '走力', '内野守備', '外野守備', '先発', '中継ぎ'];
const analysisGrades = ['S', 'A', 'B', 'C', 'D', 'E', 'F', 'G'];
String relativeGrade(double? value, List<double> population, {bool lowerBetter = false}) {
  if (value == null || population.length < 2) return '—';
  final better = population.where((v) => lowerBetter ? v < value : v > value).length;
  // 同値は同じ評価。全チーム同値は中央値。
  if (population.every((v) => v == value)) return 'C';
  return analysisGrades[(better * 7 / (population.length - 1)).round().clamp(0, 7)];
}

Map<String, double?> clubMetrics(Map<String, dynamic> team) {
  final batting = listMapFromJson(team['batting_stats']);
  double? weighted(Iterable<Map<String, dynamic>> rows, String metric, String weight) {
    var sum = 0.0, total = 0.0;
    for (final p in rows) {
      final v = double.tryParse('${p[metric]}'), w = double.tryParse('${p[weight]}');
      if (v != null && v.isFinite && w != null && w > 0) {
        sum += v * w;
        total += w;
      }
    }
    return total > 0 ? sum / total : null;
  }

  double? running() {
    if (batting.isEmpty) return null;
    var steals = 0.0, caught = 0.0;
    for (final p in batting) {
      final sb = double.tryParse('${p['stolen_bases']}');
      final cs = double.tryParse('${p['caught_stealing']}');
      if (sb == null || cs == null || !sb.isFinite || !cs.isFinite) return null;
      steals += sb;
      caught += cs;
    }
    final games = double.tryParse('${team['game_count']}');
    return games != null && games > 0 ? (steals - 2 * caught) / games : null;
  }

  double? defense(Set<String> slots) {
    var chances = 0.0, errors = 0.0;
    final rows = listMapFromJson(team['fielding_stats']);
    // MLB may supply both OF totals and LF/CF/RF. Use the individual
    // positions when present, avoiding double counting the OF total.
    final separateOutfield = rows.any((p) => {'LF', 'CF', 'RF'}.contains(p['position']));
    for (final p in rows) {
      if (!slots.contains(p['position']) || separateOutfield && p['position'] == 'OF') continue;
      final po = double.tryParse('${p['putouts']}');
      final assists = double.tryParse('${p['assists']}');
      final e = double.tryParse('${p['errors']}');
      if (po == null || assists == null || e == null ||
          !po.isFinite || !assists.isFinite || !e.isFinite) {
        return null;
      }
      chances += po + assists + e;
      errors += e;
    }
    return chances > 0 ? 1 - errors / chances : null;
  }

  final workload = [for (final p in listMapFromJson(team['pitching_workload'])) strengthPlayerMetrics(team, p)];
  return {
    '打撃': weighted(batting, 'ops', 'pa'),
    '走力': running(),
    '内野守備': defense({'1B', '2B', '3B', 'SS'}),
    '外野守備': defense({'LF', 'CF', 'RF', 'OF'}),
    '先発': weighted(workload.where((p) => usageInt(p['starter_outs']) >= usageInt(p['relief_outs'])), 'whip', 'total_outs'),
    '中継ぎ': weighted(workload.where((p) => usageInt(p['starter_outs']) < usageInt(p['relief_outs'])), 'whip', 'total_outs')
  };
}

Map<String, dynamic>? clubDefenseEvidence(Map<String, dynamic> team, String category, int year) {
  if (!['内野守備', '外野守備'].contains(category)) return null;
  final data = team['defense_analysis'];
  if (data is! Map) return null;
  final entry = data[category == '内野守備' ? 'infield' : 'outfield'];
  if (entry is! Map || entry['metric'] != 'OAA' || '${entry['year']}' != '$year' ||
      double.tryParse('${entry['value']}')?.isFinite != true) {
    return null;
  }
  return Map<String, dynamic>.from(entry);
}

List<Map<String, dynamic>> analyzeClubs(List<Map<String, dynamic>> teams, int year) {
  final metrics = teams.map(clubMetrics).toList();
  final defenseMethods = <String, bool>{};
  for (final category in ['内野守備', '外野守備']) {
    final complete = teams.length >= 2 && teams.every((t) => clubDefenseEvidence(t, category, year) != null);
    defenseMethods[category] = complete;
    if (complete) {
      for (var i = 0; i < teams.length; i++) {
        metrics[i][category] = double.parse('${clubDefenseEvidence(teams[i], category, year)!['value']}');
      }
    }
  }
  return [
    for (var i = 0; i < teams.length; i++)
      (() {
        final grades = {for (final c in analysisCategories) c: relativeGrade(metrics[i][c], metrics.map((m) => m[c]).whereType<double>().toList(), lowerBetter: c == '先発' || c == '中継ぎ')};
        final regulars = selectRegulars(listMapFromJson(teams[i]['positions']).where((p) => p['slot'] != 'P').toList()).values;
        final ages = regulars.map((p) => rosterAge(strengthPlayerMetrics(teams[i], p), year)).whereType<int>().toList();
        final ordered = analysisCategories.where((c) => grades[c] != '—').toList()..sort((a, b) => analysisGrades.indexOf(grades[a]!).compareTo(analysisGrades.indexOf(grades[b]!)));
        final strong = ordered.where((c) => analysisGrades.indexOf(grades[c]!) <= 2).toList(), weak = ordered.where((c) => analysisGrades.indexOf(grades[c]!) >= 5).toList();
        return <String, dynamic>{
          ...teams[i],
          'grades': grades,
          'metrics': metrics[i],
          'defense_methods': {for (final e in defenseMethods.entries) e.key: e.value ? 'OAA' : '失策参考'},
          'regular_age': ages.isEmpty ? null : ages.reduce((a, b) => a + b) / ages.length,
          'age_count': ages.length,
          'regular_count': regulars.length,
          'strengths': ordered.isEmpty
              ? '判定データなし'
              : strong.isEmpty
                  ? '突出項目なし'
                  : strong.map((c) => defenseMethods[c] == false ? '$c（失策参考）' : c).join('・'),
          'weaknesses': ordered.isEmpty
              ? '判定データなし'
              : weak.isEmpty
                  ? '下位項目なし'
                  : weak.map((c) => defenseMethods[c] == false ? '$c（失策参考）' : c).join('・')
        };
      })()
  ];
}

String npbClubKey(Map<String, dynamic> team) {
  final url = '${team['url_npb_players'] ?? ''}';
  final code = RegExp(r'(?:rst_|index_|/teams/)([a-z]+)(?:\.html|/)').firstMatch(url)?[1];
  if (code != null) return code;
  final name = '${team['name_team'] ?? team['name_short'] ?? ''}';
  const names = {'g': '巨人', 't': '阪神', 'db': 'DeNA', 'c': '広島', 'd': '中日', 's': 'ヤクルト', 'h': 'ソフトバンク', 'f': '日本ハム', 'm': 'ロッテ', 'l': '西武', 'e': '楽天', 'b': 'オリックス'};
  for (final e in names.entries) {
    if (name.contains(e.value) || e.key == 'g' && name.contains('読売')) {
      return e.key;
    }
  }
  return '';
}

List<Map<String, dynamic>> sortedTrainingGroups(dynamic value) {
  final groups = listMapFromJson(value);
  groups.sort((a, b) {
    final size = listMapFromJson(b['members']).length.compareTo(listMapFromJson(a['members']).length);
    return size != 0 ? size : '${a['name']}'.compareTo('${b['name']}');
  });
  return groups;
}
