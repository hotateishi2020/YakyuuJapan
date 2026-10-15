import 'package:test/test.dart';
import '../app/OverseasContracts.dart';

void main() {
  test('来日前のみ登録し最低年俸・複数年総額を年俸にしない', () {
    final imported = overseasContractHistory(
        [
          {'yr': 2022, 'y': 1, 'tv': 1000000, 't': 'NYY'},
          {'yr': 2023, 'y': 1, 'min': 720000, 't': 'LAA'},
          {'yr': 2020, 'y': 2, 'tv': 6000000, 't': 'NYM'},
          {'yr': 2024, 'y': 3, 'tv': 6000000, 't': 'SD'},
          {'yr': 2025, 'y': 1, 'tv': 8000000, 't': 'SF'},
          {'d': '2021-11-28', 'mn': 1, 't': 'LAA'},
        ],
        2025,
        {},
        1);
    expect((imported['salary_history'] as List).length, 1);
    expect((imported['salary_history'] as List).single['amount'], 1000000);
    expect((imported['periods'] as List).length, 4);
    expect((imported['periods'] as List)[1]['detail'], contains('実受取額未確認'));
    final record = <String, dynamic>{
      'salary_history': [
        {'year': 2026, 'amount': 200000000, 'currency': 'JPY'}
      ],
      'periods': [],
      'affiliation_history': [],
    };
    final merged = mergeOverseasContracts(record, imported);
    expect((merged['salary_history'] as List).length, 2);
    expect(mergeOverseasContracts(merged, imported), merged);
    expect((record['salary_history'] as List).length, 1);
  });
}
