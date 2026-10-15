import 'package:test/test.dart';
import '../app/ContractExchange.dart';

void main() {
  test('ECBの対ユーロレートから円ドルを計算し休業日は直前のみ使用', () {
    final rates = parseContractExchangeRates("""
<Cube time='2023-12-08'><Cube currency='USD' rate='1.1'/>
<Cube currency='JPY' rate='165'/></Cube>
<Cube time='2023-12-11'><Cube currency='USD' rate='1.2'/>
<Cube currency='JPY' rate='168'/></Cube>""");
    expect(rates['2023-12-08'], closeTo(150, .00001));
    final fx = contractExchange('2023-12-10', rates);
    expect(fx['exchange_date'], '2023-12-08');
    expect(fx['usd_jpy_rate'], closeTo(150, .00001));
    expect(contractExchange(null, rates), isEmpty);
    expect(contractExchange('2023-12-07', rates)['usd_jpy_rate'], isNull);
    expect(contractExchange('2024-01-01', rates)['usd_jpy_rate'], isNull);
  });
}
