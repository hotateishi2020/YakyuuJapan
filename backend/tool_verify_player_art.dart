import 'dart:convert';
import 'dart:io';
import 'app/PlayerArt.dart';
import 'app/PlayerDetailSnapshot.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  final result = await Postgres.withConnection((c) async {
    final rows = await c
        .execute('SELECT source_player_id,filename FROM t_player_art_official');
    var verified = 0;
    final detailFailures = <String>[];
    final missing = <String>[];
    for (final row in rows) {
      final art = await PlayerArt.official(
          c, {'source_player_id': row[0], 'id_team': 7});
      if (art == null || !File('${PlayerArt.root}/${row[1]}').existsSync()) {
        missing.add('${row[0]}');
        continue;
      }
      final detail = await PlayerDetailSnapshot.read(c,
          year: DateTime.now().year,
          leagues: [1, 2],
          identity: {'source_player_id': row[0], 'id_team': 7});
      if (detail['found'] != true ||
          detail['character_image']?['url'] != art['character_image']?['url']) {
        detailFailures.add('${row[0]}');
      }
      verified++;
    }
    final sample = await PlayerDetailSnapshot.read(c,
        year: 2026, leagues: [1, 2], identity: {'id_player': 1010});
    return {
      'registered': rows.length,
      'verified': verified,
      'missing': missing,
      'detail_failures': detailFailures,
      'sample_found': sample['found'],
      'sample_image': sample['character_image']?['url']
    };
  });
  print(jsonEncode(result));
  exit((result['missing'] as List).isEmpty &&
          (result['detail_failures'] as List).isEmpty &&
          result['sample_image'] != null
      ? 0
      : 1);
}
