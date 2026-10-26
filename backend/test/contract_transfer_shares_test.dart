import 'package:test/test.dart';
import '../app/ContractTransferShares.dart';
import '../app/ContractSalaryShares.dart';
void main() {
  test('移籍先の欠けた契約だけを選手IDで補う', () {
    final record=<String,dynamic>{'player_key':'npb:1','salary_history':[{'year':2026,'amount':100,'currency':'JPY','team_shares':[{'team':'A','amount':70},{'team':'B','amount':30}]}]};
    final result=shareTransferredContracts([], [{'player_key':'npb:1'}], [record], 2026);
    expect(result.single['player_key'],'npb:1');
    expect(shareTransferredContracts([], [{'player_key':'npb:2'}], [record], 2026),isEmpty);
    expect(shareTransferredContracts(result, [{'player_key':'npb:1'}], [record], 2026),result);
  });
  final start=DateTime(2026,2,1), end=DateTime(2026,12,1);
  Map<String,dynamic> move(String from,String to,String date)=>{'from':from,'to':to,'date':date,'source_url':'official'};
  test('NPBの複数回移籍をまとめ負担目安の合計は年俸に一致',(){
    final result=allocateTransferSalary({'amount':10000001,'currency':'JPY'},[move('巨人','西武','2026-05-10'),move('西武','巨人','2026-07-01')],start,end);
    final shares=result['team_shares'] as List;
    expect(shares.length,2);
    expect(shares.fold<int>(0,(n,s)=>n+(s['amount'] as int)),10000001);
    expect(shares.every((s)=>s['method']=='tenure_estimate'),true);
    expect(shares.first['days'],251);
  });
  test('オフ移籍・不連続の履歴・年俸不明は誤った按分を作らない',(){
    final salary=<String,dynamic>{'amount':100};
    expect(allocateTransferSalary(salary,[move('A','B','2026-01-01')],start,end),salary);
    expect(allocateTransferSalary(salary,[move('A','B','2026-05-01'),move('C','D','2026-06-01')],start,end),salary);
    expect(allocateTransferSalary({},[move('A','B','2026-05-01')],start,end),isEmpty);
  });
  test('MLBの報道済み負担額は日割り推定で上書きしない',(){
    final record=supplementSalaryShares('mlb',{'player_key':'mlb:669373','salary_history':[{'year':2026,'share_method':'tenure_estimate'}]});
    final salary=(record['salary_history'] as List).single as Map<String,dynamic>;
    expect(salary.containsKey('share_method'),false);
    expect(allocateTransferSalary(salary,[move('DET','LAD','2026-08-02')],DateTime(2026,3,25),DateTime(2026,9,28)),salary);
  });
}
