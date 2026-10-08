import 'app/AppSql.dart';
import 'app/FetchMLB.dart';
import 'app/FetchURL.dart';
import 'app/YahooHtml.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final clubRows = await conn.execute(AppSql.selectTeams());
    final clubs = clubRows
        .map((row) => CareerClub(
              id: row[0] as int,
              league: row[1] as int,
              shortName: '${row[2] ?? ''}',
              fullName: '${row[3] ?? ''}',
              url: '${row[4] ?? ''}',
            ))
        .toList();
    print('clubs ${clubs.length}');

    // team match smoke
    for (final name in ['レッドソックス', 'ドジャース', 'オリックス', '巨人', 'ブルージェイズ']) {
      final id = FetchURL.matchCareerClubId(name, clubs, preferMlb: true);
      final c = clubs.where((e) => e.id == id).toList();
      print('match $name -> $id ${c.isEmpty ? "" : "${c.first.shortName} L${c.first.league}"}');
    }

    const playerId = 5142; // 吉田
    const url = 'https://baseball.yahoo.co.jp/mlb/player/202100515/';
    final doc = await YahooHtml.fetchDocument(Uri.parse(url));
    print('year_b ${doc.querySelector('#year_b') != null} year_p ${doc.querySelector('#year_p') != null}');
    final table = doc.querySelector('#year_b');
    var i = 0;
    for (final tr in table!.querySelectorAll('tbody tr')) {
      if (i++ >= 3) break;
      final yearText = tr.querySelector('.bb-playerStatsTable__dataLabel')?.text.trim();
      final teamRaw = tr.querySelector('.bb-playerStatsTable__data--team')?.text.trim();
      final cells = tr.querySelectorAll('td.bb-playerStatsTable__data');
      print('row year=$yearText team="$teamRaw" cells=${cells.length} c2=${cells.length > 2 ? cells[2].text : ""} c5=${cells.length > 5 ? cells[5].text : ""}');
    }
    final n = await FetchMLB.upsertYahooMlbYearCareers(conn, playerId, doc, clubs);
    print('upserted $n');
    final rows = await conn.execute('''
      SELECT c.int_year, t.name_short, t.id_league, c.int_batting, c.double_inning
      FROM m_player_career c JOIN m_team t ON t.id=c.id_team
      WHERE c.id_player=\$1 AND COALESCE(c.flg_delete,FALSE)=FALSE
      ORDER BY c.int_year, t.id_league
    ''', parameters: [playerId]);
    for (final r in rows) {
      print(r.toColumnMap());
    }
  });
}
