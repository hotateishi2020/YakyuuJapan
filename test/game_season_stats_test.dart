import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/game_season_stats.dart';

void main() {
  final rows = [
    {'title': '打率', 'stats': '0.312'},
    {'title': '本塁打', 'stats': '30'},
    {'title': '防御率', 'stats': '1.9'},
    {'title': '最多勝', 'stats': '12'},
    {'title': 'ホールド', 'stats': '21'},
    {'title': 'HP', 'stats': '25'},
    {'title': 'セーブ', 'stats': '35'},
  ];
  test('野手は打率3桁と本塁打数', () {
    expect(gameSeasonStats(rows, pitching: false), '.312 30本');
  });
  test('投手は防御率2桁と役割別の勝・H・S', () {
    expect(gameSeasonStats(rows, pitching: true, role: '先'), '1.90 12勝');
    expect(gameSeasonStats(rows, pitching: true, role: '中'), '1.90 21H');
    expect(gameSeasonStats(rows, pitching: true, role: '抑'), '1.90 35S');
  });
  test('未取得とゼロを区別しHPをHとして表示しない', () {
    expect(gameSeasonStats([{'title': 'HP', 'stats': 20}], pitching: true, role: '中'), '— —H');
    expect(gameSeasonStats([{'title': '打率', 'stats': 0}, {'title': '本塁打', 'stats': 0}], pitching: false), '.000 0本');
  });
}
