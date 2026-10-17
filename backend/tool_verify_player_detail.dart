import 'dart:io';
import 'tools/Postgres.dart';
import 'app/PlayerDetailSnapshot.dart';

/// Read-only end-to-end check: dart run tool_verify_player_detail.dart npb 2026 PLAYER_ID
Future<void> main(List<String> args) async {
  if (args.length != 3 ||
      !['npb', 'mlb'].contains(args[0]) ||
      int.tryParse(args[1]) == null ||
      int.tryParse(args[2]) == null) {
    stderr.writeln(
        'Usage: dart run tool_verify_player_detail.dart npb|mlb YEAR PLAYER_ID');
    exitCode = 64;
    return;
  }
  for(var attempt=1;attempt<=3;attempt++) {
  final watch = Stopwatch()..start();
  final result = await Postgres.withConnection((conn) =>
      PlayerDetailSnapshot.read(conn,
          year: int.parse(args[1]),
          leagues: args[0] == 'npb' ? [1, 2] : [3, 4],
          identity: {'id_player': int.parse(args[2])}));
  print({
    'attempt': attempt,
    'found': result['found'],
    'recent_games': (result['recent_games'] as List?)?.length,
    'season_stats': (result['season_stats'] as List?)?.length,
    'elapsed_ms': watch.elapsedMilliseconds
  });
  }
  exit(0);
}
