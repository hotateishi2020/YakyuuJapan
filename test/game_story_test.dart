import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/game_story.dart';

void main() {
  final game = <String,dynamic>{'id_game':4,'date_game':'2026-10-27','id_team_home':1,'id_team_away':2,
    'name_team_home':'ホーム','name_team_away':'ビジター','code_game':'JS','state':'試合前'};
  final wins = [for (var i=1;i<=3;i++) {...game,'id_game':i,'date_game':'2026-10-${20+i}',
    'state':'試合終了','score_home':2,'score_away':1}];
  test('王手と決定を区別し将来の結果を使わない', () {
    final future = {...game,'id_game':5,'date_game':'2026-10-28','state':'試合終了','score_home':2,'score_away':1};
    expect(gameStory(game,seriesGames:[...wins,future]), contains('優勝阻止'));
    expect(gameStory(game,seriesGames:[...wins,future]), isNot(contains('決定')));
    expect(gameStory({...game,'state':'試合終了','score_home':2,'score_away':1},seriesGames:wins), contains('日本一決定'));
  });
  test('確定したエースと試合前の連勝を使用', () {
    final text=gameStory({...game,'code_game':'R','story_streak_home':3,'flg_ace_pitcher_home':true,'name_pitcher_home':'山田 太郎'});
    expect(text,contains('4連勝なるか？'));
    expect(text,contains('エースの山田'));
  });
  test('ポストシーズンは連敗より王手・優勝阻止を優先して一文にする', () {
    final target = {...game, 'flg_ace_pitcher_away':true,
      'name_pitcher_away':'東 克樹', 'story_streak_away':-3};
    final before = gameStory(target, seriesGames:wins.take(2).toList());
    expect(before, 'ホーム3連勝で王手か、ビジターはエースの東で王手阻止なるか？');
    expect(gameStory(target, seriesGames:wins), 'ホーム4連勝で日本一か、ビジターはエースの東で優勝阻止なるか？');
    expect(before, isNot(contains('\n')));
    expect(before, isNot(contains('連敗')));
  });
  test('ホークスの王手と相手の阻止の両視点を表示する', () {
    final target = {...game, 'name_team_home':'ソフトバンク', 'name_team_away':'DeNA',
      'story_streak_home':2, 'flg_ace_pitcher_away':true, 'name_pitcher_away':'東 克樹'};
    expect(gameStory(target,seriesGames:wins.take(2).toList()),
      'ホークス3連勝で王手か、DeNAはエースの東で王手阻止なるか？');
    expect(gameStory({...target,'story_streak_home':0},seriesGames:wins.take(2).toList()),
      isNot(contains('3連勝')));
  });
  test('中止とデータなしに架空の見どころを作らない', () {
    expect(gameStory({...game,'state':'中止'}),isEmpty);
    expect(gameStory({}),isEmpty);
    expect(gameStory(game),isNot(contains('本拠地')));
  });
}
