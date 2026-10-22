import 'dart:io';
import 'tools/Postgres.dart';
import 'app/AppSql.dart';
import 'app/DB/t_stats_player.dart';
Future<void> main() async {await Postgres.withConnection((conn) async {
 final token=(await conn.execute('SELECT name_shortest FROM m_team WHERE id=18')).first[0] as String;
 for(final name in ['村上','村上宗隆']) {
  for(final url in ['', 'https://baseball.yahoo.co.jp/mlb/player/202101502/', 'https://baseball.yahoo.co.jp/mlb/player/202101502/top']) {
   final row=t_stats_player()..playerName=name..teamName=token..playerUrl=url..id_league=3..id_stats=1..stats=0.207;
   final sql=AppSql.selectInsertStatsPlayer([row]);
   final start=sql.indexOf('(\n        SELECT');
   if(start<0) throw StateError('Unexpected SQL shape');
   final selected=await conn.execute(sql.substring(start+1,sql.lastIndexOf(')')));
   if(selected.length!=1 || selected.first.toColumnMap()['id_player']!=5601) throw StateError('Lookup failed: $name $url');
  }
 }
 print('6 lookup cases resolve to player 5601.');
 final duplicates=await conn.execute("SELECT payload->>'id_stats',payload->>'title',count(*) FROM v_stats_player WHERE int_year=2026 AND payload->>'id_player'='5601' GROUP BY payload->>'id_stats',payload->>'title' HAVING count(*)>1");
 if(duplicates.isNotEmpty) throw StateError('Duplicate display metrics remain');
 final aliases=await conn.execute("SELECT count(*) FROM v_stats_player WHERE int_year=2026 AND payload->>'id_player' IN ('5141','5366','5427')");
 if(aliases.first[0]!=0) throw StateError('Old snapshot aliases remain');
 print('No duplicate personal-stat metrics or alias snapshots.');
 });exit(0);}
