import 'dart:convert';
import 'package:test/test.dart';
import '../app/ClubDefense.dart';
void main() {
  final rows = [for (var i=0; i<30; i++) {'entity_id': i, 'entity_code': 'Fielding_Team', 'year': '2026', 'n': '100', 'outs_above_average': i-15}];
  test('OAAは球団IDと年度を確認しゼロも実測として保存', () {
    final data = parseTeamOaa('var data = ${jsonEncode(rows)};', 2026, 'https://example.com');
    expect(data.length, 30);
    expect(data['15']['value'], 0);
    expect(data['0']['value'], -15);
    expect(data['0']['source_url'], 'https://example.com');
  });
  test('別年度・欠落球団・取得エラーを正常データにしない', () {
    expect(() => parseTeamOaa('var data = ${jsonEncode(rows)};', 2025, ''), throwsStateError);
    expect(() => parseTeamOaa('var data = ${jsonEncode(rows.take(29).toList())};', 2026, ''), throwsStateError);
    expect(() => parseTeamOaa('<html>error</html>', 2026, ''), throwsStateError);
  });
}
