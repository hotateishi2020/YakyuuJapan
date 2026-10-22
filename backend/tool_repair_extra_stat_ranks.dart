import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/PlayerDetail.dart';
import 'app/ClubData.dart';
import 'app/StrengthUsage.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  await Postgres.withConnection((conn) async {
    final extra = await extraStatRows(conn, year, [1, 2, 3, 4]);
    final titles = {
      for (final p in usageMaps(readClubFile('player-metrics-$year.json')['players']))
        for (final m in usageMaps(p['metrics'])) if(m['title'] != '盗塁阻止率') m['title'],
      'GG受賞回数',
    };
    final records = await conn.execute('SELECT id_player,payload FROM t_player_detail_snapshot WHERE int_year=\$1', parameters: [year]);
    final backup = records.map((r) => r.toColumnMap()).toList();
    final path = '/tmp/koko-extra-ranks-$year-${DateTime.now().millisecondsSinceEpoch}.json';
    await File(path).writeAsString(jsonEncode(backup));
    final updates = <Map<String,dynamic>>[];
    for (final r in records) {
      final id = r[0];
      final payload = detailMap(r[1]);
      final stats = usageMaps(payload['season_stats']);
      stats.removeWhere((s) => titles.contains(s['title']));
      stats.addAll(extra.where((s) => s['id_player'] == id));
      addMissingRequestedMetrics(stats);
      updates.add({'id': id, 'stats': stats});
    }
    await conn.runTx((tx) async {
      for (var i = 0; i < updates.length; i += 100) {
        await tx.execute("UPDATE t_player_detail_snapshot d SET payload=jsonb_set(payload,'{season_stats}',u.stats) FROM jsonb_to_recordset(\$1::jsonb) AS u(id int,stats jsonb) WHERE d.int_year=\$2 AND d.id_player=u.id", parameters: [jsonEncode(updates.skip(i).take(100).toList()), year]);
      }
    });
    final batch = await PlayerDetailBatch.load(conn, year, playerIds: [4935]);
    final ranking = extra.singleWhere((s) => s['id_player']==4935 && s['title']=='打席数');
    final detail = batch.extra.singleWhere((s) => s['title']=='打席数');
    if (detail['int_rank'] != ranking['int_rank'] || detail['stats'] != ranking['stats']) throw StateError('Detail rank mismatch');
    print({'updated': updates.length, 'backup': path, 'matsumoto_pa': ranking['stats'], 'league_rank': ranking['int_rank'], 'batch_matches': true});
  });
  exit(0);
}
