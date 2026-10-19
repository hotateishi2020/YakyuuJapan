import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/PredictGroupBoard.dart';
void main() {
 test('MVPは投手・野手の設定に関係なく黒文字', () {
   expect(predictStatsColor(title:'MVP',pitcher:true),Colors.black);
   expect(predictStatsColor(title:'MVP',pitcher:false),Colors.black);
   expect(predictStatsColor(title:'MVP'),Colors.black);
 });
}
