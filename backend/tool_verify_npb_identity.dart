import 'dart:convert';
import 'dart:io';
import 'app/PlayerIdentity.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  final plan=jsonDecode(File('data/npb-player-identity-plan.json').readAsStringSync()) as Map;
  final groups=List<Map<String,dynamic>>.from(plan['groups']);
  await Postgres.withConnection((conn) async {
    for(final g in groups) {
      final canonical=g['canonical_id'] as int;
      final rows=await conn.execute('SELECT id,merged_into_player_id,flg_delete FROM m_player WHERE id=ANY(\$1::int[])',parameters:[g['merge_ids']]);
      if(rows.length!=(g['merge_ids'] as List).length || rows.any((r)=>r[1]!=canonical || r[2]!=true)) throw StateError('Invalid redirects for $canonical');
      final found=await PlayerIdentity.find(conn,name:g['name_ja'],teamId:g['team_id'],source:'npb',externalId:g['identity_sources']['npb']);
      if(found!=canonical) throw StateError('Official ID lookup failed for $canonical');
    }
    final duplicates=await conn.execute("SELECT identity_sources->>'npb',count(*) FROM m_player WHERE NOT coalesce(flg_delete,false) AND identity_sources->>'npb' ~ '^[0-9]+\$' GROUP BY 1 HAVING count(*)>1");
    if(duplicates.isNotEmpty) throw StateError('Duplicate official NPB identities');
    final oldIds=[for(final g in groups)...List<int>.from(g['merge_ids'])];
    final references=await conn.execute("""SELECT c.table_name,c.column_name FROM information_schema.columns c
      JOIN information_schema.tables t ON t.table_name=c.table_name AND t.table_schema=c.table_schema AND t.table_type='BASE TABLE'
      WHERE c.table_schema='public' AND c.data_type='integer'
      AND c.column_name IN ('id_player','id_player_fav','id_batter','id_pitcher','id_player_enter','id_player_exit','id_pitcher_home','id_pitcher_away','id_pitcher_win','id_pitcher_lose','id_pitcher_save')""");
    for(final r in references) {
      final count=(await conn.execute('SELECT count(*) FROM ${r[0]} WHERE ${r[1]}=ANY(\$1::int[])',parameters:[oldIds])).single[0];
      if(count!=0) throw StateError('Old IDs still referenced in ${r[0]}.${r[1]}: $count');
    }
    // Keep unresolved names in the review queue; different verified source IDs remain separate people.
    var pending = 0;
    var distinct = 0;
    for(final raw in plan['review'] as List) {
      final r=Map<String,dynamic>.from(raw);
      final ids=List<int>.from(r['ids']);
      final people=await conn.execute('SELECT identity_sources FROM m_player WHERE id=ANY(\$1::int[])',parameters:[ids]);
      final official=people.map((p)=>(p[0] as Map?)?['npb']).where((id)=>RegExp(r'^\d+$').hasMatch('$id')).toSet();
      final status=official.length==ids.length ? 'distinct' : 'pending';
      if (status == 'pending') { pending++; } else { distinct++; }
      await conn.execute("INSERT INTO t_player_identity_review(review_key,evidence,status) VALUES(\$1,\$2::jsonb,\$3) ON CONFLICT(review_key) DO UPDATE SET evidence=excluded.evidence,status=excluded.status,updated_at=now()",parameters:['npb-audit:${ids.join('-')}',jsonEncode({...r,'candidate_ids':ids}),status]);
    }
    final report={'checked_at':DateTime.now().toUtc().toIso8601String(),'players_unified':groups.length,'duplicate_rows_merged':oldIds.length,'official_npb_id_duplicates':0,'old_reference_count':0,'reference_columns_checked':references.length,'pending_review_groups':pending,'distinct_name_groups':distinct};
    File('data/npb-player-identity-verification.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    print(jsonEncode(report));
  });exit(0);
}
