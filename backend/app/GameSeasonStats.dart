import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'PlayerDetail.dart' show officialPlayerId;
import 'PlayerIdentityName.dart';
import 'StrengthUsage.dart';
import '../tools/Postgres.dart';

const gameSeasonStatsVersion = 2;
const _npbCodes = ['g', 't', 'db', 'c', 'd', 's', 'h', 'f', 'm', 'l', 'e', 'b'];

/// Official team tables include unqualified hitters and relief pitchers.
List<Map<String, dynamic>> parseNpbGameSeasonStats(String body, String code, int year, {required bool pitching}) {
  final doc = html.parse(body);
  if (!(doc.querySelector('title')?.text ?? '').contains('$year')) {
    throw const FormatException('Wrong NPB season');
  }
  final result = <Map<String, dynamic>>[];
  for (final table in doc.querySelectorAll('table')) {
    final headers = table.querySelectorAll('thead th').map((e) => e.text.replaceAll(RegExp(r'\s'), '')).toList();
    if (!headers.contains(pitching ? '防御率' : '打率')) continue;
    for (final tr in table.querySelectorAll('tbody tr')) {
      final cells = tr.querySelectorAll('td');
      if (cells.length != headers.length) continue;
      final values = <String, dynamic>{};
      for (final title in pitching ? ['防御率', '勝利', 'ホールド', 'セーブ'] : ['打率', '本塁打']) {
        final index = headers.indexOf(title);
        if (index < 0) continue;
        final value = cells[index].text.replaceAll(RegExp(r'\s'), '');
        if (num.tryParse(value)?.isFinite == true) values[title] = value;
      }
      if (values.isEmpty) continue;
      final name = cells.first.text.replaceAll(RegExp(r'^[*+\s]+'), '').trim();
      if (name.isEmpty) continue;
      result.add({
        'org': 'npb',
        'name': name,
        'team_code': code,
        'group': pitching ? 'pitching' : 'hitting',
        'values': values,
        'samples': {
          for (final title in pitching ? ['投球回', '自責点'] : ['打数', '安打'])
            if (headers.contains(title)) title: cells[headers.indexOf(title)].text.replaceAll(RegExp(r'\s'), '')
        },
        'source': 'https://npb.jp/bis/$year/stats/id${pitching ? 'p' : 'b'}1_$code.html'
      });
    }
  }
  if (result.isEmpty) throw const FormatException('Empty NPB statistics');
  return result;
}

List<Map<String, dynamic>> parseMlbGameSeasonStats(Map<String, dynamic> data, int year, {required bool pitching}) {
  final result = <Map<String, dynamic>>[];
  for (final block in usageMaps(data['stats'])) {
    if (usageMap(block['group'])['displayName'] != (pitching ? 'pitching' : 'hitting')) continue;
    for (final split in usageMaps(block['splits'])) {
      if ('${split['season']}' != '$year') continue;
      final player = usageMap(split['player']), stat = usageMap(split['stat']);
      if (player['id'] == null) continue;
      final values = <String, dynamic>{};
      final fields = pitching ? {'防御率': 'era', '勝利': 'wins', 'ホールド': 'holds', 'セーブ': 'saves'} : {'打率': 'avg', '本塁打': 'homeRuns'};
      for (final field in fields.entries) {
        final value = stat[field.value];
        if (num.tryParse('$value')?.isFinite == true) values[field.key] = value;
      }
      // Never synthesize missing rate/count fields as zero.
      if (values.isNotEmpty) {
        result.add({
          'org': 'mlb',
          'source_id': '${player['id']}',
          'name': player['fullName'],
          'group': pitching ? 'pitching' : 'hitting',
          'total': split['isTotal'] == true || split['team'] == null,
          'team_id': usageMap(split['team'])['id'],
          'values': values,
          'samples': pitching ? {'投球回': stat['inningsPitched'], '自責点': stat['earnedRuns']} : {'打数': stat['atBats'], '安打': stat['hits']}
        });
      }
    }
  }
  return result;
}

/// Match stable official IDs first, otherwise full registered aliases only.
/// An initial or surname is never sufficient to attach another player's stats.
void addOfficialGameSeasonStats(List<Map<String, dynamic>> stats, List<Map<String, dynamic>> people, List<Map<String, dynamic>> records) {
  for (final person in people) {
    final org = [3, 4].contains(person['id_league']) ? 'mlb' : 'npb';
    final id = officialPlayerId(person);
    final aliases = ['${person['name_full_summary'] ?? person['name_full'] ?? ''}', ...List<String>.from(person['name_patterns'] as List? ?? [])];
    final matches = records.where((r) => r['org'] == org && (r['source_id'] != null ? (id != null && r['source_id'] == id || id == null && (r['aliases'] as List? ?? []).any((a) => matchesPlayerPatterns('$a', aliases))) : matchesPlayerPatterns('${r['name']}', aliases))).toList();
    if (matches.map((r) => r['source_id']).where((id) => id != null).toSet().length > 1) continue;
    for (final group in ['hitting', 'pitching']) {
      var candidates = matches.where((r) => r['group'] == group).toList();
      final totals = candidates.where((r) => r['total'] == true).toList();
      if (totals.isNotEmpty) candidates = totals;
      if (candidates.isEmpty) continue;
      var record = candidates.first;
      if (candidates.length > 1) {
        final samples = candidates.map((r) => usageMap(r['samples'])).toList();
        final rate = group == 'pitching' ? '防御率' : '打率';
        final values = <String, dynamic>{};
        for (final title in group == 'pitching' ? ['勝利', 'ホールド', 'セーブ'] : ['本塁打']) {
          if (candidates.every((r) => usageMap(r['values'])[title] != null)) {
            values[title] = candidates.fold<int>(0, (n, r) => n + usageInt(usageMap(r['values'])[title]));
          }
        }
        final sampleKey = group == 'pitching' ? '投球回' : '打数';
        final countKey = group == 'pitching' ? '自責点' : '安打';
        if (samples.every((s) => num.tryParse('${s[sampleKey]}') != null && num.tryParse('${s[countKey]}') != null)) {
          int outs(dynamic raw) {
            final p = '$raw'.split('.');
            return int.parse(p.first) * 3 + (p.length > 1 ? int.parse(p[1].substring(0, 1)) : 0);
          }

          final denominator = samples.fold<int>(0, (n, s) => n + (group == 'pitching' ? outs(s[sampleKey]) : usageInt(s[sampleKey])));
          final numerator = samples.fold<int>(0, (n, s) => n + usageInt(s[countKey]));
          if (denominator > 0) values[rate] = (numerator * (group == 'pitching' ? 27 : 1) / denominator).toStringAsFixed(group == 'pitching' ? 2 : 3);
        }
        record = {...record, 'values': values};
      }
      if (record['source_id'] == null && people.any((other) => other['id_player'] != person['id_player'] && other['id_league'] == person['id_league'] && matchesPlayerPatterns('${record['name']}', ['${other['name_full_summary'] ?? ''}']) && officialPlayerId(other) != id)) {
        continue;
      }
      for (final value in usageMap(record['values']).entries) {
        stats.removeWhere((s) => '${s['id_player']}' == '${person['id_player']}' && (s['title'] == value.key || value.key == '勝利' && s['title'] == '最多勝'));
        stats.add({'id_player': person['id_player'], 'id_team': person['id_team'], 'id_league': person['id_league'], 'name_player': person['name_full_summary'] ?? person['name_full'], 'title': value.key, 'stats': value.value, 'source_url': record['source']});
      }
    }
  }
}

class GameSeasonStats {
  static bool _busy = false;
  static File file(int year) => File('${Directory('backend/data').existsSync() ? 'backend/' : ''}data/game-season-stats-$year.json');
  static List<Map<String, dynamic>> cached(int year) {
    final source = file(year);
    if (!source.existsSync()) return [];
    try {
      final data = usageMap(jsonDecode(source.readAsStringSync()));
      if (data['year'] != year) return [];
      return usageMaps(data['records']);
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> refresh(int year) async {
    if (_busy) return {'skipped': true};
    _busy = true;
    final client = http.Client();
    final errors = <String>[];
    final records = cached(year);
    Future<void> load(String key, Uri uri, FutureOrRecords Function(String) parse) async {
      try {
        final response = await client.get(uri).timeout(const Duration(seconds: 25));
        if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
        final next = parse(utf8.decode(response.bodyBytes));
        if (next.isEmpty) throw const FormatException('Empty official statistics');
        records.removeWhere((r) => r['batch'] == key);
        records.addAll(next.map((r) => {...r, 'batch': key, 'checked_at': DateTime.now().toUtc().toIso8601String(), 'source': uri.toString()}));
      } catch (error) {
        errors.add('$key: $error');
      }
    }

    try {
      for (final code in _npbCodes) {
        for (final pitching in [false, true]) {
          final group = pitching ? 'pitching' : 'hitting';
          await load('npb:$code:$group', Uri.parse('https://npb.jp/bis/$year/stats/id${pitching ? 'p' : 'b'}1_$code.html'), (body) => parseNpbGameSeasonStats(body, code, year, pitching: pitching));
        }
      }
      for (final pitching in [false, true]) {
        final group = pitching ? 'pitching' : 'hitting';
        final uri = Uri.https('statsapi.mlb.com', '/api/v1/stats', {
          'stats': 'season',
          'group': group,
          'season': '$year',
          'sportIds': '1',
          'playerPool': 'ALL',
          'gameType': 'R',
          'limit': '10000',
        });
        await load('mlb:$group', uri, (body) {
          final data = usageMap(jsonDecode(body));
          for (final block in usageMaps(data['stats'])) {
            if (usageInt(block['totalSplits']) > usageMaps(block['splits']).length) {
              throw const FormatException('Truncated MLB player statistics');
            }
          }
          return parseMlbGameSeasonStats(data, year, pitching: pitching);
        });
      }
      // Rows created by old score feeds can lack an ID. Only explicitly
      // verified aliases can bridge those rows to an official player ID.
      final aliasesFile = File('${Directory('backend/data').existsSync() ? 'backend/' : ''}data/game-season-identity-aliases.json');
      if (aliasesFile.existsSync()) {
        final aliases = usageMaps(usageMap(jsonDecode(aliasesFile.readAsStringSync()))['mlb']);
        for (final r in records.where((r) => r['org'] == 'mlb')) {
          final known = aliases.where((a) => a['source_id'] == r['source_id']).firstOrNull;
          if (known != null) r['aliases'] = known['names'];
        }
      }
      // Individually verify absent regular-season groups for players who
      // appear in game feeds (for example postseason-only appearances).
      final bulkKeys = records.where((r) => r['org'] == 'mlb' && !'${r['batch']}'.startsWith('mlb:individual:')).map((r) => '${r['source_id']}:${r['group']}').toSet();
      records.removeWhere((r) => '${r['batch']}'.startsWith('mlb:individual:') && bulkKeys.contains('${r['source_id']}:${r['group']}'));
      final missing = await Postgres.withConnection((conn) async {
        final rows = await conn.execute('''SELECT p.id,p.name_full,p.url,p.identity_sources,t.id_league,
            bool_or(s.int_batting>0) AS batted, bool_or(s.double_inning_pitch>0 OR s.int_pitch>0) AS pitched
          FROM m_player p JOIN m_team t ON t.id=p.id_team
          JOIN t_game_summary s ON s.id_player=p.id JOIN t_game g ON g.id=s.id_game
          WHERE t.id_league IN(3,4) AND g.datetime_start>=make_date(\$1,1,1)
            AND g.datetime_start<make_date(\$1+1,1,1) AND NOT COALESCE(s.flg_delete,false)
          GROUP BY p.id,t.id_league''', parameters: [year]);
        return rows.map((r) => r.toColumnMap()).where((p) {
          final id = officialPlayerId(p);
          return id != null && ['hitting', 'pitching'].any((group) => p[group == 'hitting' ? 'batted' : 'pitched'] == true && !bulkKeys.contains('$id:$group'));
        }).toList();
      });
      for (final p in missing) {
        final id = officialPlayerId(p)!;
        final uri = Uri.https('statsapi.mlb.com', '/api/v1/people/$id', {
          'hydrate': 'stats(group=[hitting,pitching],type=[season],season=$year,gameType=R)',
        });
        await load('mlb:individual:$id', uri, (body) {
          final person = usageMaps(usageMap(jsonDecode(body))['people']).single;
          if ('${person['id']}' != id) throw const FormatException('Player ID mismatch');
          final individual = <Map<String, dynamic>>[];
          for (final pitching in [false, true]) {
            final group = pitching ? 'pitching' : 'hitting';
            if (p[pitching ? 'pitched' : 'batted'] != true) continue;
            if (bulkKeys.contains('$id:$group')) continue;
            final stats = parseMlbGameSeasonStats({'stats': person['stats']}, year, pitching: pitching);
            if (stats.isNotEmpty) {
              individual.addAll(stats);
            } else {
              individual.add({
                'org': 'mlb',
                'source_id': id,
                'name': person['fullName'],
                'group': group,
                'values': pitching ? {'防御率': '登板なし', '勝利': 0, 'ホールド': 0, 'セーブ': 0} : {'打率': '打席なし', '本塁打': 0}
              });
            }
          }
          return individual;
        });
      }
      if (records.isEmpty) throw StateError(errors.join('\n'));
      final out = file(year);
      await out.parent.create(recursive: true);
      final temp = File('${out.path}.tmp');
      await temp.writeAsString(jsonEncode({'year': year, 'records': records, 'errors': errors}), flush: true);
      await temp.rename(out.path);
      return {'year': year, 'records': records.length, 'errors': errors};
    } finally {
      client.close();
      _busy = false;
    }
  }
}

typedef FutureOrRecords = List<Map<String, dynamic>>;
