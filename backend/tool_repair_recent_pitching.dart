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
    final metadata = await conn.execute('''SELECT s.id_player,g.datetime_start::date::text,
      jsonb_build_object('double_inning_pitch',s.double_inning_pitch,
        'code_result_pitcher',s.code_result_pitcher,'starter',s.id_player IN (g.id_pitcher_home,g.id_pitcher_away),
        'int_velo_max',(SELECT MAX(d.int_velo) FROM t_game_details d
          WHERE d.id_game=g.id AND d.id_pitcher=s.id_player AND NOT COALESCE(d.flg_delete,false)))
      FROM t_game_summary s JOIN t_game g ON g.id=s.id_game
      WHERE g.datetime_start>=make_date(\$1,1,1) AND g.datetime_start<make_date(\$1+1,1,1)
        AND s.double_inning_pitch IS NOT NULL AND NOT COALESCE(s.flg_delete,false)
        AND NOT COALESCE(g.flg_delete,false)''', parameters: [year]);
    final byPlayerDate = <String,List<Map<String,dynamic>>>{};
    for (final row in metadata) {
      byPlayerDate.putIfAbsent('${row[0]}:${row[1]}', () => []).add(usageMap(row[2]));
    }
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
        final meta = byPlayerDate['${row[0]}:${games[i]['datetime_start'].toString().substring(0,10)}'];
        if (meta?.length == 1) mergeRecentPitchingMetadata(replacement, {'lines': meta});
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
