import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/widgets/broadcast_logo.dart';

void main() {
  test('RKB television and radio use distinct official assets', () {
    expect(broadcastLogoAsset({'name':'RKB毎日放送','kind':'tv'}), endsWith('/rkb.svg'));
    expect(broadcastLogoAsset({'name':'RKBラジオ','kind':'radio'}), endsWith('/rkb-radio.png'));
  });
  testWidgets('bundled logos render without remote image requests', (tester) async {
    for (final name in ['TVer','U-NEXT','hulu','RKB毎日放送','日本テレビ','テレビ東京','TBSテレビ']) {
      final row = {'name':name,'kind':'tv'};
      expect(File(broadcastLogoAsset(row)!).existsSync(),isTrue);
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:56,height:28,child:BroadcastLogo(row:row)))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:150)));
      await tester.pump();
      expect(tester.takeException(),isNull,reason:name);
    }
  });
}
