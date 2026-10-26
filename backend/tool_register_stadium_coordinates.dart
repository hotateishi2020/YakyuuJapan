import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';

String key(dynamic value) => '${value ?? ''}'.toLowerCase().replaceAll(RegExp(r'[\s　・･]'), '');
Future<void> main(List<String> args) async {
  final catalog = (jsonDecode(File('data/stadium-catalog.json').readAsStringSync())['stadiums'] as List).cast<Map>();
  await Postgres.withConnection((conn) async {
    if (args.contains('--verify')) {
      final rows = await conn.execute(r'''SELECT g.id,COALESCE(NULLIF(s.name_full,''),s.name_short) AS stadium,
        s.latitude,s.longitude FROM t_game g JOIN m_stadium s ON s.id=g.id_stadium
        WHERE g.datetime_start::date=(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Tokyo')::date
          AND NOT COALESCE(g.flg_delete,false)''');
      print(jsonEncode(rows.map((r)=>r.toColumnMap()).toList()));
      return;
    }
    if (!args.contains('--apply')) {
      final rows = await conn.execute('SELECT id,name_short,name_full FROM m_stadium WHERE NOT COALESCE(flg_delete,false) ORDER BY id');
      for (final row in rows) { print(jsonEncode(row.toColumnMap())); }
      return;
    }
    await conn.execute('ALTER TABLE m_stadium ADD COLUMN IF NOT EXISTS latitude double precision, ADD COLUMN IF NOT EXISTS longitude double precision');
    final rows = await conn.execute('SELECT id,name_short,name_full FROM m_stadium WHERE NOT COALESCE(flg_delete,false)');
    var updated = 0;
    final unknown = <String>[];
    for (final row in rows) {
      final r = row.toColumnMap();
      final names = [key(r['name_full']),key(r['name_short'])].where((s)=>s.isNotEmpty).toSet();
      final matches = catalog.where((v) => [v['name'],v['match'],...(v['aliases'] as List? ?? [])].any((s)=>names.contains(key(s)))).toList();
      if (matches.length != 1 || matches.single['latitude'] is! num || matches.single['longitude'] is! num) {
        unknown.add('${r['id']}: ${r['name_full']}'); continue;
      }
      final v = matches.single;
      await conn.execute(r'UPDATE m_stadium SET latitude=$1,longitude=$2 WHERE id=$3 AND (latitude IS NULL OR longitude IS NULL)', parameters:[v['latitude'],v['longitude'],r['id']]);
      updated++;
    }
    print(jsonEncode({'matched':updated,'unmatched':unknown}));
  });
  exit(0);
}
