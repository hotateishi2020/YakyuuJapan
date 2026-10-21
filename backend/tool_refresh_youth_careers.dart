import 'dart:convert';
import 'dart:io';
import 'app/YouthCareers.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.single);
  var count = 0;
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('SELECT code_org,id_team,payload FROM t_team_strength WHERE int_year=\$1', parameters: [year]);
    for (final row in rows) {
      await conn.runTx((tx) async {
        final saved = await tx.execute('SELECT payload FROM t_team_strength WHERE int_year=\$1 AND code_org=\$2 AND id_team=\$3 FOR UPDATE', parameters: [year,row[0],row[1]]);
        final data = usageMap(saved.single[0] is String ? jsonDecode(saved.single[0] as String) : saved.single[0]);
        final updates = <Map<String,dynamic>>[];
        for (final p in usageMaps(data['roster'])) {
          if (p['active'] == false || (p['departure_confirmed'] == true && p['departure_type'] == 'retired')) continue;
          final old = usageMaps(p['career_history']);
          final merged = withYouthCareers(p, old);
          if (merged.length == old.length || p['player_key'] == null) continue;
          updates.add({'key':p['player_key'],'payload':{'career_history':merged}});
          count++;
        }
        if (updates.isEmpty) return;
        await tx.execute('''INSERT INTO t_strength_player_status(code_org,int_year,id_team,player_key,payload)
          SELECT \$1,\$2,\$3,p->>'key',p->'payload' FROM jsonb_array_elements(\$4::jsonb) p
          ON CONFLICT(code_org,int_year,id_team,player_key) DO UPDATE SET payload=t_strength_player_status.payload||EXCLUDED.payload,updated_at=NOW()''', parameters:[row[0],year,row[1],jsonEncode(updates)]);
        await tx.execute('''UPDATE t_team_strength t SET payload=jsonb_set(payload,'{roster}',
          (SELECT jsonb_agg(p||COALESCE((SELECT u->'payload' FROM jsonb_array_elements(\$4::jsonb) u WHERE u->>'key'=p->>'player_key'),'{}'::jsonb)) FROM jsonb_array_elements(t.payload->'roster') p))
          WHERE int_year=\$1 AND code_org=\$2 AND id_team=\$3''',parameters:[year,row[0],row[1],jsonEncode(updates)]);
        print('${row[0]} 球団${row[1]}: ${updates.length}人更新');
      });
    }
  });
  print('所属歴追加: $count人');
  exit(0);
}
