import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/player_detail_dialog.dart';
void main(){
 testWidgets('公式IDだけの選手も画像付きプロフィールをスマホに表示できる',(t)async{
  t.view.physicalSize=const Size(390,900);t.view.devicePixelRatio=1;
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  await http.runWithClient(()async{
   await t.pumpWidget(const MaterialApp(home:PlayerDetailDialog(player:{'source_player_id':'123'},org:'npb',year:2026)));
   await t.pumpAndSettle();
   expect(find.text('AI生成キャラクター'),findsNothing);
   final image=t.widget<Image>(find.byType(Image).first);
   final provider = image.image is ResizeImage ? (image.image as ResizeImage).imageProvider : image.image;
   expect((provider as NetworkImage).url,contains('/player-art/npb-123-test.png'));
   expect(find.text('新人選手'),findsOneWidget);expect(t.takeException(),isNull);
  },()=>MockClient((_)async=>http.Response(jsonEncode({'found':true,'profile':{'name_full':'新人選手','name_team':'ソフトバンク'},'character_image':{'url':'/player-art/npb-123-test.png'}}),200,headers:{'content-type':'application/json; charset=utf-8'})));
 });
}
