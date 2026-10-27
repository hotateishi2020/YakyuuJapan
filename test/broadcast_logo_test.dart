import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/widgets/broadcast_logo.dart';

void main() {
  test('RKB television and radio use distinct official assets', () {
    expect(broadcastLogoAsset({'name':'RKB毎日放送','kind':'tv'}), endsWith('/rkb.svg'));
    expect(broadcastLogoAsset({'name':'RKBラジオ','kind':'radio'}), endsWith('/rkb-radio.png'));
  });
  test('NHK radio 1 uses the supplied image without affecting radio 2 or TV', () {
    for(final name in ['NHKラジオ第一','NHKラジオ第1','ＮＨＫラジオ第１','NHKラジオ','NHK R1']) {
      expect(broadcastLogoAsset({'name':name,'kind':'radio'}),endsWith('/nhk-radio1.png'));
    }
    expect(broadcastLogoAsset({'name':'NHKラジオ第2','kind':'radio'}),isNull);
    expect(broadcastLogoAsset({'name':'NHK BS','kind':'tv'}),isNull);
  });
  testWidgets('supplied NHK logo renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:SizedBox(width:56,height:28,
      child:BroadcastLogo(row:{'name':'NHKラジオ第1','kind':'radio'}))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:150)));
    await tester.pump();
    expect(tester.takeException(),isNull);
  });
  testWidgets('bundled logos render without remote image requests', (tester) async {
    for (final name in ['NHK総合（長野）','NHK Eテレ（長野）','テレビ信州','長野朝日放送','長野放送','SBC信越放送','信越放送','SBC','TVer','U-NEXT','hulu','RKB毎日放送','日本テレビ','テレビ東京','TBSテレビ']) {
      final row = {'name':name,'kind':'tv'};
      expect(File(broadcastLogoAsset(row)!).existsSync(),isTrue);
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:56,height:28,child:BroadcastLogo(row:row)))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:150)));
      await tester.pump();
      expect(tester.takeException(),isNull,reason:name);
    }
  });
}
