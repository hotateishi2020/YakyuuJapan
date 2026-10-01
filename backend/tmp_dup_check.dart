import 'dart:io';
import 'app/PlayLabel.dart';
import 'tools/Postgres.dart';

void main() async {
  final conn = await Postgres.acquire();
  try {
    final result = await Postgres.execute(conn, '''
      SELECT d.id, d.id_game, p.id_team, p.name_full, d.int_inning, d.flg_bottom,
             d.int_batting_order, d.cnt_out, d.flg_runner_first, d.flg_runner_second,
             d.flg_runner_third, d.code_result, d.int_runs, d.cnt_homerun,
             d.code_state_score, d.flg_goodbye, d.code_direction_batting,
             runner.name_full AS name_runner, runner.id_team AS id_team_runner
      FROM t_game_details d
      JOIN m_player p ON p.id = d.id_batter
      JOIN t_game g ON g.id = d.id_game
      LEFT JOIN m_player runner ON runner.id = d.id_player_enter
        AND d.code_result IN ('STEAL_BASE_SAFE', 'STEAL_BASE_OUT')
      WHERE COALESCE(d.flg_delete, false) = false
        AND g.datetime_start::date = DATE '2026-10-01'
        AND p.name_full IN ('森下翔太', '大山悠輔', '佐藤輝明')
      ORDER BY d.id
    ''');
    final labels = playLabelsByPlayer(Postgres.toJson(result));
    for (final entry in labels.entries) {
      stdout.writeln('${entry.key.split('|').last} => ${entry.value}');
    }
    final mori = labels.entries.firstWhere((e) => e.key.endsWith('森下翔太')).value;
    final oyama = labels.entries.firstWhere((e) => e.key.endsWith('大山悠輔')).value;
    final sato = labels.entries.firstWhere((e) => e.key.endsWith('佐藤輝明')).value;
    final walks = '四球'.allMatches(mori).length;
    final hits = RegExp(r'安\|').allMatches(mori).length;
    if (walks != 3 || hits != 1 || 'ホームラン'.allMatches(oyama).length != 1 || '左2'.allMatches(sato).length != 1) {
      stderr.writeln('mori walks=$walks hits=$hits');
      exit(1);
    }
  } finally {
    await Postgres.release(conn);
  }
  stdout.writeln('ok');
  exit(0);
}
