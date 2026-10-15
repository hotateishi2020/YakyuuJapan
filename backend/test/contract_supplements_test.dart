import 'package:test/test.dart';
import '../app/ContractSupplements.dart';

void main() {
  test('補完は一致選手のみ、再実行で重複せず未知の契約の為替情報を保持', () {
    final original = <String, dynamic>{
      'player_key': 'mlb:660271',
      'periods': [
        {'team': 'LAD', 'signed_date': '2023-12-11', 'usd_jpy_rate': 145.0}
      ],
      'salary_history': [
        {'year': 2026, 'amount': 70000000}
      ]
    };
    final result = supplementContracts('mlb', original);
    final period = (result['periods'] as List).single;
    expect(period['start_year'], 2024);
    expect(period['end_year'], 2033);
    expect(period['usd_jpy_rate'], 145);
    expect(period['source_url'], contains('mlb.com'));
    expect(supplementContracts('mlb', result), result);
    expect((original['periods'] as List).single['start_year'], isNull);
    expect(supplementContracts('npb', original), original);
  });
}
