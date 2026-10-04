import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:postgres/postgres.dart';
import '../tools/DateTimeTool.dart';
import 'FetchURL.dart';
import 'OrgLeague.dart';

/// エースポイント算出と m_player.flg_ace の更新。
/// Ace Point = 0.35I + 0.35E + 0.15K + 0.10L + 0.05W
/// （各指標は同一リーグ・同一年の先発内で 0–100 相対評価）
class AceEvaluator {
  static const double aceThreshold = 75.0;

  /// 指定リーグについてエース判定を行い flg_ace を更新する。
  static Future<int> refresh(Connection conn, List<int> leagueIds) async {
    final year = DateTimeTool.getThisYear();
    final leagueIn = leagueIds.join(',');
    print('エース判定開始 leagues=$leagueIds year=$year');
    await _ensureCareerFromEraPages(conn, leagueIds, year);

    final candidates = await _loadStarters(conn, leagueIds, year);
    print('エース判定: 先発候補 ${candidates.length}人');
    if (candidates.isEmpty) {
      print('エース判定: 先発候補なし leagues=$leagueIds year=$year');
      return 0;
    }

    final byLeague = <int, List<_AcePitcher>>{};
    for (final p in candidates) {
      byLeague.putIfAbsent(p.leagueId, () => []).add(p);
    }

    final aceIds = <int>{};
    for (final entry in byLeague.entries) {
      final pool = entry.value;
      _assignRelativeScores(pool);
      for (final p in pool) {
        p.acePoint = 0.35 * p.scoreIp +
            0.35 * p.scoreEra +
            0.15 * p.scoreK9 +
            0.10 * p.scoreIpPerApp +
            0.05 * p.scoreWins;
      }

      final byTeam = <int, List<_AcePitcher>>{};
      for (final p in pool) {
        byTeam.putIfAbsent(p.teamId, () => []).add(p);
      }
      for (final teamPitchers in byTeam.values) {
        teamPitchers.sort((a, b) => b.acePoint.compareTo(a.acePoint));
        final top = teamPitchers.first;
        if (top.acePoint + 1e-9 >= aceThreshold) {
          aceIds.add(top.playerId);
        }
      }

      pool.sort((a, b) => b.acePoint.compareTo(a.acePoint));
      for (final p in pool.take(5)) {
        print(
          'エース候補 L${entry.key}: ${p.name} team=${p.teamId} '
          'pt=${p.acePoint.toStringAsFixed(1)} '
          'IP=${p.ip} ERA=${p.era} K9=${p.k9.toStringAsFixed(2)} '
          'IP/G=${p.ipPerApp.toStringAsFixed(2)} W=${p.wins}',
        );
      }
    }

    final cleared = await conn.execute(
      '''
        UPDATE m_player AS p
        SET flg_ace = FALSE,
            updat = NOW()
        FROM m_team AS t
        WHERE t.id = p.id_team
          AND t.id_league IN ($leagueIn)
          AND COALESCE(p.flg_ace, FALSE) IS DISTINCT FROM FALSE
      ''',
    );

    var setCount = 0;
    if (aceIds.isNotEmpty) {
      final idList = aceIds.join(',');
      final set = await conn.execute(
        '''
          UPDATE m_player
          SET flg_ace = TRUE,
              updat = NOW()
          WHERE id IN ($idList)
        ''',
      );
      setCount = set.affectedRows;
    }

    print(
      'エース判定完了 leagues=$leagueIds year=$year '
      'candidates=${candidates.length} aces=$setCount '
      'cleared=${cleared.affectedRows}',
    );
    return setCount;
  }

  static Future<void> refreshAll(Connection conn) async {
    await refresh(conn, OrgKind.npb.leagueIds);
    await refresh(conn, OrgKind.mlb.leagueIds);
  }

  /// MLB など career が薄いリーグは防御率ランキングから投球成績を補完する。
  static Future<void> _ensureCareerFromEraPages(
    Connection conn,
    List<int> leagueIds,
    int year,
  ) async {
    for (final leagueId in leagueIds) {
      final count = await conn.execute(
        '''
          SELECT COUNT(*)::int AS n
          FROM m_player_career c
          JOIN m_team t ON t.id = c.id_team
          WHERE c.int_year = \$1
            AND t.id_league = \$2
            AND COALESCE(c.flg_delete, FALSE) = FALSE
            AND COALESCE(c.double_inning, 0) >= 40
            AND COALESCE(c.double_average_earned_runs, 0) > 0
        ''',
        parameters: [year, leagueId],
      );
      final nRaw = count.first.toColumnMap()['n'];
      final n = nRaw is int ? nRaw : int.tryParse('$nRaw') ?? 0;
      if (n >= 8) continue;
      print('エース判定: career不足のため防御率表を同期 league=$leagueId n=$n');
      await _syncEraPage(conn, leagueId);
    }
  }

  static Future<void> _syncEraPage(Connection conn, int leagueId) async {
    final urls = await conn.execute(
      '''
        SELECT d.url
        FROM m_stats_details d
        JOIN m_stats s ON s.id = d.id_stats
        WHERE d.id_league = \$1
          AND s.title = '防御率'
        LIMIT 1
      ''',
      parameters: [leagueId],
    );
    if (urls.isEmpty) return;
    var url = '${urls.first.toColumnMap()['url'] ?? ''}'.trim();
    if (url.isEmpty) return;
    if (leagueId == 3 || leagueId == 4) {
      url = url.replaceAll('/npb/stats/', '/mlb/stats/');
      url = url.replaceAllMapped(RegExp(r'gameKindId=(\d+)'), (match) {
        final id = match.group(1)!;
        if (id == '1') return 'gameKindId=1001';
        if (id == '2') return 'gameKindId=1002';
        return match.group(0)!;
      });
    }

    http.Response res;
    try {
      res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
    } catch (e) {
      print('エース同期URL失敗 league=$leagueId: $e');
      return;
    }
    if (res.statusCode != 200) {
      print('エース同期HTTP ${res.statusCode} league=$leagueId');
      return;
    }

    final doc = parse(FetchURL.decodeHtmlResponse(res));
    final table = doc.querySelector('#js-playerTable');
    if (table == null) return;

    var upserted = 0;
    for (final tr in table.querySelectorAll('tr')) {
      final tds = tr.querySelectorAll('td');
      if (tds.length < 19) continue;
      final cols = tds.map((td) => td.text.trim()).toList();
      final parsed = FetchURL.parseYahooRankingPlayerCell(cols[1]);
      if (parsed.player.isEmpty || parsed.team.isEmpty) continue;

      final appearances = int.tryParse(cols[3].replaceAll(RegExp(r'\s'), '')) ?? 0;
      final starts = int.tryParse(cols[4].replaceAll(RegExp(r'\s'), '')) ?? 0;
      final wins = int.tryParse(cols[8].replaceAll(RegExp(r'\s'), '')) ?? 0;
      final innings = double.tryParse(cols[14].replaceAll(RegExp(r'\s'), '')) ?? 0;
      final strikeouts = int.tryParse(cols[17].replaceAll(RegExp(r'\s'), '')) ?? 0;
      final era = double.tryParse(cols[2].replaceAll(RegExp(r'\s'), '')) ?? 0;
      if (innings <= 0 && appearances <= 0) continue;

      final ok = await FetchURL.upsertPitcherSeasonLine(
        conn,
        playerName: parsed.player,
        teamToken: parsed.team,
        appearances: appearances,
        starts: starts,
        innings: innings,
        wins: wins,
        strikeouts: strikeouts,
        era: era,
      );
      if (ok) upserted++;
    }
    print('エース同期: league=$leagueId upserted=$upserted');
  }

  static Future<List<_AcePitcher>> _loadStarters(
    Connection conn,
    List<int> leagueIds,
    int year,
  ) async {
    final leagueIn = leagueIds.join(',');
    final rows = await conn.execute(
      '''
        SELECT
          p.id AS id_player,
          p.name_full,
          COALESCE(c.id_team, p.id_team) AS id_team,
          t.id_league,
          COALESCE(c.int_pitching, 0) AS appearances,
          COALESCE(c.double_inning, 0) AS innings,
          COALESCE(c.int_win, 0) AS wins,
          COALESCE(c.int_strike_out_pitcher, 0) AS strikeouts,
          COALESCE(c.double_average_earned_runs, 0) AS era,
          COALESCE(tg.int_game, 0) AS team_games
        FROM m_player_career c
        JOIN m_player p ON p.id = c.id_player
        JOIN m_team t ON t.id = COALESCE(c.id_team, p.id_team)
        LEFT JOIN LATERAL (
          SELECT st.int_game
          FROM t_stats_team st
          WHERE st.id_team = COALESCE(c.id_team, p.id_team)
          ORDER BY st.crtat DESC NULLS LAST
          LIMIT 1
        ) tg ON TRUE
        WHERE c.int_year = \$1
          AND COALESCE(c.flg_delete, FALSE) = FALSE
          AND t.id_league IN ($leagueIn)
          AND COALESCE(c.double_inning, 0) > 0
          AND COALESCE(c.int_pitching, 0) > 0
      ''',
      parameters: [year],
    );

    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    double asDouble(dynamic v) {
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }

    final out = <_AcePitcher>[];
    for (final row in rows) {
      final m = row.toColumnMap();
      final appearances = asInt(m['appearances']);
      final rawIp = asDouble(m['innings']);
      final ip = FetchURL.baseballInnings('$rawIp');
      if (appearances <= 0 || ip <= 0) continue;
      final era = asDouble(m['era']);
      // 防御率未取得の行は相対評価を歪めるので除外
      if (era <= 0) continue;
      final ipPerApp = ip / appearances;
      final teamGames = asInt(m['team_games']);
      // 先発: 登板あたり投球回 >= 4 かつ 投球回 >= チーム試合数 * 0.5
      if (ipPerApp < 4) continue;
      if (teamGames > 0 && ip < teamGames * 0.5) continue;

      final so = asInt(m['strikeouts']);
      out.add(
        _AcePitcher(
          playerId: asInt(m['id_player']),
          name: '${m['name_full'] ?? ''}',
          teamId: asInt(m['id_team']),
          leagueId: asInt(m['id_league']),
          ip: rawIp,
          ipDecimal: ip,
          appearances: appearances,
          wins: asInt(m['wins']),
          era: era,
          k9: so * 9 / ip,
          ipPerApp: ipPerApp,
        ),
      );
    }
    return out;
  }

  /// 昇順ランク（最小=1）。得点 = 100*(rank-1)/(n-1)。ERA のみ反転。
  static void _assignRelativeScores(List<_AcePitcher> pool) {
    if (pool.isEmpty) return;
    if (pool.length == 1) {
      final only = pool.first;
      only.scoreIp = 100;
      only.scoreEra = 100;
      only.scoreK9 = 100;
      only.scoreIpPerApp = 100;
      only.scoreWins = 100;
      return;
    }

    void apply(List<double> values, void Function(_AcePitcher, double) setScore, {required bool invert}) {
      final ranks = _averageRanksAscending(values);
      final denom = pool.length - 1;
      for (var i = 0; i < pool.length; i++) {
        var score = 100.0 * (ranks[i] - 1) / denom;
        if (invert) score = 100.0 - score;
        setScore(pool[i], score);
      }
    }

    apply([for (final p in pool) p.ipDecimal], (p, s) => p.scoreIp = s, invert: false);
    apply([for (final p in pool) p.era], (p, s) => p.scoreEra = s, invert: true);
    apply([for (final p in pool) p.k9], (p, s) => p.scoreK9 = s, invert: false);
    apply([for (final p in pool) p.ipPerApp], (p, s) => p.scoreIpPerApp = s, invert: false);
    apply([for (final p in pool) p.wins.toDouble()], (p, s) => p.scoreWins = s, invert: false);
  }

  /// 昇順。同値は平均順位。
  static List<double> _averageRanksAscending(List<double> values) {
    final indexed = [for (var i = 0; i < values.length; i++) (i: i, v: values[i])];
    indexed.sort((a, b) {
      final c = a.v.compareTo(b.v);
      return c != 0 ? c : a.i.compareTo(b.i);
    });
    final ranks = List<double>.filled(values.length, 0);
    var i = 0;
    while (i < indexed.length) {
      var j = i + 1;
      while (j < indexed.length && indexed[j].v == indexed[i].v) {
        j++;
      }
      // 順位は 1-based。区間 [i, j) の平均順位 = ((i+1)+(j))/2
      final avg = ((i + 1) + j) / 2.0;
      for (var k = i; k < j; k++) {
        ranks[indexed[k].i] = avg;
      }
      i = j;
    }
    return ranks;
  }
}

class _AcePitcher {
  final int playerId;
  final String name;
  final int teamId;
  final int leagueId;
  final double ip;
  final double ipDecimal;
  final int appearances;
  final int wins;
  final double era;
  final double k9;
  final double ipPerApp;

  double scoreIp = 0;
  double scoreEra = 0;
  double scoreK9 = 0;
  double scoreIpPerApp = 0;
  double scoreWins = 0;
  double acePoint = 0;

  _AcePitcher({
    required this.playerId,
    required this.name,
    required this.teamId,
    required this.leagueId,
    required this.ip,
    required this.ipDecimal,
    required this.appearances,
    required this.wins,
    required this.era,
    required this.k9,
    required this.ipPerApp,
  });
}
