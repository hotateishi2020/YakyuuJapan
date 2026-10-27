import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import '../app/GameBroadcasts.dart';
import '../../lib/logic/career_regions.dart';
void main() {
  test('47 prefectures and Saga/Nagano area codes', () {
    final p = japanRegions.values.expand((v)=>v).toList();
    expect(p.toSet(), hasLength(47));
    expect(p.indexOf('佐賀県')+1, 41); expect(p.indexOf('長野県')+1, 20);
  });
  test('official schedule isolates date and opponent, landing pages are not streams', () {
    final body = File('test/fixtures/hawks_broadcast_202610.html').readAsStringSync();
    final rows = parseClubBroadcasts(body, 'https://www.softbankhawks.co.jp/news/broadcast/202610/', DateTime(2026,10,27), 'DeNA');
    expect(rows, isNotEmpty);
    expect(rows.any((r)=>r['name']=='TVer'), isTrue);
    expect(rows.where((r)=>r['name']=='TVer').single['stream_url'], isNull);
    expect(parseClubBroadcasts(body,'',DateTime(2026,10,27),'阪神'), isEmpty);
  });
  test('region filtering does not infer affiliation or radio reach', () {
    final rows = <Map<String,dynamic>>[
      {'name':'TVer','kind':'stream'}, {'name':'サガテレビ','kind':'tv'},
      {'name':'信越放送','kind':'tv'}, {'name':'RKBラジオ','kind':'radio'},
      {'name':'TBSテレビ','kind':'tv'},
    ];
    expect(filterGameBroadcasts(rows,'長野県').map((r)=>r['name']), ['TVer','信越放送']);
    expect(filterGameBroadcasts(rows,'佐賀県',radioStations:[{'name':'RKBラジオ','logo_url':'https://example.com/logo.png'}]).map((r)=>r['name']), ['TVer','サガテレビ','RKBラジオ']);
    expect(filterGameBroadcasts(rows,'').map((r)=>r['name']), ['TVer']);
  });
  test('日本シリーズのRKB地上波を佐賀で表示しラジオと区別する', () {
    final data = jsonDecode(File('data/game-broadcasts.json').readAsStringSync()) as List;
    for (final day in [24,25,27]) {
      final entry = data.firstWhere((e) => e['date'] == '2026-10-$day');
      final rows = (entry['broadcasts'] as List).map((r) => Map<String,dynamic>.from(r)).toList();
      expect(filterGameBroadcasts(rows,'佐賀県').any((r) => r['kind']=='tv' && r['name']=='RKB毎日放送'), isTrue);
      expect(filterGameBroadcasts(rows,'長野県').any((r) => r['name']=='RKB毎日放送'), isFalse);
    }
    expect(filterGameBroadcasts([{'kind':'tv','name':'RKB毎日放送'}],'佐賀県'), hasLength(1));
  });
  test('10月27日のSBC地上波は長野に表示し他県には表示しない', () {
    final data=jsonDecode(File('data/game-broadcasts.json').readAsStringSync()) as List;
    final entry=data.firstWhere((e)=>e['date']=='2026-10-27');
    final rows=(entry['broadcasts'] as List).map((r)=>Map<String,dynamic>.from(r)).toList();
    final nagano=filterGameBroadcasts(rows,'長野県');
    expect(nagano.where((r)=>r['kind']=='tv'&&r['name']=='SBC信越放送'),hasLength(1));
    for(final area in ['佐賀県','東京都','']) {
      expect(filterGameBroadcasts(rows,area).any((r)=>r['name']=='SBC信越放送'),isFalse);
    }
    expect(nagano.firstWhere((r)=>r['name']=='SBC信越放送')['stream_url'],isNull);
  });
  test('exact event URL only', () {
    expect(isGameStreamUrl('https://tver.jp/'), isFalse);
    expect(isGameStreamUrl('https://tver.jp/live/special/lepw20my0j'), isTrue);
    expect(isGameStreamUrl('javascript:alert(1)'), isFalse);
  });
}
