import 'package:test/test.dart';
import '../app/InjuryList.dart';
void main() {
  test('復帰予定は不明・今期絶望・全治期間に揃える', () {
    expect(InjuryList.periodLabel('不明'), '不明');
    expect(InjuryList.periodLabel('今季絶望・全治6～8ヶ月'), '今期絶望');
    expect(InjuryList.periodLabel('全治4週間程度'), '全治4週間');
    expect(InjuryList.periodLabel('全治6～8週間程度'), '全治6〜8週間');
    expect(InjuryList.periodLabel('長期見込'), '長期見込');
    expect(InjuryList.periodLabel(''), '不明');
  });

}
