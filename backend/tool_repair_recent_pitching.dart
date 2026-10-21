import 'dart:convert';
import 'dart:io';
import 'app/ClubData.dart';
import 'app/RecentPlayerGames.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

/// Repair existing snapshots without recomputing unrelated player information.
Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  final cache = readClubFile('npb-recent-games-$year.json');
  var changed = 0;
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''SELECT id_player,source_player_id,
      payload->'recent_games',updated_at::text FROM t_player_detail_snapshot
      WHERE int_year=\$1 AND id_league IN (1,2) AND source_player_id IS NOT NULL''', parameters: [year]);
    final updates = <Map<String, dynamic>>[];
    for (final row in rows) {
      final official = officialNpbRecentGames('${row[1]}', year, snapshot: cache);
      final bySource = {for (final g in official) g['source']: g};
      final old = row[2] is String ? jsonDecode(row[2] as String) : row[2];
      final games = usageMaps(old);
      var repaired = false;
      for (var i = 0; i < games.length; i++) {
        final replacement = bySource[games[i]['source']];
        if (replacement == null) continue;
        final pitching = usageMaps(replacement['lines']).where((l) => l['double_inning_pitch'] != null);
        if (pitching.isEmpty || pitching.any((l) => l['int_runs'] == null)) continue;
        if (jsonEncode(games[i]['lines']) == jsonEncode(replacement['lines'])) continue;
        games[i] = {...games[i], 'lines': replacement['lines'], 'opponent': replacement['opponent']};
        repaired = true;
      }
      if (repaired) updates.add({'id': row[0], 'stamp': row[3], 'games': games});
    }
    if (updates.isNotEmpty) {
      final result = await conn.execute('''UPDATE t_player_detail_snapshot d
        SET payload=jsonb_set(d.payload,'{recent_games}',u.games)
        FROM jsonb_to_recordset(\$1::jsonb) AS u(id int,stamp timestamptz,games jsonb)
        WHERE d.int_year=\$2 AND d.id_player=u.id AND d.updated_at=u.stamp
        RETURNING d.id_player''', parameters: [jsonEncode(updates), year]);
      changed = result.length;
    }
  });
  print('投手の出場成績を修正: $changed 選手');
  exit(0);
}
