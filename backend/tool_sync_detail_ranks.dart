import 'dart:convert';
import 'dart:io';
import 'app/PredictionSnapshot.dart';
import 'app/PlayerDisplay.dart';
import 'app/PlayerDetail.dart' show detailMap;
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year=int.parse(args.firstOrNull ?? '${DateTime.now().year}');
  await Postgres.withConnection((conn) async {
    final rankings=(await PredictionSnapshot.players(conn,year,[1,2,3,4])).stats;
    final saved=await conn.execute('SELECT id_player,payload FROM t_player_detail_snapshot WHERE int_year=\$1',parameters:[year]);
    final changes=<Map<String,dynamic>>[];
    var changedRanks=0;
    for(final row in saved) {
      final id=row[0] as int;
      final payload=detailMap(row[1]);
      final stats=playerDetailSeasonStats(rankings,id);
      final old=List<Map<String,dynamic>>.from(payload['season_stats'] as List? ?? []);
      for(final s in stats) {
        final before=old.where((r)=>r['title']==s['title'] && r['flg_pitcher']==s['flg_pitcher']).firstOrNull;
        if(before!=null && before['int_rank']!=s['int_rank']) changedRanks++;
      }
      changes.add({'id':id,'stats':stats});
    }
    await conn.execute('''UPDATE t_player_detail_snapshot d SET payload=jsonb_set(d.payload,'{season_stats}',v.stats)
      FROM jsonb_to_recordset(\$2::jsonb) AS v(id int,stats jsonb)
      WHERE d.int_year=\$1 AND d.id_player=v.id''',parameters:[year,jsonEncode(changes)]);
    final azuma=rankings.where((r)=>'${r['name_player']}'.replaceAll(RegExp(r'[\s　]'),'').startsWith('東克樹'));
    print(jsonEncode({'year':year,'snapshots_synced':changes.length,'rank_differences_fixed':changedRanks,
      'azuma':[for(final r in azuma) if(['BB/9','四死球/9','平均投球回','登板回数','QS率'].contains(r['title'])) {'title':r['title'],'value':r['stats'],'rank':r['int_rank']}]}));
  });exit(0);
}
