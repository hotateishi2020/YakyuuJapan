import 'app/ClubData.dart';
import 'app/StrengthUsage.dart';
import 'dart:convert';
import 'dart:io';
import 'app/ChampionshipSummary.dart';
import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute("SELECT code_org,int_year,payload->'standings',updated_at::text FROM t_page_snapshot WHERE kind='records'");
    for (final row in rows) {
      final raw = row[2] is String ? jsonDecode(row[2] as String) : row[2];
      final summary = championshipSummary([for (final s in raw as List) Map<String,dynamic>.from(s)],row[1] as int,mlb: row[0]=='mlb',officialLeagueWinners: usageMap(readClubFile('npb_league_champions.json')['years']));
      await conn.execute('''UPDATE t_page_snapshot SET payload=jsonb_set(payload,'{championship_summary}',\$3::jsonb)
        WHERE kind='records' AND code_org=\$1 AND int_year=\$2 AND updated_at=\$4::timestamptz''',
        parameters:[row[0],row[1],jsonEncode(summary),row[3]]);
      print('${row[0]} ${row[1]}: ${summary.length} teams');
      if (row[0]=='npb') { for (final team in summary) { print('${team['name']}: 日本一${team['champion_count']} 最長${team['champion_streak']} リーグ${team['league_count']} 交流戦${team['interleague_count']}'); } }
    }
  });
  exit(0);
}
