import 'dart:convert';
import 'dart:io';
import '../lib/logic/strength_analytics.dart';
import '../lib/logic/strength_usage.dart';
import '../lib/tools/json_utils.dart';

void main() {
  final root = File('data/regular-history.json').existsSync() ? '.' : 'backend';
  final data = jsonDecode(File('$root/data/regular-history.json').readAsStringSync());
  final rows = listMapFromJson(data['rows']);
  final audit = <Map<String, dynamic>>[];
  for (final row in rows) {
    final players = listMapFromJson(row['pitching_workload']);
    if (players.isEmpty || players.any((p) => p['starts'] == null || p['throws'] == null)) {
      throw StateError('Incomplete pitching roles: ${row['year']} ${row['club_name']}');
    }
    final selected = selectPitcherAces(row);
    final missing = [for (final slot in pitcherAceSlots.keys) if (!selected.containsKey(slot)) slot];
    for (final slot in missing) {
      final eligible = players.where((p) =>
          slot == 'CL' ? usageInt(p['saves']) > 0 :
          [slot.endsWith('L') ? '左' : '右', '両'].contains(p['throws']) &&
          (slot.startsWith('SP') ? usageInt(p['starts']) > 0 :
              usageInt(p['appearances']) > usageInt(p['starts'])));
      if (eligible.isNotEmpty) throw StateError('Unselected eligible pitcher: ${row['year']} ${row['club_name']} $slot');
    }
    audit.add({
      'year': row['year'], 'club': row['club_name'],
      'sources': [...?row['official_stat_sources'], ...?row['archive_stat_sources']],
      'selected': {for (final slot in selected.keys) slot: [for (final p in selected[slot]!) {
        'name': p['name'], 'basis': p['ace_basis'] ?? 'recorded_role_stats',
        'starts': p['starts'], 'relief_appearances': p['relief_appearances'],
        'holds': p['holds'], 'saves': p['saves'],
      }]},
      'no_eligible_pitcher': missing,
    });
  }
  File('$root/data/regular-history-audit.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'team_seasons': rows.length, 'rows': audit}));
  print('${rows.length} team-seasons verified');
}
