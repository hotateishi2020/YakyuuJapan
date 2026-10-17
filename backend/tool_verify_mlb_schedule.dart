import 'dart:io';
import 'tools/Postgres.dart';
import 'app/JapanClock.dart';
Future<void> main() async {
final day=JapanClock.now().toIso8601String().substring(0,10);
await Postgres.withConnection((c) async {
print((await c.execute('''SELECT g.id,g.datetime_start::text,g.state,g.flg_delete,h.name_short AS home,a.name_short AS away FROM t_game g JOIN m_team h ON h.id=g.id_team_home JOIN m_team a ON a.id=g.id_team_away WHERE g.datetime_start::date BETWEEN \$1::date AND \$1::date+1 AND h.id_league IN (3,4) ORDER BY g.datetime_start''',parameters:[day])).map((r)=>r.toColumnMap()).toList());
print((await c.execute('''SELECT date_game,COUNT(DISTINCT id_game) FROM v_games_details WHERE date_game BETWEEN \$1::date AND \$1::date+1 AND (payload->>'id_league_home')::int IN (3,4) GROUP BY date_game''',parameters:[day])).map((r)=>r.toColumnMap()).toList());
});exit(0);}
