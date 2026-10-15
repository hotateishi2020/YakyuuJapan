import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/contract_fa.dart';
import 'package:Yakyuu_Japan/data/npb_fa_rights.dart';
import 'package:Yakyuu_Japan/View/strength_contracts.dart';

void main() {
  test('公式IDで取得年を照合し、権利保有だけでは年を推測しない', () {
    final actual = npbFaRights.firstWhere((e) => e['player_key'] != null);
    expect(
        contractFaEvents(
            {'player_key': actual['player_key'], 'name': '別表記'}, null,
            isNpb: true),
        contains(equals(actual)));
    expect(
        contractFaEvents(
            {'player_key': 'npb:invalid', 'name': actual['name']}, null,
            isNpb: true),
        isEmpty);
    expect(contractFaEvents({'name': actual['name']}, null, isNpb: false),
        isEmpty);
    expect(
        contractFaEvents({'name': '架空選手', 'fa_confirmed': true}, null,
            isNpb: true),
        isEmpty);
  });
  test('取得済みを見込みより優先し、国内と海外は別イベント', () {
    final events = contractFaEvents({
      'name': '架空選手',
      'fa_events': [
        {
          'year': 2026,
          'type': 'domestic',
          'projected': false,
          'source_url': 'https://npb.jp/'
        },
        {
          'year': 2026,
          'type': 'domestic',
          'projected': true,
          'source_url': 'https://npb.jp/'
        },
        {
          'year': 2027,
          'type': 'international',
          'projected': true,
          'source_url': 'https://npb.jp/'
        },
        {'year': 0, 'type': 'domestic', 'source_url': 'https://npb.jp/'},
      ]
    }, null, isNpb: true);
    expect(events.length, 2);
    expect(contractFaLabel(events[0]), '国内FA権獲得');
    expect(contractFaLabel(events[1]), '海外FA権獲得（見込み）');
  });
  test('参考動画10本は全て5万再生以上で実際の評価または予想に使用', () {
    final data = jsonDecode(
        File('backend/assets/data/draft_2026.json').readAsStringSync());
    final videos = data['reference_videos'] as List;
    expect(videos.length, 10);
    for (final video in videos) {
      expect(video['view_count'], greaterThanOrEqualTo(50000));
      expect(video['used_for'], isNotEmpty);
      expect(video['checked_at'], '2026-10-15');
      final id = video['video_id'];
      final referenced = (data['players'] as List).any((p) => [
            ...?p['attention_sources'],
            for (final q in p['predictions'] ?? []) ...[
              q,
              ...?q['additional_sources']
            ]
          ].any((e) => e['video_id'] == id));
      expect(referenced, isTrue, reason: '$id');
    }
  });
  testWidgets('同一年の国内海外FAラベルと年俸を重ならず表示し出典を開く', (t) async {
    t.view.physicalSize = const Size(900, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthContracts(year: 2026, team: {
      'id_team': 1,
      'name_team': '球団',
      'id_league': 1,
      'contracts': [
        {
          'player_key': 'test',
          'name': '架空選手',
          'salary_history': [
            {'year': 2026, 'amount': 10000000}
          ],
          'fa_events': [
            {
              'year': 2026,
              'type': 'domestic',
              'projected': false,
              'source_url': 'https://npb.jp/',
              'detail': '確認済み資料'
            },
            {
              'year': 2026,
              'type': 'international',
              'projected': true,
              'source_url': 'https://npb.jp/',
              'detail': '見込み資料'
            },
          ]
        }
      ]
    }))));
    await t.pumpAndSettle();
    final domestic = find.text('国内FA権獲得');
    final overseas = find.text('海外FA権獲得（見込み）');
    expect(domestic, findsOneWidget);
    expect(overseas, findsOneWidget);
    expect(t.getBottomLeft(domestic).dy, lessThan(t.getTopLeft(overseas).dy));
    await t.tap(domestic);
    await t.pumpAndSettle();
    expect(find.text('確認済み資料'), findsOneWidget);
    expect(find.text('2026年 国内FA権獲得'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
