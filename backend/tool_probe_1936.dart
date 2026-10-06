import 'app/HistoricalBaseballImporter.dart';

Future<void> dump(String label, String url, int year, {int leagueId = 1}) async {
  final importer = HistoricalBaseballImporter();
  final body = HistoricalBaseballImporter.decodeOfficialHtml(
    await importer.fetchOfficial(Uri.parse(url)),
  );
  final page = HistoricalBaseballImporter.parseNpbYearPage(
    body,
    year: year,
    leagueId: leagueId,
  );
  final names = page.standings.map((row) => row.teamName).toList();
  print(
      '$label standings=${page.standings.length} unique=${names.toSet().length} hitting=${page.hitting.length} pitching=${page.pitching.length}');
  for (final row in page.standings) {
    print(
        '  stand ${row.teamName} G${row.games} W${row.wins} L${row.losses} D${row.draws}');
  }
  if (page.hitting.isNotEmpty) {
    final first = page.hitting.first;
    print(
        '  hit ${first.playerName} (${first.teamAlias}) -> ${HistoricalBaseballImporter.resolveNpbTeamAlias(first.teamAlias, names)}');
  }
  if (page.pitching.isNotEmpty) {
    final first = page.pitching.first;
    print(
        '  pit ${first.playerName} (${first.teamAlias}) -> ${HistoricalBaseballImporter.resolveNpbTeamAlias(first.teamAlias, names)}');
  }
}

Future<void> main() async {
  await dump('1936s', 'https://npb.jp/bis/yearly/yakyuremmei_1936s.html', 1936);
  await dump('1936f', 'https://npb.jp/bis/yearly/yakyuremmei_1936f.html', 1936);
  await dump('1950c', 'https://npb.jp/bis/yearly/centralleague_1950.html', 1950);
  await dump('2005c', 'https://npb.jp/bis/yearly/centralleague_2005.html', 2005);
}
