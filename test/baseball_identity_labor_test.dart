import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/logic/baseball_labor.dart';
void main() {
 test('同名でもMLBタイガースと阪神は別ロゴ', () {
  expect(teamLogoVisual('タイガース', mlb: true).networkUrl, contains('/det.png'));
  expect(teamLogoVisual('阪神タイガース').asset, isNotNull);
  expect(teamLogoVisual('デトロイト・タイガース').asset, isNull);
  expect(teamLogoVisual('ジャイアンツ', mlb: true).networkUrl, contains('/sf.png'));
 });
 test('確定済みの労使紛争と将来の懸念を区別', () {
  expect(baseballLaborLabel(2004, mlb:false)?.label, 'ストライキ');
  expect(baseballLaborLabel(2022, mlb:true)?.label, 'ロックアウト');
  expect(baseballLaborLabel(1995, mlb:true)?.label, 'ストライキ');
  expect(baseballLaborLabel(2026, mlb:true), isNull);
  expect(baseballLaborLabel(2027, mlb:true)?.label, contains('未確定'));
  expect(baseballLaborLabel(2027, mlb:false), isNull);
 });
}
