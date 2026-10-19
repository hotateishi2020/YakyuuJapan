import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/strength_usage.dart';
void main(){
 test('FA権保有だけでは移籍確定にならず年度外はラベルを出さない',(){
  expect(rosterMoveLabels({'fa_eligible':true},2026),['FA権保有']);
  expect(rosterMoveLabels({'move_status':'FA宣言（移籍先未定）','move_status_year':2026},2026),['FA宣言（移籍先未定）']);
  expect(rosterMoveLabels({'move_method':'現役ドラフト','move_method_year':2026},2026),['現役ドラフト']);
  expect(rosterMoveLabels({'move_method':'トレード','move_method_year':2025},2026),isEmpty);
  expect(rosterMoveLabels({'move_method':'FA移籍','move_method_year':2026,'departure_confirmed':true,'fa_eligible':true},2026),['FA移籍']);
 });
}
