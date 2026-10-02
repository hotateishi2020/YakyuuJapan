import 'dart:convert';

import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import '../tools/Postgres.dart';
import 'AppSql.dart';
import 'DB/m_stadium.dart';
import 'DB/t_game.dart';
import 'Value.dart';

DateTime? _startOn(String date, String raw) {
  final match = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{2})').firstMatch(raw);
  if (match == null) return null;
  final hour = match.group(1)!.padLeft(2, '0');
  final minute = match.group(2)!;
  return DateTime.tryParse('$date $hour:$minute:00');
}

/// スケジュール見出しから code_game を決める。
/// OP オープン戦 / NM 一般戦 / EX 交流戦 / AS オールスター /
/// CS1 ファースト / CSF ファイナル / JS 日本シリーズ / E イベント戦 / SJ 侍ジャパン
String? codeFromScheduleTitle(String title) {
  final text = title.replaceAll(RegExp(r'\s+'), '');
  if (text.isEmpty) return null;
  if (text.contains('日本シリーズ') || text.contains('日本選手権')) return 'JS';
  if (text.contains('ファイナル')) return 'CSF';
  if (text.contains('ファースト') || text.contains('1st') || text.contains('１ｓｔ')) return 'CS1';
  if (text.contains('交流')) return 'EX';
  if (text.contains('オープン')) return 'OP';
  if (text.contains('オールスター')) return 'AS';
  if (text.contains('侍')) return 'SJ';
  if (text.contains('イベント') || text.contains('練習試合')) return 'E';
  return null;
}

bool isPostseasonHeading(String title) {
  final code = codeFromScheduleTitle(title);
  return code == 'CS1' || code == 'CSF' || code == 'JS';
}

String regularGameCode(String title, int homeLeague, int awayLeague) {
  final fromTitle = codeFromScheduleTitle(title);
  if (fromTitle != null && fromTitle != 'NM') return fromTitle;
  if ((homeLeague == 1 || homeLeague == 2) && (awayLeague == 1 || awayLeague == 2) && homeLeague != awayLeague) {
    return 'EX';
  }
  return 'NM';
}

class _Edge {
  final DateTime today;
  final DateTime finalDate;
  final bool beforeOpen;

  const _Edge({required this.today, required this.finalDate, required this.beforeOpen});
}

class Postseason {
  static DateTime? _lastFullScan;

  static bool _flag(dynamic value) {
    if (value == true) return true;
    final text = '$value'.trim().toLowerCase();
    return text == 'true' || text == 't';
  }

  static Future<_Edge?> _edge(Connection conn) async {
    final rows = await conn.execute(
      AppSql.selectSeasonEdge(),
      parameters: [
        Value.SystemCode.Code.ADMIN,
        Value.SystemCode.Key.DATE_FINAL_GAME,
        Value.SystemCode.Key.DATE_OPEN_GAME,
      ],
    );
    if (rows.isEmpty) return null;
    final map = rows.first.toColumnMap();
    final today = DateTime.tryParse('${map['today']}'.substring(0, 10));
    final finalDate = DateTime.tryParse('${map['date_final']}'.substring(0, 10));
    if (today == null || finalDate == null) return null;
    return _Edge(
      today: today,
      finalDate: finalDate,
      beforeOpen: _flag(map['before_open']),
    );
  }

  /// 最終試合の年の9月15日から、次の開幕より前。この間に CS・日本シリーズを登録する。
  static Future<bool> isRegistrationOpen(Connection conn) async {
    final edge = await _edge(conn);
    if (edge == null || !edge.beforeOpen) return false;
    final start = DateTime(edge.finalDate.year, 9, 15);
    return !edge.today.isBefore(start);
  }

  /// 11月中旬までは日程と勝敗を追い、それ以降は未消化の試合が残るときだけ続ける。
  static Future<bool> shouldKeepUpdating(Connection conn) async {
    if (!await isRegistrationOpen(conn)) return false;
    final edge = await _edge(conn);
    if (edge == null) return false;
    final limit = DateTime(edge.finalDate.year, 11, 20);
    if (!edge.today.isAfter(limit)) return true;
    final rows = await conn.execute('''
      SELECT COUNT(*) AS n
      FROM t_game
      WHERE code_game IN ('CS1', 'CSF', 'JS')
        AND datetime_start::date >= CURRENT_DATE - 1
        AND COALESCE(state, '') NOT IN ('試合終了', '試合中止')
    ''');
    final n = rows.first.toColumnMap()['n'];
    if (n is int) return n > 0;
    return (int.tryParse('$n') ?? 0) > 0;
  }

  static Future<void> sync(Connection conn) async {
    final edge = await _edge(conn);
    if (edge == null) return;
    final year = edge.finalDate.year;
    final start = DateTime(year, 9, 15);
    final end = DateTime(year, 11, 15);
    final fullDue = _lastFullScan == null || DateTime.now().difference(_lastFullScan!) > const Duration(hours: 6);
    final dates = <DateTime>[];
    if (fullDue) {
      for (var day = start; !day.isAfter(end); day = day.add(const Duration(days: 1))) {
        dates.add(day);
      }
      _lastFullScan = DateTime.now();
    } else if (!edge.today.isBefore(start) && !edge.today.isAfter(end)) {
      dates.add(edge.today);
    }
    for (final day in dates) {
      await _syncDate(conn, day, fetchDetail: fullDue);
    }
  }

  static String _ymd(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<void> _syncDate(Connection conn, DateTime day, {required bool fetchDetail}) async {
    final date = _ymd(day);
    final res = await http.get(Uri.parse('https://baseball.yahoo.co.jp/npb/schedule/?date=$date'));
    if (res.statusCode != 200) return;
    final document = parse(utf8.decode(res.bodyBytes, allowMalformed: true));
    final root = document.querySelector('#gm_card');
    if (root == null) return;

    for (final section in root.querySelectorAll('section.bb-score')) {
      final title = section.querySelector('.bb-score__title')?.text.trim() ?? '';
      final code = codeFromScheduleTitle(title);
      if (code == null || (code != 'CS1' && code != 'CSF' && code != 'JS')) continue;
      for (final card in section.querySelectorAll('li.bb-score__item')) {
        final homeName = card.querySelector('.bb-score__homeLogo')?.text.trim() ?? '';
        final awayName = card.querySelector('.bb-score__awayLogo')?.text.trim() ?? '';
        if (homeName.isEmpty || awayName.isEmpty || homeName == '未定' || awayName == '未定') continue;
        final state = card.querySelector('.bb-score__link')?.text.trim() ?? '試合前';
        final venue = card.querySelector('.bb-score__venue')?.text.trim() ?? '';
        final scoreLeft = int.tryParse(card.querySelector('.bb-score__score--left')?.text.trim() ?? '');
        final scoreRight = int.tryParse(card.querySelector('.bb-score__score--right')?.text.trim() ?? '');
        final href = card.querySelector('a')?.attributes['href'] ?? '';
        var start = _startOn(date, '18:00');
        if (fetchDetail && href.isNotEmpty) {
          final detail = await _detail(href, date);
          if (detail != null && detail.start != null) start = detail.start;
        }
        if (start == null) continue;
        await _upsert(
          conn,
          code: code,
          date: date,
          homeName: homeName,
          awayName: awayName,
          state: state,
          venue: venue,
          scoreHome: scoreLeft ?? -1,
          scoreAway: scoreRight ?? -1,
          start: start,
        );
      }
    }
  }

  static Future<({DateTime? start})?> _detail(String href, String date) async {
    final path = href.replaceFirst('index', 'top');
    final url = path.startsWith('http') ? Uri.parse(path) : Uri.parse('https://baseball.yahoo.co.jp$path');
    final res = await http.get(url);
    if (res.statusCode != 200) return null;
    final document = parse(utf8.decode(res.bodyBytes, allowMalformed: true));
    final time = document.querySelector('time')?.text.trim() ?? '';
    return (start: _startOn(date, time));
  }

  static Future<void> _upsert(
    Connection conn, {
    required String code,
    required String date,
    required String homeName,
    required String awayName,
    required String state,
    required String venue,
    required int scoreHome,
    required int scoreAway,
    required DateTime start,
  }) async {
    final homeRows = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [homeName]);
    final awayRows = await Postgres.execute(conn, AppSql.selectTeamsWhereName(), data: [awayName]);
    if (homeRows.isEmpty || awayRows.isEmpty) {
      print('ポストシーズンの球団が見つかりません: $homeName vs $awayName');
      return;
    }
    final homeId = homeRows.first.toColumnMap()['id'] as int;
    final awayId = awayRows.first.toColumnMap()['id'] as int;
    var stadiumId = 0;
    if (venue.isNotEmpty && venue != '未定') {
      final stadiumRows = await Postgres.execute(conn, AppSql.selectStadium(), data: ['%$venue%']);
      if (stadiumRows.isEmpty) {
        final stadium = m_stadium();
        stadium.name_short = venue;
        stadium.id_team = homeId;
        stadiumId = await Postgres.insert(conn, stadium);
      } else {
        stadiumId = stadiumRows.first.toColumnMap()['id'] as int;
      }
    }

    final existing = await Postgres.execute(conn, AppSql.selectGameOnDate(), data: [homeId, awayId, date]);
    if (existing.isEmpty) {
      final game = t_game();
      game.code_game = code;
      game.id_team_home = homeId;
      game.id_team_away = awayId;
      game.id_stadium = stadiumId;
      game.score_home = scoreHome;
      game.score_away = scoreAway;
      game.state = state;
      game.datetime_start = start;
      await Postgres.insert(conn, game);
      print('$code $date $awayName @ $homeName を登録しました。');
      return;
    }
    final id = existing.first.toColumnMap()['id'] as int;
    await conn.execute(
      AppSql.updatePostseasonGame(),
      parameters: [code, state, scoreHome, scoreAway, start, stadiumId, id],
    );
  }
}
