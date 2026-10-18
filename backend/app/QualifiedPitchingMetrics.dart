import 'package:postgres/postgres.dart';
import 'dart:convert';
import 'StrengthUsage.dart' show usageMap;

const qualifiedPitchingRateTitles = {'BB/9', '四死球/9'};

Future<Map<int, int>> readQualificationGames(Connection conn, int year) async {
  final rows = await conn.execute('SELECT payload FROM v_stats_teams WHERE int_year=\$1', parameters: [year]);
  final games = <int, int>{};
  for (final row in rows) {
    final p = usageMap(row[0] is String ? jsonDecode(row[0] as String) : row[0]);
    final id = int.tryParse('${p['id_team']}'), count = int.tryParse('${p['int_game']}');
    if (id != null && count != null && count > 0) games[id] = count;
  }
  return games;
}

/// Use outs so 142 2/3 never rounds up to a 143-inning qualification.
void retainQualifiedPitchingRates(List<Map<String, dynamic>> rows, Map<int, int> teamGames) {
  final outsByPlayer = <String, int>{};
  String key(Map<String, dynamic> r) => '${r['id_player']}:${r['id_team']}';
  for (final r in rows) {
    if (r['title'] != '投球回数') continue;
    final value = num.tryParse('${r['numeric_value']}');
    if (value != null && value.isFinite) {
      outsByPlayer[key(r)] = (value * 3).round();
    }
  }
  rows.removeWhere((r) {
    if (!qualifiedPitchingRateTitles.contains(r['title'])) return false;
    final games = teamGames[int.tryParse('${r['id_team']}')];
    final outs = int.tryParse('${r['outs']}') ?? outsByPlayer[key(r)];
    return games == null || games <= 0 || outs == null || outs < games * 3;
  });
}

void rankQualifiedPitchingRates(List<Map<String, dynamic>> rows) {
  for (final title in qualifiedPitchingRateTitles) {
    for (final league in rows.map((r) => r['id_league']).toSet()) {
      final group = rows.where((r) => r['title'] == title && r['id_league'] == league).toList();
      num? value(Map<String, dynamic> r) => num.tryParse('${r['numeric_value'] ?? r['stats']}');
      group.sort((a, b) => (value(a) ?? double.infinity).compareTo(value(b) ?? double.infinity));
      num? previous;
      var rank = 0;
      for (var i = 0; i < group.length; i++) {
        final v = value(group[i]);
        if (v == null) {
          group[i]['int_rank'] = 1000;
          continue;
        }
        if (v != previous) rank = i + 1;
        group[i]['int_rank'] = rank;
        previous = v;
      }
    }
  }
}

/// Cumulative catcher counts do not require plate-appearance qualification.
void retainCatcherCounts(List<Map<String, dynamic>> rows) {
  rows.removeWhere((r) {
    if (r['title'] != '盗塁阻止数') return false;
    final position = '${r['txt_position'] ?? ''}'.toUpperCase();
    final catcher = r['catcher_metric'] == true || position.contains('捕') || RegExp(r'(^|[^A-Z])C($|[^A-Z])').hasMatch(position);
    final count = num.tryParse('${r['numeric_value'] ?? r['stats']}');
    return !catcher || count == null || !count.isFinite || count < 0;
  });
}
