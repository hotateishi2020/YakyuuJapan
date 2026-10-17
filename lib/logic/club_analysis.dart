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
    final known = batting.where((p) => p['stolen_bases'] != null && p['caught_stealing'] != null).toList();
    final pa = known.fold<int>(0, (v, p) => v + usageInt(p['pa']));
    return pa > 0 ? known.fold<double>(0, (v, p) => v + usageInt(p['stolen_bases']) - 2 * usageInt(p['caught_stealing'])) / pa * 100 : null;
  }

  double? defense(Set<String> slots) {
    var sum = 0.0, count = 0;
    for (final p in listMapFromJson(team['fielding_metrics'])) {
      final uzr = p['uzr_by_position'];
      if (uzr is! Map) continue;
      for (final s in slots) {
        final n = double.tryParse('${uzr[s]}');
        if (n != null) {
          sum += n;
          count++;
        }
      }
    }
    return count > 0 ? sum : null;
  }

  final workload = [for (final p in listMapFromJson(team['pitching_workload'])) strengthPlayerMetrics(team, p)];
  return {
    '打撃': weighted(batting, 'ops', 'pa'),
    '走力': running(),
    '内野守備': defense({'1B', '2B', '3B', 'SS'}),
    '外野守備': defense({'LF', 'CF', 'RF'}),
    '先発': weighted(workload.where((p) => usageInt(p['starter_outs']) >= usageInt(p['relief_outs'])), 'whip', 'total_outs'),
    '中継ぎ': weighted(workload.where((p) => usageInt(p['starter_outs']) < usageInt(p['relief_outs'])), 'whip', 'total_outs')
  };
}

List<Map<String, dynamic>> analyzeClubs(List<Map<String, dynamic>> teams, int year) {
  final metrics = teams.map(clubMetrics).toList();
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
          'regular_age': ages.isEmpty ? null : ages.reduce((a, b) => a + b) / ages.length,
          'age_count': ages.length,
          'regular_count': regulars.length,
          'strengths': ordered.isEmpty
              ? '判定データなし'
              : strong.isEmpty
                  ? '突出項目なし'
                  : strong.join('・'),
          'weaknesses': ordered.isEmpty
              ? '判定データなし'
              : weak.isEmpty
                  ? '下位項目なし'
                  : weak.join('・')
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
