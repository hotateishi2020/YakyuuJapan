import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'app/StrengthUsage.dart';
import 'app/StrengthContracts.dart';
import 'app/OverseasContracts.dart';
import 'app/ContractExchange.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.first);
  final client = http.Client();
  final cache = Directory('/tmp/koko-npb-overseas-$year')..createSync(recursive: true);
  final report = <Map<String, dynamic>>[];
  Future<String> get(String url, String name) async {
    final file = File('${cache.path}/$name');
    if (file.existsSync()) return file.readAsStringSync();
    final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes);
    file.writeAsStringSync(body);
    return body;
  }

  try {
    final history = usageMap(jsonDecode(await get('https://frontofficemoves.com/data/contracts.json', 'contracts.json')));
    final rates = parseContractExchangeRates(await get('https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml', 'fx.xml'));
    final teams = await Postgres.withConnection((c) => c.execute("SELECT id_team,payload FROM t_team_strength WHERE code_org='npb' AND int_year=\$1", parameters: [year]));
    for (final row in teams) {
      final team = usageMap(row[1] is String ? jsonDecode(row[1] as String) : row[1]);
      final updates = <String, Map<String, dynamic>>{};
      final candidates = usageMaps(team['roster']).where((p) => RegExp('[ァ-ヶ]|^[王呉張宋孫陳鄭黄徐劉蕭]').hasMatch('${p['name']}') || ['林安可', '林冠臣', '林燦'].contains(p['name'])).toList();
      for (var offset = 0; offset < candidates.length; offset += 4) {
        await Future.wait(candidates.skip(offset).take(4).map((player) async {
          final id = '${player['source_player_id']}';
          final status = <String, dynamic>{'team': team['name_team'], 'name': player['name'], 'npb_id': id};
          try {
            final profileUrl = 'https://npb.jp/bis/players/$id.html';
            final doc = html.parse(await get(profileUrl, '$id.html'));
            final name = RegExp(r'\(([^)]+)\)').firstMatch(doc.querySelector('#pc_v_kana')?.text ?? '')?[1]?.trim();
            if (name == null) throw StateError('公式英字名なし');
            final people = usageMaps(usageMap(jsonDecode(await get('https://statsapi.mlb.com/api/v1/people/search?names=${Uri.encodeComponent(name)}', '$id-mlb.json')))['people']);
            // Search results are name-matched by MLB; require exact DOB and a
            // unique identity as well. No surname-only fallback.
            final matches = people.where((p) => p['birthDate'] == player['date_birth']).toList();
            if (matches.length != 1) throw StateError('氏名・生年月日の一意一致なし');
            final mlbId = usageInt(matches.single['id']);
            status['mlb_id'] = mlbId;
            final record = usageMaps(team['contracts']).where((p) => p['player_key'] == player['player_key']).firstOrNull ?? <String, dynamic>{'name': player['name'], 'player_key': player['player_key']};
            final npbYears = usageMaps(record['salary_history'])
                .where((s) {
                  final t = '${s['team']}';
                  return salaryTeamSlugs.keys.any(t.contains) || t.contains('横浜');
                })
                .map((s) => usageInt(s['year']))
                .where((y) => y > 0)
                .toList();
            // Include official NPB appearances to avoid importing post-arrival deals.
            npbYears.addAll(doc.querySelectorAll('#pc_stats td').map((e) => e.text.trim()).where((s) => RegExp(r'^(19|20)\d{2}$').hasMatch(s)).map(int.parse));
            if (npbYears.isEmpty) throw StateError('NPB初年度未確認');
            npbYears.sort();
            final overseas = overseasContractHistory(usageMaps(history['$mlbId']), npbYears.first, rates, mlbId);
            overseas['identity_source'] = profileUrl;
            overseas['identity_name'] = name;
            overseas['identity_birth_date'] = player['date_birth'];
            overseas['first_npb_year'] = npbYears.first;
            final count = usageMaps(overseas['periods']).length;
            if (count > 0) updates['${player['player_key']}'] = overseas;
            status['periods'] = count;
            status['salaries'] = usageMaps(overseas['salary_history']).length;
            status['status'] = count > 0 ? 'matched' : 'no_pre_npb_contracts';
          } catch (e) {
            status['status'] = '$e';
          }
          report.add(status);
        }));
      }
      if (updates.isNotEmpty) {
        await Postgres.withConnection((c) => c.runTx((tx) async {
              final latest = await tx.execute("SELECT payload FROM t_team_strength WHERE code_org='npb' AND int_year=\$1 AND id_team=\$2 FOR UPDATE", parameters: [year, row[0]]);
              final raw = latest.single[0];
              final payload = usageMap(raw is String ? jsonDecode(raw) : raw);
              final records = usageMaps(payload['contracts']).toList();
              for (final entry in updates.entries) {
                final index = records.indexWhere((p) => p['player_key'] == entry.key);
                final existing = index >= 0 ? records[index] : usageMaps(team['roster']).firstWhere((p) => p['player_key'] == entry.key);
                final merged = mergeOverseasContracts(existing, entry.value);
                if (index >= 0) {
                  records[index] = merged;
                } else {
                  records.add(merged);
                }
              }
              await tx.execute("UPDATE t_team_strength SET payload=payload || \$1::jsonb,updated_at=NOW() WHERE code_org='npb' AND int_year=\$2 AND id_team=\$3", parameters: [
                jsonEncode({'contracts': records}),
                year,
                row[0]
              ]);
            }));
      }
      print('${team['name_team']}: ${updates.length}/${candidates.length}人 登録');
      File('${cache.path}/report.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
  } finally {
    client.close();
  }
  exit(0);
}
