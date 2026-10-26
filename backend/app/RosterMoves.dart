import 'NpbResearchEvents.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import '../tools/Postgres.dart';
import 'StrengthUsage.dart';
import 'ScheduledLog.dart';
import 'NpbRosterTransactions.dart';

const rosterMovesUrl = 'https://baseball.yahoo.co.jp/npb/transfer';

List<Map<String, dynamic>> parseRosterMoves(String source, int year) {
  final result = <Map<String, dynamic>>[];
  for (final table in html.parse(source).querySelectorAll('table.bb-transferTable')) {
    var section = table.parent;
    while (section != null && section.localName != 'section') {
      section = section.parent;
    }
    final team = section?.querySelector('h3')?.text.trim();
    if (team == null) continue;
    for (final row in table.querySelectorAll('tbody tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length != 5) continue;
      final date = cells[0].text.trim().split('/');
      if (date.length != 3) continue;
      final state = cells[1].text.trim(), reason = cells[4].text.trim();
      if (RegExp('調査|検討|可能性|交渉中|見込み').hasMatch('$state $reason')) continue;
      final incoming = state == '入団';
      if (!incoming && state != '退団') continue;
      final eventYear = int.tryParse(date[0]);
      final month = int.tryParse(date[1]) ?? 0;
      if (eventYear != year && !(incoming && eventYear == year - 1 && month >= 9)) {
        continue;
      }
      final name = (cells[2].querySelector('a')?.text ?? cells[2].text).replaceAll('※', '').trim();
      final href = cells[2].querySelector('a')?.attributes['href'];
      result.add({
        'source_team_verified': true,
        'team': team,
        'name': name,
        'kind': incoming ? 'arrival' : 'departure',
        'position_group': cells[3].text.trim(),
        'status_as_of': '${date[0]}-${date[1].padLeft(2, '0')}-${date[2].padLeft(2, '0')}',
        'status_source': rosterMovesUrl,
        'departure_reason': reason,
        if (incoming && RegExp('FA|ＦＡ|トレード|現役ドラフト|新外国人').hasMatch(reason))
          'move_method': reason.contains('現役ドラフト')
              ? '現役ドラフト'
              : reason.contains('トレード')
                  ? 'トレード'
                  : RegExp('FA|ＦＡ').hasMatch(reason)
                      ? 'FA移籍'
                      : '新外国人',
        if (href != null) 'profile_source': Uri.parse(rosterMovesUrl).resolve(href).toString(),
        if (!incoming)
          'departure_type': reason.contains('引退')
              ? 'retired'
              : reason.contains('戦力外')
                  ? 'non_tender'
                  : reason.contains('自由契約')
                      ? 'released'
                      : reason.contains('移籍')
                          ? 'transfer'
                          : 'departure',
        if (incoming) 'previous_team_name': reason.replaceAll(RegExp(r'から(?:移籍|加入)?|より(?:移籍|加入)?|移籍|加入|トレード|自由契約|育成契約|新外国人|[（）()]'), ' ').trim(),
      });
    }
  }
  if (result.isEmpty) throw const FormatException('当年の入退団一覧を取得できませんでした');
  return result;
}

String _name(dynamic name) => usageName('$name').replaceAll('※', '');
bool _same(Map<String, dynamic> p, Map<String, dynamic> event) => (event['player_key'] != null && p['player_key'] == event['player_key']) || _name(p['name']) == _name(event['name']) || (event['aliases'] is List && (event['aliases'] as List).any((a) => _name(p['name']) == _name(a)));

int _statusPriority(Map<String, dynamic> e) => e['kind'] != 'status'
    ? 3
    : '${e['move_status']}'.contains('権保有')
        ? 0
        : '${e['move_status']}'.contains('未定')
            ? 1
            : 2;

bool _appliesToYear(Map<String, dynamic> event, int year) {
  final date = DateTime.tryParse('${event['status_as_of']}');
  return date != null && (date.year == year || (event['kind'] == 'arrival' && date.year == year - 1 && date.month >= 9));
}

/// Applies only events from this display year; departed players remain in their old team's grid.
void applyRosterMoves(List<Map<String, dynamic>> teams, List<Map<String, dynamic>> events, int year, {bool reconcileSource = true, List<Map<String, dynamic>> previous = const [], List<Map<String, dynamic>> identities = const []}) {
  for (final team in teams) {
    final roster = usageMaps(team['roster']);
    final old = previous.where((t) => t['id_team'] == team['id_team']).expand((t) => usageMaps(t['roster'])).toList();
    final relevant = events.where((e) => (_appliesToYear(e, year)) && _name(e['team']) == _name(team['name_team'])).toList()..sort((a, b) => ('${a['status_as_of']}'.compareTo('${b['status_as_of']}') != 0 ? '${a['status_as_of']}'.compareTo('${b['status_as_of']}') : _statusPriority(a).compareTo(_statusPriority(b))));
    // Only a complete source snapshot can withdraw entries; research is incremental.
    // Remove withdrawn/source-corrected entries without deleting original roster members.
    roster.removeWhere((p) => reconcileSource && p['status_source'] == rosterMovesUrl && !relevant.any((e) => _same(p, e)) && ('${p['player_key']}'.startsWith('move:') || p['move_added'] == true || previous.where((t) => t['id_team'] != team['id_team']).expand((t) => usageMaps(t['roster'])).any((other) => other['player_key'] == p['player_key'])));
    for (final p in roster.where((p) => reconcileSource && p['status_source'] == rosterMovesUrl && !relevant.any((e) => _same(p, e)))) {
      for (final key in ['status_source', 'status_as_of', 'departure_confirmed', 'departure_type', 'departure_reason', 'new_arrival', 'arrival_year', 'arrival_as_of', 'departure_as_of', 'move_method_as_of', 'previous_team']) {
        p.remove(key);
      }
    }
    for (final event in relevant) {
      var player = roster.where((p) => _same(p, event)).firstOrNull;
      if (player == null && event['kind'] == 'status') continue;
      if (player == null) {
        final candidates = [...old, for (final t in previous) ...usageMaps(t['roster'])].where((p) => _same(p, event)).toList();
        player = candidates.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(candidates.first);
        // Never carry another team's usage into a new team's lineup.
        if (event['kind'] == 'arrival') {
          for (final field in ['level_appearances', 'lower_level_usage', 'level_workload', 'main_level']) {
            player.remove(field);
          }
        }
        player.addAll({
          'move_added': true,
          'name': event['name'],
          'position_group': event['position_group'],
          'player_key': event['player_key'] ?? player['player_key'] ?? 'move:$year:${team['id_team']}:${_name(event['name'])}',
          for (final field in ['date_birth', 'throws', 'bats', 'source_player_id'])
            if (event[field] != null) field: event[field],
        });
        roster.add(player);
      }
      player.addAll({'status_as_of': event['status_as_of'], 'status_source': event['status_source']});
      if (event['kind'] == 'status') {
        if (player['departure_confirmed'] != true) {
          player['move_status'] = event['move_status'];
          player['move_status_year'] = event['status_year'] ?? year;
        }
        continue;
      }
      player.remove('move_status');
      player.remove('move_status_year');
      if (event['move_method'] != null) {
        player['move_method'] = event['move_method'];
        player['move_method_year'] = year;
        player['move_method_as_of'] = event['status_as_of'];
      }
      if (event['destination_team_name'] != null) player['destination_team_name'] = event['destination_team_name'];
      if (event['kind'] == 'departure') {
        player.addAll({'departure_confirmed': true, 'departure_as_of': event['status_as_of'], 'departure_type': event['departure_type'], 'departure_reason': event['departure_reason'], 'new_arrival': false});
      } else {
        for (final field in ['departure_type', 'departure_reason', 'transfer_confirmed', 'retirement_confirmed', 'released_confirmed']) {
          player.remove(field);
        }
        player.addAll({'departure_confirmed': false, 'new_arrival': true, 'arrival_year': year, 'arrival_as_of': event['status_as_of']});
        final previousName = '${event['previous_team_name'] ?? ''}';
        final matches = identities.where((t) => previousName.isNotEmpty && [t['name_team'], t['name_short'], t['name_shortest']].whereType<String>().any((s) => s.length >= 2 && _name(previousName).contains(_name(s)))).toList();
        final identity = matches.length == 1 ? matches.single : null;
        player['previous_team'] = event['previous_team'] ??
            {
              'name': previousName.isEmpty ? '前所属未確認' : previousName,
              'label': identity?['name_shortest'] ?? previousName,
              'color_back': identity?['color_back'],
              'color_font': identity?['color_font'],
            };
      }
    }
    team['roster'] = roster;
  }
}

class RosterMoves {
  static Timer? _timer;
  static bool _busy = false;
  static File _file(int year) => File('${Directory('backend/data').existsSync() ? 'backend/' : ''}data/roster-moves-$year.json');
  static List<Map<String, dynamic>> verified(int year) {
    final file = File('${Directory('backend/assets').existsSync() ? 'backend/' : ''}assets/data/roster-moves-verified-$year.json');
    return file.existsSync() ? usageMaps(jsonDecode(file.readAsStringSync())) : [];
  }

  static String eventKey(Map<String, dynamic> e) => '${e['team']}:${_name(e['name'])}:${e['kind']}:${e['kind'] == 'status' ? e['move_status'] : ''}';
  static List<Map<String, dynamic>> cached(int year) {
    final file = _file(year), prior = _file(year - 1);
    final values = [
      if (prior.existsSync()) ...usageMaps(jsonDecode(prior.readAsStringSync())).where((e) => _appliesToYear(e, year)),
      if (file.existsSync()) ...usageMaps(jsonDecode(file.readAsStringSync())),
      ...verified(year),
    ];
    final merged = <String, Map<String, dynamic>>{};
    for (final e in values) {
      final key = eventKey(e);
      if ('${merged[key]?['status_as_of'] ?? ''}'.compareTo('${e['status_as_of']}') > 0) continue;
      merged[key] = e;
    }
    return merged.values.toList();
  }

  static void start() {
    _timer?.cancel();
    Future<void> tick() async {
      try {
        await ScheduledLog.run('roster_moves', () => refresh(DateTime.now().year));
      } catch (e) {
        print('入退団情報更新失敗: $e');
      }
    }

    // Startup refresh is asynchronous and never blocks a screen request.
    unawaited(tick());
    _timer = Timer.periodic(const Duration(hours: 6), (_) => unawaited(tick()));
  }

  static Future<void> attach(int year, List<Map<String, dynamic>> teams) async {
    final events = cached(year);
    if (events.isEmpty) return;
    final previous = await Postgres.withConnection((c) async => (await c.execute("SELECT payload FROM t_team_strength WHERE code_org='npb' AND int_year=\$1", parameters: [year])).map((r) => usageMap(r[0] is String ? jsonDecode(r[0] as String) : r[0])).toList());
    final identities = await _identities();
    applyRosterMoves(teams, events, year, previous: previous, identities: identities);
  }

  static Future<List<Map<String, dynamic>>> _identities() => Postgres.withConnection((c) async => (await c.execute('SELECT id AS id_team,name_short AS name_team,name_shortest,color_back,color_font FROM m_team WHERE id_league IN (1,2,3,4) AND NOT COALESCE(flg_delete,false)')).map((r) => r.toColumnMap()).toList());
  static Future<Map<String, dynamic>> refresh(int year) async {
    if (_busy) return {'busy': true};
    _busy = true;
    final client = http.Client();
    try {
      final response = await client.get(Uri.parse(rosterMovesUrl)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError('入退団一覧 HTTP ${response.statusCode}');
      }
      final fetched = parseRosterMoves(utf8.decode(response.bodyBytes), year);
      for (final y in [year - 1, year]) {
        for (final page in ['pn_traded', 'fa_filed', if (y == year) 'fa_qualified']) {
          final url = 'https://npb.jp/announcement/$y/$page.html';
          try {
            final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
            if (r.statusCode == 404) continue; // Not published yet this season.
            if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}');
            fetched.addAll(parseNpbTransactions(utf8.decode(r.bodyBytes), url, y));
          } catch (e) {
            print('移籍・FA公示取得保留: $url $e');
          }
        }
      }
      final events = {for (final e in cached(year).where((e) => e['status_source'] != rosterMovesUrl || e['source_team_verified'] == true)) '${e['team']}:${_name(e['name'])}:${e['kind']}:${e['kind'] == 'status' ? e['move_status'] : ''}': e};
      for (final e in [...fetched, ...verified(year)]) {
        final key = '${e['team']}:${_name(e['name'])}:${e['kind']}:${e['kind'] == 'status' ? e['move_status'] : ''}';
        if ('${events[key]?['status_as_of'] ?? ''}'.compareTo('${e['status_as_of']}') > 0) continue;
        events[key] = {...?events[key], ...e};
      }
      final values = events.values.toList();
      final file = _file(year);
      final temp = File('${file.path}.tmp');
      temp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(values));
      temp.renameSync(file.path);
      final identities = await _identities();
      final researched = await Postgres.withConnection((c) => NpbResearchEvents.read(c, year));
      var count = 0;
      await Postgres.withConnection((c) => c.runTx((tx) async {
            final rows = await tx.execute("SELECT id_team,payload FROM t_team_strength WHERE code_org='npb' AND int_year=\$1 FOR UPDATE", parameters: [year]);
            final teams = rows.map((r) => usageMap(r[1] is String ? jsonDecode(r[1] as String) : r[1])).toList();
            final previous = [
              for (final t in teams) {...t, 'roster': usageMaps(t['roster']).map((p) => Map<String, dynamic>.from(p)).toList()}
            ];
            applyRosterMoves(teams, values, year, previous: previous, identities: identities);
            NpbResearchEvents.apply(teams, researched, year);
            for (final t in teams) {
              await tx.execute("UPDATE t_team_strength SET payload=jsonb_set(payload,'{roster}',\$1::jsonb),updated_at=NOW() WHERE code_org='npb' AND int_year=\$2 AND id_team=\$3", parameters: [jsonEncode(t['roster']), year, t['id_team']]);
              count++;
            }
          }));
      return {'events': values.length, 'teams': count};
    } finally {
      client.close();
      _busy = false;
    }
  }
}
