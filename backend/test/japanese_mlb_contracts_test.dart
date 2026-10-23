import 'package:test/test.dart';
import '../app/JapaneseMlbContracts.dart';
import '../app/ContractSupplements.dart';
void main() {
  test('年俸は選択年度の金額を使い不明・矛盾時は推測しない', () {
    final record={'salary_history':[
      {'year':2025,'amount':1000000,'currency':'USD'},
      {'year':2026,'amount':22025000,'currency':'USD'},
    ]};
    expect(japaneseMlbSalaryLabel(record,2026),'2202.5万ドル');
    expect(japaneseMlbSalaryLabel(record,2027),'ー');
    expect(japaneseMlbSalaryLabel({'salary_history':[
      {'year':2026,'amount':1000000,'currency':'USD'},
      {'year':2026,'amount':2000000,'currency':'USD'},
    ]},2026),'ー');
  });

  test('選択年度に有効な契約期間・総額・終了年を表示する', () {
    final record = {'periods': [
      {'start_year': 2026, 'end_year': 2030, 'detail': '契約総額 USD 90000000（年俸とは別）'},
      {'start_year': 2031, 'end_year': 2032, 'detail': '契約総額 USD 50000000'},
    ]};
    expect(japaneseMlbContractLabel(record, 2026), '5年 9000万ドル（2030年まで）');
    expect(japaneseMlbContractLabel(record, 2031), '2年 5000万ドル（2032年まで）');
    expect(japaneseMlbContractLabel(record, 2025), 'ー');
  });
  test('年俸から複数年契約の総額や終了年を推測しない', () {
    final record = {'salary_history': [{'year':2026,'amount':780000,'currency':'USD'}]};
    expect(japaneseMlbContractLabel(record, 2026), 'ー');
    expect(japaneseMlbContractLabel({...record, 'periods':[{'start_year':2026,'end_year':2026}]},2026), '1年 78万ドル（2026年まで）');
    expect(japaneseMlbContractLabel({...record, 'periods':[{'start_year':2026,'end_year':2027}]},2026), '2年 金額未確認（2027年まで）');
  });
  test('確認済みの期間を既存の契約金額へ補完し小数も保持する', () {
    final record = supplementContracts('mlb', {'player_key':'mlb:684007','periods':[
      {'team':'CHC','signed_date':'2025-11-18','detail':'契約総額 USD 22025000'},
    ]});
    expect(japaneseMlbContractLabel(record,2026),'1年 2202.5万ドル（2026年まで）');
    expect(japaneseMlbContractLabel(supplementContracts('mlb', {'player_key':'mlb:506433'}),2026),'6年 1.08億ドル（2028年まで）');
  });
}
