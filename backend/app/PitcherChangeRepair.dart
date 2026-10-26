import 'package:postgres/postgres.dart';
import '../tools/Postgres.dart';
import 'DB/t_game_details.dart';
import 'LiveText.dart';

/// 速報に存在する継投だけを、既存打席の状況と照合して補完する。
Future<int> repairPitcherChanges(Connection conn, {
  required int gameId, required int homeTeam, required int awayTeam,
  required ParsedLiveText parsed,
  required int Function(String name, int team) playerId,
}) async {
  final rows = Postgres.toJson(await conn.execute(
    'SELECT * FROM t_game_details WHERE id_game = \$1 AND COALESCE(flg_delete, false) = false',
    parameters: [gameId],
  ));
  int number(dynamic value) => int.tryParse('$value') ?? 0;
  final pitchers = Postgres.toJson(await conn.execute(
    'SELECT DISTINCT p.id, p.id_team, p.name_full, p.name_last FROM t_game_summary s JOIN m_player p ON p.id=s.id_player WHERE s.id_game=\$1 AND s.double_inning_pitch > 0 AND COALESCE(s.flg_delete, false)=false',
    parameters: [gameId],
  ));
  String compact(dynamic name) => '$name'.replaceAll(RegExp(r'[\s　]+'), '');
  int pitcherId(String name, int team) {
    final resolved = playerId(name, team);
    if (resolved != 0) return resolved;
    final query = compact(name);
    if (query.isEmpty) return 0;
    // 「松本裕」「鈴木豪」などは、この試合で登板した同チームの選手に限って照合。
    final matches = pitchers.where((p) {
      final full = compact(p['name_full']), last = compact(p['name_last']);
      return number(p['id_team']) == team && last.isNotEmpty &&
        (query == full || query == last || (query.startsWith(last) && full.startsWith(query)));
    }).toList();
    return matches.length == 1 ? number(matches.single['id']) : 0;
  }
  var added = 0;
  for (final half in parsed.halves) {
    for (final plate in half.plates) {
      for (final event in plate.events.where((e) => e.pitcherChange)) {
        final entered = pitcherId(event.enterName, half.bottom ? awayTeam : homeTeam);
        final batter = playerId(plate.batterName, half.bottom ? homeTeam : awayTeam);
        if (entered == 0 || batter == 0) continue;
        final situation = rows.where((r) => number(r['int_inning']) == half.inning &&
          r['flg_bottom'] == half.bottom && number(r['id_batter']) == batter).toList();
        if (situation.any((r) => r['code_result'] == 'CHANGE_PITCHER')) continue;
        var batting = situation.where((r) => livePlateFinishedResults.contains(r['code_result'])).toList();
        if (batting.length > 1) batting = batting.where((r) => number(r['cnt_out']) == plate.outs).toList();
        if (batting.length != 1) continue;
        final source = batting.single;
        final detail = t_game_details()
          ..id_game = gameId ..int_inning = half.inning ..flg_bottom = half.bottom
          ..id_batter = batter ..int_batting_order = number(source['int_batting_order'])
          ..cnt_out = plate.outs ..flg_runner_first = plate.runnerFirst
          ..flg_runner_second = plate.runnerSecond ..flg_runner_third = plate.runnerThird
          ..int_score_home = number(source['int_score_home'])
          ..int_score_away = number(source['int_score_away'])
          ..code_category = event.category ..code_result = event.result
          ..id_player_enter = entered
          ..id_player_exit = pitcherId(event.exitName, half.bottom ? awayTeam : homeTeam);
        await Postgres.insertMulti(conn, [detail]);
        rows.add({'int_inning': half.inning, 'flg_bottom': half.bottom,
          'id_batter': batter, 'cnt_out': plate.outs, 'code_result': 'CHANGE_PITCHER'});
        added++;
      }
    }
  }
  return added;
}
