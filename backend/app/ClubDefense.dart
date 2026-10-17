import 'dart:convert';
import 'package:http/http.dart' as http;
import 'StrengthUsage.dart';

final _cache = <int, (DateTime, Map<String, dynamic>)>{};

Map<String, dynamic> parseTeamOaa(String source, int year, String url) {
  final match = RegExp(r'var data = (\[.*?\]);', dotAll: true).firstMatch(source);
  if (match == null) throw StateError('MLB OAA data not found');
  final result = <String, dynamic>{};
  for (final row in usageMaps(jsonDecode(match[1]!))) {
    if ('${row['year']}' != '$year' || row['entity_code'] != 'Fielding_Team') continue;
    final value = double.tryParse('${row['outs_above_average']}');
    final opportunities = int.tryParse('${row['n']}');
    if (value == null || !value.isFinite || opportunities == null || opportunities <= 0) continue;
    result['${row['entity_id']}'] = {'metric': 'OAA', 'value': value,
      'opportunities': opportunities, 'year': year, 'source_url': url,
      'checked_at': DateTime.now().toUtc().toIso8601String()};
  }
  if (result.length != 30) throw StateError('MLB OAA coverage: ${result.length}/30');
  return result;
}

Future<Map<String, dynamic>> fetchTeamDefense(http.Client client, int year, dynamic teamId) async {
  var cached = _cache[year];
  if (cached == null || DateTime.now().difference(cached.$1) > const Duration(hours: 5)) {
    final data = <String, dynamic>{};
    for (final position in ['if', 'of']) {
      final url = 'https://baseballsavant.mlb.com/leaderboard/outs_above_average?type=Fielding_Team&year=$year&team=&range=year&min=q&pos=$position&roles=&viz=hide';
      data[position] = parseTeamOaa(await StrengthUsage.get(client, url), year, url);
    }
    cached = (DateTime.now(), data);
    _cache[year] = cached;
  }
  return {for (final entry in {'infield': 'if', 'outfield': 'of'}.entries)
    entry.key: cached.$2[entry.value]['$teamId']};
}
