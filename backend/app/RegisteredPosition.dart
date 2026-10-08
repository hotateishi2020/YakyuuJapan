import 'dart:convert';

import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// 公式名簿の登録ポジション（投手・捕手・内野手・外野手）を m_player.txt_position に入れる。
/// 個人成績の地色はここだけを見る。故障の有無では色を変えない。
class RegisteredPosition {
  static const groups = {'投手', '捕手', '内野手', '外野手', '指名打者'};

  static const _yahooAlias = <String, List<String>>{
    'Rソックス': ['レッドソックス'],
    'Wソックス': ['ホワイトソックス'],
    'Dバックス': ['ダイヤモンドバックス', 'Dバックス'],
  };

  static Future<void> ensureSchema(Connection conn) async {
    final existing = await conn.execute('''
      SELECT 1
      FROM information_schema.columns
      WHERE table_name = 'm_player'
        AND column_name = 'txt_position'
      LIMIT 1
    ''');
    if (existing.isNotEmpty) return;
    await conn.execute("ALTER TABLE m_player ADD COLUMN IF NOT EXISTS txt_position varchar(16) NOT NULL DEFAULT ''");
  }

  static String compact(String raw) => raw.replaceAll(RegExp(r'[\s　]'), '').trim();

  /// NPB 公式の選手一覧。育成のあと支配下を重ね、同じ名前は支配下を残す。
  static List<({String name, String position})> parseNpbRoster(String html) {
    final doc = parse(html);
    final tables = doc.querySelectorAll('table.rosterlisttbl').toList().reversed;
    final rows = <({String name, String position})>[];
    for (final table in tables) {
      var position = '';
      for (final tr in table.querySelectorAll('tr')) {
        final headers = tr.querySelectorAll('th');
        if (headers.length >= 2) {
          final label = compact(headers[1].text);
          position = groups.contains(label) ? label : '';
          continue;
        }
        if (position.isEmpty) continue;
        final cells = tr.querySelectorAll('td');
        if (cells.length < 2) continue;
        final name = compact(cells[1].text);
        if (name.isEmpty) continue;
        rows.add((name: name, position: position));
      }
    }
    return rows;
  }

  /// スポーツナビの MLB 選手一覧。見出しのあとに並ぶ名前をそのポジションにする。
  static List<({String name, String position})> parseYahooMlbRoster(String html) {
    final doc = parse(html);
    final rows = <({String name, String position})>[];
    var position = '';
    for (final el in doc.querySelectorAll('h2.bb-head01__title, p.bb-playerList__name')) {
      if (el.localName == 'h2') {
        final label = compact(el.text);
        position = groups.contains(label) ? label : '';
        continue;
      }
      if (position.isEmpty) continue;
      final name = compact(el.text);
      if (name.isEmpty) continue;
      rows.add((name: name, position: position));
    }
    return rows;
  }

  static Map<String, String> yahooMlbTeamIds(String html) {
    final doc = parse(html);
    final ids = <String, String>{};
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      final match = RegExp(r'/mlb/teams/(2021\d{3})/top$').firstMatch(href);
      if (match == null) continue;
      final name = a.text.trim();
      if (name.isEmpty) continue;
      ids[match.group(1)!] = name;
    }
    return ids;
  }

  static int? matchTeamId(List<Map<String, dynamic>> teams, String yahooName) {
    final needles = _yahooAlias[yahooName] ?? [yahooName];
    for (final team in teams) {
      final blob = '${team['name_short'] ?? ''} ${team['name_full'] ?? ''} ${team['name_shortest'] ?? ''}';
      if (needles.any(blob.contains)) return int.tryParse('${team['id']}');
    }
    return null;
  }

  static Future<int> syncNpb(Connection conn) async {
    await ensureSchema(conn);
    final teams = await conn.execute('''
      SELECT id, COALESCE(url_npb_players, '') AS url
      FROM m_team
      WHERE id_league IN (1, 2)
        AND COALESCE(url_npb_players, '') <> ''
    ''');
    var updated = 0;
    for (final row in teams) {
      final map = row.toColumnMap();
      final teamId = map['id'] as int;
      final url = '${map['url'] ?? ''}'.trim();
      if (url.isEmpty) continue;
      final html = await _get(url);
      if (html == null) continue;
      final positions = <String, String>{};
      for (final player in parseNpbRoster(html)) {
        positions[player.name] = player.position;
      }
      updated += await _write(conn, teamId, positions);
    }
    print('NPB登録ポジション 更新$updated');
    return updated;
  }

  static Future<int> syncMlb(Connection conn) async {
    await ensureSchema(conn);
    await conn.execute("SET statement_timeout = '4000'");
    final indexHtml = await _get('https://baseball.yahoo.co.jp/mlb/teams/');
    if (indexHtml == null) return 0;
    final yahooTeams = yahooMlbTeamIds(indexHtml);
    final dbTeams = (await conn.execute('''
      SELECT id, name_shortest, name_short, name_full
      FROM m_team
      WHERE id_league IN (3, 4)
        AND COALESCE(flg_delete, FALSE) = FALSE
    ''')).map((row) => row.toColumnMap()).toList();

    var updated = 0;
    for (final entry in yahooTeams.entries) {
      final teamId = matchTeamId(dbTeams, entry.value);
      if (teamId == null) {
        print('MLB球団を対応できない: ${entry.value}');
        continue;
      }
      final html = await _get('https://baseball.yahoo.co.jp/mlb/teams/${entry.key}/players');
      if (html == null) continue;
      final positions = <String, String>{};
      for (final player in parseYahooMlbRoster(html)) {
        positions[player.name] = player.position;
      }
      updated += await _write(conn, teamId, positions, lastToken: true);
    }
    print('MLB登録ポジション 更新$updated');
    return updated;
  }

  static String lastToken(String name) {
    final parts = name.split(RegExp(r'[・．.]')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return name;
    return parts.last;
  }

  /// [lastToken] は MLB の「A.チャプマン」と名簿の「アロルディス・チャプマン」を姓で結ぶ。
  /// 同じチームに同じ姓が複数いるときは更新しない。
  static Future<int> _write(
    Connection conn,
    int teamId,
    Map<String, String> positions, {
    bool lastToken = false,
  }) async {
    final players = await conn.execute(
      '''
        SELECT id, regexp_replace(COALESCE(name_full, ''), '[[:space:]　]+', '', 'g') AS name
        FROM m_player
        WHERE id_team = \$1::int
          AND COALESCE(flg_delete, FALSE) = FALSE
      ''',
      parameters: [teamId],
    );
    final byExact = <String, List<int>>{};
    final byLast = <String, Map<String, List<int>>>{};
    for (final row in players) {
      final map = row.toColumnMap();
      final id = map['id'] as int;
      final name = '${map['name'] ?? ''}';
      byExact.putIfAbsent(name, () => []).add(id);
      final token = RegisteredPosition.lastToken(name);
      if (token.length < 2) continue;
      byLast.putIfAbsent(token, () => {}).putIfAbsent(name, () => []).add(id);
    }

    final chosen = <int, String>{};
    for (final entry in positions.entries) {
      final exact = byExact[entry.key];
      if (exact != null && exact.isNotEmpty) {
        for (final id in exact) {
          chosen[id] = entry.value;
        }
        continue;
      }
      if (!lastToken) continue;
      final token = RegisteredPosition.lastToken(entry.key);
      if (token.length < 2) continue;
      final names = byLast[token];
      if (names == null || names.length != 1) continue;
      for (final id in names.values.first) {
        chosen[id] = entry.value;
      }
    }

    var updated = 0;
    for (final entry in chosen.entries) {
      try {
        final result = await conn.execute(
          '''
            UPDATE m_player
            SET txt_position = \$2::varchar,
                updat = NOW()
            WHERE id = \$1::int
              AND txt_position IS DISTINCT FROM \$2::varchar
          ''',
          parameters: [entry.key, entry.value],
        );
        updated += result.affectedRows;
      } catch (e) {
        final text = '$e';
        if (!text.contains('57014') && !text.contains('canceling statement')) rethrow;
      }
    }
    return updated;
  }

  static Future<String?> _get(String url) async {
    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'Koko'}).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        print('登録ポジションHTTP ${res.statusCode} $url');
        return null;
      }
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    } catch (e) {
      print('登録ポジション取得失敗 $url: $e');
      return null;
    }
  }
}
