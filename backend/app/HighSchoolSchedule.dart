import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

const highSchoolRounds = ['1回戦', '準々決勝', '準決勝', '決勝'];
String schoolName(Object? value) => '$value'
    .split(RegExp(r'[（(]'))
    .first
    .replaceAll(RegExp(r'\s'), '')
    .replaceAll('日本文理大付', '日本文理大附');

/// The source's stable round/slot IDs also identify games after postponements.
List<Map<String, dynamic>> parseHighSchoolResults(String body, int year) {
  final document = html.parse(body);
  if (!(document.querySelector('h1')?.text ?? '').contains('$year')) {
    throw const FormatException('Tournament year missing');
  }
  final result = <Map<String, dynamic>>[];
  for (final round in document.querySelectorAll('.gdw-round')) {
    final number = highSchoolRounds
        .indexOf(round.querySelector('.gdw-rh')?.text.trim() ?? '');
    if (number < 0) continue;
    for (final game in round.querySelectorAll('.gdw-m')) {
      final slot = int.tryParse(game.attributes['data-no'] ?? '');
      final sides = game.querySelectorAll('.gdw-s');
      if (slot == null || sides.length != 2) continue;
      final row = <String, dynamic>{'round': number, 'slot': slot - 1};
      for (var i = 0; i < 2; i++) {
        final side = i == 0 ? 'home' : 'away';
        row[side] = schoolName(sides[i].querySelector('.gdw-name')?.text ?? '');
        if (game.classes.contains('gdw-m--finished')) {
          row['score_$side'] = int.tryParse(
              sides[i].querySelector('.gdw-score')?.text.trim() ?? '');
        }
      }
      final date = RegExp(r'(\d{1,2})月(\d{1,2})日.*?(\d{1,2}:\d{2})')
          .firstMatch(game.querySelector('.gdw-court')?.text ?? '');
      if (date != null) {
        row['date'] = '${date[1]}/${date[2]}';
        row['time'] = date[3];
      }
      result.add(row);
    }
  }
  // Reject changed layouts and unrelated/partial tournament widgets.
  if (result.length != 15 ||
      result.map((m) => '${m['round']}:${m['slot']}').toSet().length != 15) {
    throw const FormatException('Incomplete tournament results');
  }
  return result;
}

String? highSchoolWinner(Map<String, dynamic> game) {
  final home = game['score_home'], away = game['score_away'];
  if (home is! int || away is! int || home == away) return null;
  return '${game[home > away ? 'home' : 'away']}';
}

/// Apply only final results of the expected teams, then advance those winners.
Map<String, dynamic> updateHighSchoolSchedule(Map<String, dynamic> current,
    List<Map<String, dynamic>> results, String source, DateTime now) {
  final updated = jsonDecode(jsonEncode(current)) as Map<String, dynamic>;
  final bracket = updated['kyushu'] as Map<String, dynamic>;
  final matches = (bracket['matches'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> gameAt(int round, int slot) =>
      matches.singleWhere((m) => m['round'] == round && m['slot'] == slot);
  final byId = {
    for (final row in results) '${row['round']}:${row['slot']}': row
  };
  for (var round = 0; round < 4; round++) {
    for (var slot = 0; slot < (8 >> round); slot++) {
      final game = gameAt(round, slot);
      if (round > 0) {
        for (var side = 0; side < 2; side++) {
          final winner = highSchoolWinner(gameAt(round - 1, slot * 2 + side));
          if (winner != null) {
            final key = side == 0 ? 'home' : 'away';
            if (schoolName(game[key]) != schoolName(winner)) {
              game.remove('score_home');
              game.remove('score_away');
            }
            game[key] = winner;
          }
        }
      }
      final row = byId['$round:$slot'];
      if (row == null) continue;
      final expected = {schoolName(game['home']), schoolName(game['away'])};
      final actual = {schoolName(row['home']), schoolName(row['away'])};
      if (actual.length != 2 || !expected.containsAll(actual)) continue;
      // Scheduled/live scores never decide a winner.
      if (row['score_home'] is int &&
          row['score_away'] is int &&
          highSchoolWinner(row) != null) {
        final sameOrder = schoolName(game['home']) == schoolName(row['home']);
        game['score_home'] = row[sameOrder ? 'score_home' : 'score_away'];
        game['score_away'] = row[sameOrder ? 'score_away' : 'score_home'];
        game['source_url'] = source;
      }
      if (row['date'] != null) {
        game['date'] = row['date'];
        game['time'] = row['time'];
      }
    }
  }
  final calendar = updated['calendar'] as Map<String, dynamic>;
  final tournament = (calendar['tournaments'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((t) => t['id'] == 'autumn-kyushu-2026');
  final calendarMatches =
      (tournament['matches'] as List).cast<Map<String, dynamic>>();
  final prefectures = calendar['school_prefectures'] as Map;
  // Candidate schools must shrink as soon as a school is eliminated, so its
  // supporters no longer see conditional games for that school.
  List<String> candidates(int round, int slot) {
    final game = gameAt(round, slot);
    final winner = highSchoolWinner(game);
    if (winner != null) return [schoolName(winner)];
    if (round == 0) return [schoolName(game['home']), schoolName(game['away'])];
    return [
      ...candidates(round - 1, slot * 2),
      ...candidates(round - 1, slot * 2 + 1)
    ];
  }

  for (var round = 0; round < 4; round++) {
    final scheduled = calendarMatches
        .where((m) => m['round'] == highSchoolRounds[round])
        .toList();
    for (var slot = 0; slot < scheduled.length; slot++) {
      final match = scheduled[slot], game = gameAt(round, slot);
      for (final side in ['home', 'away']) {
        final school = schoolName(game[side]);
        if (!school.contains('勝者')) {
          match[side] = school;
          match['${side}_prefecture'] = prefectures[school] ?? '';
        } else if (round > 0) {
          final remaining =
              candidates(round - 1, slot * 2 + (side == 'home' ? 0 : 1));
          match[side] = '${remaining.join('／')}の勝者';
        }
      }
      final date = '${game['date']}'.split('/');
      match['date'] =
          '2026-${date[0].padLeft(2, '0')}-${date[1].padLeft(2, '0')}';
      match['time'] = game['time'];
      final pending = '${match['home']} ${match['away']}'.contains('勝者');
      if (pending) {
        match['conditional'] = true;
        match['candidate_schools'] = round == 0
            ? []
            : [
                ...candidates(round - 1, slot * 2),
                ...candidates(round - 1, slot * 2 + 1),
              ];
      } else {
        match.remove('candidate_schools');
        match.remove('conditional');
        if ('${match['note']}'.contains('勝ち上がり条件付き')) match.remove('note');
      }
      for (final key in ['score_home', 'score_away']) {
        if (game[key] != null) {
          match[key] = game[key];
        } else {
          match.remove(key);
        }
      }
    }
  }
  final checked = now
      .toUtc()
      .add(const Duration(hours: 9))
      .toIso8601String()
      .substring(0, 10);
  bracket['checked_at'] = calendar['checked_at'] = checked;
  updated['checked_at'] = now.toUtc().toIso8601String();
  return updated;
}

class HighSchoolSchedule {
  static Timer? _timer;
  static bool _busy = false;
  static Map<String, dynamic>? _cached;
  static String get _prefix =>
      Directory('backend/public').existsSync() ? 'backend/' : '';
  static File get _store => File('${_prefix}data/high-school-schedule.json');
  static Map<String, dynamic> snapshot() {
    if (_cached != null) return _cached!;
    if (_store.existsSync()) {
      try {
        return _cached =
            jsonDecode(_store.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {}
    }
    Map<String, dynamic> asset(String name) {
      final local = File('${_prefix}assets/data/$name.json');
      final deployed =
          File('${_prefix}public/assets/backend/assets/data/$name.json');
      return jsonDecode(
              (local.existsSync() ? local : deployed).readAsStringSync())
          as Map<String, dynamic>;
    }

    final calendar = asset('high_school_calendar'),
        bracket = asset('autumn_kyushu_2026');
    final tournament = (calendar['tournaments'] as List)
        .cast<Map>()
        .singleWhere((t) => t['id'] == 'autumn-kyushu-2026');
    for (var round = 0; round < 4; round++) {
      final scheduled = (tournament['matches'] as List)
          .cast<Map>()
          .where((m) => m['round'] == highSchoolRounds[round])
          .toList();
      for (var slot = 0; slot < scheduled.length; slot++) {
        final game = (bracket['matches'] as List)
            .cast<Map>()
            .singleWhere((m) => m['round'] == round && m['slot'] == slot);
        final match = scheduled[slot],
            date = '${scheduled[slot]['date']}'.split('-');
        game['date'] = '${int.parse(date[1])}/${int.parse(date[2])}';
        game['time'] = match['time'];
      }
    }
    return _cached = {'calendar': calendar, 'kyushu': bracket};
  }

  static void start() {
    if (_timer != null) return;
    unawaited(tick());
    _timer =
        Timer.periodic(const Duration(minutes: 30), (_) => unawaited(tick()));
  }

  static Future<void> tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final current = snapshot();
      final tournament = ((current['calendar'] as Map)['tournaments'] as List)
          .cast<Map>()
          .singleWhere((t) => t['id'] == 'autumn-kyushu-2026');
      final today = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 9))
          .toIso8601String()
          .substring(0, 10);
      // Continue after the advertised final date in case rain postpones play.
      if (today.compareTo('${tournament['date_from']}') < 0 ||
          highSchoolWinner(((current['kyushu'] as Map)['matches'] as List)
                  .cast<Map<String, dynamic>>()
                  .last) !=
              null) return;
      final source = '${tournament['source_url']}';
      final response = await http
          .get(Uri.parse(source))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200)
        throw HttpException('Results: ${response.statusCode}');
      final body = utf8.decode(response.bodyBytes);
      if (!(html.parse(body).querySelector('h1')?.text ?? '').contains('九州')) {
        throw const FormatException('Unexpected tournament');
      }
      final next = updateHighSchoolSchedule(
          current, parseHighSchoolResults(body, 2026), source, DateTime.now());
      await _store.parent.create(recursive: true);
      final pending = File('${_store.path}.tmp');
      await pending.writeAsString(jsonEncode(next), flush: true);
      await pending.rename(_store.path);
      _cached = next;
    } catch (error, stack) {
      stderr.writeln('HighSchoolSchedule: $error\n$stack');
    } finally {
      _busy = false;
    }
  }
}
