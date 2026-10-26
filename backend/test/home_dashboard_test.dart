import 'package:test/test.dart';
import '../app/HomeDashboard.dart';
void main() {
  test('首位タイを残し六冠以外や二位を除外する', () {
    expect(homeLeaders([
      for (final id in [1,2]) {'title': '本塁打', 'int_rank': 1, 'id_player': id, 'id_league': 1},
      {'title': '本塁打', 'int_rank': 2}, {'title': 'OPS', 'int_rank': 1},
    ]), hasLength(2));
  });
  test('終了試合の勝者だけから投打を比較し一人選ぶ', () {
    final game = {'id_game': 1, 'state': '試合終了', 'score_home': 3, 'score_away': 1, 'id_team_home': 10, 'id_team_away': 11};
    final lines = [
      {'id_game': 1, 'id_team': 11, 'id_player': 1, 'int_homerun': 10},
      {'id_game': 1, 'id_team': 10, 'id_player': 2, 'int_batting': 4, 'int_hit1': 2, 'int_homerun': 1, 'int_rbi': 3},
      {'id_game': 1, 'id_team': 10, 'id_player': 3, 'double_inning_pitch': 7.2, 'int_strike_out': 8, 'int_runs': 1, 'int_runs_earned': 1},
    ];
    expect(homeHero(game, lines)?['id_player'], 3);
    expect(homeHero(game, lines)?['appearance_stats'], ['7 2/3回 1失点（自責点1） 8奪三振']);
    final batter = homeHero(game, lines.take(2))!;
    expect(batter['appearance_stats'], ['4打数2安打 3打点']);
    expect(batter['highlights'], ['1本塁打', '3打点', 'マルチ安打']);
    expect(homeHero({...game, 'state': '5回表'}, lines), isNull);
    expect(homeHero({...game, 'score_home': 1}, lines), isNull);
    expect(homeHero(game, []), isNull);
  });
}
