import 'package:test/test.dart';
import '../app/ContractSalaryShares.dart';

void main() {
  test('スクバルの年俸は一度だけ保持し負担額の合計が総額に一致', () {
    final original = <String, dynamic>{'player_key': 'mlb:669373', 'salary_history': [
      {'year': 2025, 'amount': 10150000, 'currency': 'USD'},
      {'year': 2026, 'amount': 32000000, 'currency': 'USD'},
    ]};
    final result = supplementSalaryShares('mlb', original);
    final salaries = result['salary_history'] as List;
    expect(salaries, hasLength(2));
    expect(salaries.last['amount'], 32000000);
    expect((salaries.last['team_shares'] as List).fold<int>(0, (sum, s) => sum + (s['amount'] as int)), 32000000);
    expect(supplementSalaryShares('mlb', result), result);
    expect(supplementSalaryShares('npb', original), original);
    expect((original['salary_history'] as List).last['team_shares'], isNull);
  });
}
