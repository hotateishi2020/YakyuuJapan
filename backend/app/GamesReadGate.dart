import 'package:postgres/postgres.dart';

/// 画面の試合読み込み。該当する t_game の更新日時が前回と同じなら、集計SQLは出さない。
class GamesReadGate {
  static String token(Object? updat, Object? count) {
    final when = updat is DateTime ? updat.toUtc().toIso8601String() : '${updat ?? ''}';
    final n = count is int
        ? count
        : count is BigInt
            ? count.toInt()
            : int.tryParse('${count ?? ''}') ?? 0;
    return '$when|$n';
  }

  static bool reuse({
    required String? cachedBody,
    required String? previousRevision,
    required String revision,
  }) {
    if (cachedBody == null || cachedBody.isEmpty) return false;
    if (previousRevision == null || previousRevision.isEmpty) return false;
    return previousRevision == revision;
  }

  /// 表示対象の試合について、最新の t_game.updat と件数を返す。
  static Future<String> revision(
    Connection conn, {
    required List<int> leagueIds,
    required int year,
    String? from,
    String? to,
  }) async {
    final ids = leagueIds.where((id) => id > 0).toSet().toList()..sort();
    if (ids.isEmpty) return token(null, 0);
    final leagueIn = ids.join(', ');
    final ranged = from != null && to != null && from.isNotEmpty && to.isNotEmpty;
    final rows = await conn.execute(
      '''
        SELECT MAX(g.updat) AS updat, COUNT(*) AS n
        FROM t_game g
        WHERE COALESCE(g.flg_delete, FALSE) = FALSE
          AND (
            g.id_team_home IN (SELECT id FROM m_team WHERE id_league IN ($leagueIn))
            OR g.id_team_away IN (SELECT id FROM m_team WHERE id_league IN ($leagueIn))
          )
          AND ${ranged ? 'g.datetime_start::date BETWEEN \$1::date AND \$2::date' : 'EXTRACT(YEAR FROM g.datetime_start) = \$1::int'}
      ''',
      parameters: ranged ? [from, to] : [year],
    );
    if (rows.isEmpty) return token(null, 0);
    return token(rows.first[0], rows.first[1]);
  }
}
