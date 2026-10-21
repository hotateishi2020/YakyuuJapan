import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/TeamStrength.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final client = http.Client();
  Directory('/tmp/koko-regular-mlb').createSync(recursive: true);
  Future<Map<String, dynamic>> get(String key, String url) async {
    final f = File('/tmp/koko-regular-mlb/$key.json');
    if (f.existsSync()) return usageMap(jsonDecode(f.readAsStringSync()));
    final r =
        await client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw StateError('$key HTTP ${r.statusCode}');
    final d = usageMap(jsonDecode(utf8.decode(r.bodyBytes)));
    f.writeAsStringSync(jsonEncode(d));
    return d;
  }

  final teams = await Postgres.withConnection((c) async => (await c.execute(
          'SELECT id AS id_team,name_short AS name_team,name_shortest,color_back,color_font FROM m_team WHERE id_league IN (3,4) AND NOT COALESCE(flg_delete,false)'))
      .map((r) => r.toColumnMap())
      .toList());
  final file = File('data/regular-history-mlb.json');
  final rows = file.existsSync()
      ? usageMaps(jsonDecode(file.readAsStringSync())['rows'])
      : <Map<String, dynamic>>[];
  final errors = <String>[];
  const api = 'https://statsapi.mlb.com/api/v1';
  List<Map<String, dynamic>> group(Map<String, dynamic> d, String name) => [
        for (final g in usageMaps(d['stats']))
          if (usageMap(g['group'])['displayName'] == name)
            ...usageMaps(g['splits'])
      ];
  for (var year = 2005; year <= 2025; year++) {
    try {
      final list =
          await get('$year-teams', '$api/teams?sportId=1&season=$year');
      final totals = await get('$year-totals',
          '$api/teams/stats?stats=season&group=hitting&season=$year&sportIds=1');
      final url =
          '$api/schedule?sportId=1&season=$year&gameTypes=R&hydrate=lineups&fields=dates,date,games,gamePk,status,abstractGameState,detailedState,officialDate,teams,away,home,team,id,lineups,homePlayers,awayPlayers,fullName';
      final schedule = await get('$year-schedule', url);
      final source = usageMaps(list['teams']);
      for (var offset = 0; offset < source.length; offset += 3) {
        await Future.wait(source.skip(offset).take(3).map((t) async {
          final code = '${t['abbreviation']}';
          final aliases = {
            'ANA': 'LAA',
            'FLA': 'MIA',
            'MON': 'WSH',
            'TBD': 'TB',
            'OAK': 'ATH'
          };
          final team = teams
              .where((v) =>
                  v['name_shortest'] == (aliases[code] ?? code) ||
                  v['name_shortest'] == code)
              .firstOrNull;
          if (team == null) {
            errors.add('$year $code: team mapping missing');
            return;
          }
          try {
            final data = await get('$year-${t['id']}',
                '$api/stats?stats=season&group=pitching,fielding&season=$year&sportIds=1&teamId=${t['id']}&playerPool=ALL&limit=5000');
            final identities = <String, Set<int>>{};
            final officialNames = <int,String>{};
            for (final g in usageMaps(data['stats'])) {
              for (final split in usageMaps(g['splits'])) {
                final player = usageMap(split['player']);
                officialNames[usageInt(player['id'])] = '${player['fullName']}';
                identities
                    .putIfAbsent('${player['fullName']}', () => {})
                    .add(usageInt(player['id']));
              }
            }
            final duplicates = identities.entries
                .where((e) => e.value.length > 1)
                .map((e) => e.key)
                .toSet();
            void disambiguate(dynamic value) {
              if (value is Map) {
                if (value.containsKey('fullName') && officialNames.containsKey(usageInt(value['id']))) value['fullName'] = officialNames[usageInt(value['id'])];
                if (duplicates.contains(value['fullName']) &&
                    value['id'] != null) {
                  value['fullName'] = '${value['fullName']}（ID ${value['id']}）';
                }
                for (final child in value.values) {
                  disambiguate(child);
                }
              } else if (value is List) {
                for (final child in value) {
                  disambiguate(child);
                }
              }
            }

            disambiguate(data);
            disambiguate(schedule);
            final payload = buildMlbTeamStrength(
                team: team,
                year: year,
                sourceTeamId: usageInt(t['id']),
                pitching: group(data, 'pitching'),
                fielding: group(data, 'fielding'),
                teamStats: group(totals, 'hitting'),
                schedule: schedule,
                sourceUrl: url);
            payload['club_name'] = team['name_team'];
            rows.removeWhere(
                (r) => r['year'] == year && r['id_team'] == team['id_team']);
            rows.add(payload);
          } catch (e) {
            errors.add('$year $code: $e');
          }
        }));
      }
    } catch (e) {
      errors.add('$year: $e');
    }
    rows.sort((a, b) => usageInt(b['year']).compareTo(usageInt(a['year'])));
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode({'rows': rows, 'errors': errors}));
    tmp.renameSync(file.path);
    stdout.writeln(
        '$year: ${rows.where((r) => r['year'] == year).length} teams; errors ${errors.length}');
  }
  client.close();
  stdout.writeln(jsonEncode(errors));
  await stdout.flush();
  exit(errors.isEmpty ? 0 : 1);
}
