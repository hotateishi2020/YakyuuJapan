import 'package:test/test.dart';
import '../app/JapaneseMlbStats.dart';
void main() {
  test('ランキング圏外と二刀流を含め、投球回をアウト単位で合算する', () {
    final result = buildJapaneseMlbStats([
      {'id_player':1,'name_player':'二刀流','name_team':'A','int_pitching':2,'double_inning':1.2,'int_appearance':10,'int_batting':8},
      {'id_player':1,'name_player':'二刀流','name_team':'B','int_pitching':3,'double_inning':2.2,'int_appearance':5,'int_batting':4},
      {'id_player':2,'name_player':'ランキング圏外','name_team':'C','int_pitching':1,'double_inning':1.0},
    ], [
      {'id_player':1,'name_player':'二刀流','id_league':3,'flg_japan':true,'flg_pitcher':false,'title':'本塁打','stats':'4'},
      {'id_player':3,'id_league':3,'flg_japan':false,'title':'本塁打','stats':'50'},
      {'id_player':4,'id_league':1,'flg_japan':true,'title':'本塁打','stats':'50'},
    ], 2026);
    final players = (result['players'] as List).cast<Map<String,dynamic>>();
    expect(players, hasLength(3));
    final pitcher = players.firstWhere((p) => p['id_player']==1 && p['pitching']==true);
    expect(pitcher['stats']['投球回'], '4.1');
    expect(pitcher['stats']['登板'], 5);
    final batter = players.firstWhere((p) => p['pitching']==false);
    expect(batter['stats']['本塁打'],'4');
    expect(batter['stats']['打席'],15);
    expect(batter['stats'].containsKey('打率'),false);
    expect(batter['stats'].containsKey('打点'),false);
  });
}
