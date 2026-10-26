import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/today_event_map.dart';
import 'package:Yakyuu_Japan/logic/game_visibility.dart';
void main() {
  final venues = [{'name':'東京ドーム','latitude':35.7,'longitude':139.75},
    {'name':'キャンプ球場','latitude':31.8,'longitude':131.4}];
  test('league and postseason headers are selected from game metadata', () {
    for (final entry in {'CS1':'CS 1st STAGE','CSF':'CS FINAL STAGE',
      'JS':'日本シリーズ','WS':'ワールドシリーズ','ALCS':'ALCS','NLCS':'NLCS'}.entries) {
      expect(todayMapGameHeader({'code_game':entry.key,'id_league_home':1,'id_league_away':1}),entry.value);
    }
    expect(todayMapGameHeader({'id_league_home':1,'id_league_away':1}),'セ・リーグ');
    expect(todayMapGameHeader({'id_league_home':2,'id_league_away':2}),'パ・リーグ');
    expect(todayMapGameHeader({'code_game':'LCS','id_league_home':3,'id_league_away':3}),'ALCS');
    expect(todayMapGameHeader({'id_league_home':1,'id_league_away':2}),'交流戦');
  });
  test('public API preserves stadium coordinates but removes live scores', () {
    final response = publicGameData({'date':'2026-10-27','games':[
      {'id_game':3386,'date_game':'2026-10-27','state':'1回表',
        'name_team_home':'ソフトバンク','name_team_away':'DeNA',
        'name_stadium':'みずほPayPay','latitude':33.594341,'longitude':130.362411,
        'score_home':1,'score_away':0}
    ]}) as Map<String,dynamic>;
    final entries = todayMapEntries(response);
    expect(entries.single['located'],isTrue);
    expect(entries.single['latitude'],33.594341);
    expect((response['games'] as List).single['score_home'],-1);
  });
  test('today games and period events, excludes cancellation and ticket sales', () {
    final rows = todayMapEntries({'date':'2026-10-27','venues':venues,
      'games':[
        {'date_game':'2026-10-27','name_team_home':'巨人','name_team_away':'阪神','name_stadium':'東京ドーム'},
        {'date_game':'2026-10-26','name_team_home':'巨人','name_team_away':'阪神','name_stadium':'東京ドーム'},
        {'date_game':'2026-10-27','state':'中止','name_stadium':'東京ドーム'},
      ],
      'events':[
        {'title_event':'秋季キャンプ','date_from_temp':'2026-10-25','date_to':'2026-11-01','venue':'キャンプ球場'},
        {'title_event':'トークショー','date_from_temp':'2026-10-27','venue':'未発表'},
        {'title_event':'トークショー受付','calendar_kind':'ticket','date_from_temp':'2026-10-27'},
        {'title_event':'式典（中止）','date_from_temp':'2026-10-27'},
      ]});
    expect(rows,hasLength(3));
    expect(rows.where((r)=>r['located']==true),hasLength(2));
    expect(rows.last['located'],isFalse);
  });
  test('all requested event categories and exact coordinates', () {
    final rows=todayMapEntries({'date':'2026-10-27','events':[
      for(final title in ['イベントマッチ','トークショー','秋季キャンプ','自主トレ','表彰式典','メジャーリーガー来日'])
        {'title_event':title,'date_from_temp':'2026-10-27','venue':'公開会場','latitude':35,'longitude':139}
    ]});
    expect(rows,hasLength(6)); expect(rows.every((r)=>r['located']==true),isTrue);
  });
  test('ambiguous venue and invalid coordinates are not placed', () {
    final rows=todayMapEntries({'date':'2026-10-27','venues':[
      {'name':'中央野球場A','latitude':35,'longitude':139},
      {'name':'中央野球場B','latitude':36,'longitude':140}],
      'events':[
        {'title_event':'自主トレ','date_from_temp':'2026-10-27','venue':'中央野球場'},
        {'title_event':'式典','date_from_temp':'2026-10-27','latitude':999,'longitude':139}
      ]});
    expect(rows.every((r)=>r['located']==false),isTrue);
  });
  test('legacy research snapshots retain venue from structured detail', () {
    final rows=todayMapEntries({'date':'2026-10-27','venues':venues,'events':[
      {'title_event':'トークショー','date_from_temp':'2026-10-27',
        'detail':'2026-10-27 〜 2026-10-27\n\n東京ドーム\nhttps://example.com/event'}]});
    expect(rows.single['located'],isTrue);
  });
}
