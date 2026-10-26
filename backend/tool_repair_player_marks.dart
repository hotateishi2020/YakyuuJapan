import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/DisplaySnapshot.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('player_id year');
  final id = int.parse(args[0]), year = int.parse(args[1]);
  await Postgres.withConnection((c) async {
    final before = await c.execute("SELECT * FROM v_predict_stats WHERE int_year=\$1 AND kind='stats' AND (payload->>'id_player')::int=\$2", parameters: [year, id]);
    final path = '/tmp/koko-player-marks-$id-$year-${DateTime.now().millisecondsSinceEpoch}.json';
    File(path).writeAsStringSync(jsonEncode(before.map((r)=>r.toColumnMap()).toList(), toEncodable:(v)=>v.toString()));
    // Read-time repair must already work before changing the stored snapshot.
    final read = (await DisplaySnapshot.playerPart(c, year, [1,2])).stats.where((r)=>r['id_player']==id && r['title']=='勝率').toList();
    if (read.isEmpty || read.any((r)=>r['flg_rookie'] != false || r['flg_career_this_year'] != false)) throw StateError('Canonical marker verification failed');
    final changed = await c.execute(r'''
      UPDATE v_predict_stats saved
      SET payload = saved.payload || jsonb_build_object(
        'flg_rookie', actual.payload->'flg_rookie',
        'flg_career_this_year', actual.payload->'flg_career_this_year'
      ), updated_at = now()
      FROM v_stats_player actual
      WHERE saved.int_year=$1 AND saved.kind='stats'
        AND (saved.payload->>'id_player')::int=$2
        AND actual.int_year=saved.int_year
        AND actual.payload->>'id_player'=saved.payload->>'id_player'
        AND actual.payload->>'id_league'=saved.payload->>'id_league'
        AND actual.payload->>'title'=saved.payload->>'title'
        AND actual.payload ? 'flg_rookie' AND actual.payload ? 'flg_career_this_year'
        AND (saved.payload->'flg_rookie' IS DISTINCT FROM actual.payload->'flg_rookie'
          OR saved.payload->'flg_career_this_year' IS DISTINCT FROM actual.payload->'flg_career_this_year')
      RETURNING saved.payload->>'title'
    ''', parameters: [year, id]);
    print('Updated ${changed.length} rows; backup: $path');
    final stored = await c.execute("SELECT payload->>'title',payload->'flg_rookie',payload->'flg_career_this_year' FROM v_predict_stats WHERE int_year=\$1 AND kind='stats' AND (payload->>'id_player')::int=\$2", parameters: [year,id]);
    if (stored.any((r)=>r[1] != false || r[2] != false)) throw StateError('Unexpected remaining marker');
    print('Verified ${stored.length} stat rows: rookie=false, debut=false');
  });
  exit(0);
}
