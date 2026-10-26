import 'package:test/test.dart';
import '../app/GameHighlightVideos.dart';

void main() {
  final game = <String, dynamic>{'date_game':'2026-10-25','state':'試合終了',
    'id_league_home':1,'name_team_home':'DeNA','name_team_away':'ソフトバンク'};
  Map<String,dynamic> video(String id, String title) => {'id':id, 'title':title,
    'published_at':'2026-10-25T14:00:00Z'};
  test('date and both clubs required, duplicates removed', () {
    final matching = video('abcdefghijk', '2026/10/25 DeNA vs ソフトバンク ハイライト');
    final channels = [{'videos':[matching,
      video('abcdefghij2','2026/10/24 DeNA vs ソフトバンク ハイライト'),
      video('abcdefghij3','2025/10/25 DeNA vs ソフトバンク ハイライト'),
      video('abcdefghij4','2026/10/25 DeNA vs 阪神 ハイライト'),
      video('abcdefghij5','DeNA vs ソフトバンク ハイライト'),
    ]}, {'videos':[matching]}];
    expect(gameHighlightVideos(game, channels).map((v)=>v['id']), ['abcdefghijk']);
    expect(gameHighlightVideos({...game,'state':'試合前'}, channels), isEmpty);
  });
  test('month/day requires a nearby publication date', () {
    final v = video('abcdefghijk','10月25日 DeNA ソフトバンク ハイライト');
    expect(gameHighlightVideos(game,[{'videos':[v]}]), hasLength(1));
    expect(gameHighlightVideos(game,[{'videos':[{...v,'published_at':null}]}]), isEmpty);
  });
  test('MLB local game date and English team names', () {
    final mlb = {...game,'id_league_home':3,'name_team_home':'ドジャース','name_team_away':'ヤンキース'};
    expect(gameHighlightVideos(mlb,[{'videos':[
      video('abcdefghijk','Dodgers vs. Yankees Game Highlights (10/24/26)')
    ]}]), hasLength(1));
  });
}
