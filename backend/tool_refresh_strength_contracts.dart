import 'app/ContractTransferShares.dart';
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'app/StrengthUsage.dart';
import 'app/OverseasContracts.dart';
import 'app/ContractSupplements.dart';
import 'app/StrengthContracts.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  await refreshContractTransfers(year);
  final client = http.Client();
  var errors = 0;
  final cache = Directory('/tmp/koko-contract-cache-$year')
    ..createSync(recursive: true);
  final teams = await Postgres.withConnection((c) => c.execute(
      "SELECT id_team,payload FROM t_team_strength WHERE code_org='npb' AND int_year=\$1",
      parameters: [year]));
  for (final row in teams) {
    try {
      final team =
          usageMap(row[1] is String ? jsonDecode(row[1] as String) : row[1]);
      final slug = salaryTeamSlugs['${team['name_team']}'];
      if (slug == null) continue;
      final page = html.parse(await StrengthUsage.get(
          client, 'https://npb.athlete-salary.com/teams/$slug/$year/'));
      final links = page.querySelectorAll('a.npbsd-ranking-table-row');
      final visited = <String>{};
      final pending = page
          .querySelectorAll('a[href]')
          .map((a) => a.attributes['href']!)
          .where((u) =>
              u.startsWith(
                  'https://npb.athlete-salary.com/teams/$slug/$year/') &&
              u.contains('pg='))
          .toSet();
      while (pending.isNotEmpty) {
        final url = pending.first;
        pending.remove(url);
        if (!visited.add(url)) continue;
        final extra = html.parse(await StrengthUsage.get(client, url));
        final known = links.map((a) => a.attributes['href']).toSet();
        links.addAll(extra
            .querySelectorAll('a.npbsd-ranking-table-row')
            .where((a) => !known.contains(a.attributes['href'])));
        pending.addAll(extra
            .querySelectorAll('a[href]')
            .map((a) => a.attributes['href']!)
            .where((u) =>
                u.startsWith(
                    'https://npb.athlete-salary.com/teams/$slug/$year/') &&
                u.contains('pg=') &&
                !visited.contains(u)));
      }
      if (links.isEmpty) throw StateError('年俸一覧が空です');
      final records = <Map<String, dynamic>>[];
      for (var offset = 0; offset < links.length; offset += 4) {
        final batch =
            await Future.wait(links.skip(offset).take(4).map((link) async {
          final url = link.attributes['href']!;
          final name = link
              .querySelector('.npbsd-player-detail-link-label')!
              .text
              .trim();
          final key = salaryPlayerKey(name, usageMaps(team['roster']), url);
          final file = File(
              '${cache.path}/${Uri.parse(url).path.split('/').where((p) => p.isNotEmpty).last}.html');
          final source = file.existsSync()
              ? file.readAsStringSync()
              : await StrengthUsage.get(client, url);
          if (!file.existsSync()) file.writeAsStringSync(source);
          final record = parseContractHistory(source, url, name, key);
          final old = usageMaps(team['contracts'])
              .where((r) => r['player_key'] == key)
              .firstOrNull;
          return mergeOverseasContracts(
              record, usageMap(old?['overseas_contracts']));
        }));
        records.addAll(batch);
      }
      await Postgres.withConnection((c) => c.execute(
              "UPDATE t_team_strength SET payload=payload || \$1::jsonb,updated_at=NOW() WHERE code_org='npb' AND int_year=\$2 AND id_team=\$3",
              parameters: [
                jsonEncode({
                  'contracts':
                      records.map((r) => supplementContracts('npb', r)).toList()
                }),
                year,
                row[0]
              ]));
      print(
          '${team['name_team']}: ${records.length}人 ${records.fold<int>(0, (n, p) => n + usageMaps(p['salary_history']).length)}年俸履歴');
    } catch (e) {
      errors++;
      stderr.writeln('${row[0]}: $e');
    }
  }
  client.close();
  exit(errors == 0 ? 0 : 1);
}
