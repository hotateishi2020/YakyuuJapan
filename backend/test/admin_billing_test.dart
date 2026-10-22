import 'package:test/test.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import '../app/AdminBilling.dart';
class UnusedConnection implements Connection {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Must not touch DB');
}
void main() {
  final input = {'provider':'neon','month':'2026-10','kind':'accrued','currency':'USD','amount':'12.34','period':'2026年10月1日〜22日'};
  test('USDは整数セントで保持しゼロと未登録を区別する', () {
    expect(validateBilling(input)['amount_minor'],1234);
    expect(validateBilling({...input,'amount':'0'})['amount_minor'],0);
    expect(validateBilling({...input,'amount':'0.1'})['amount_minor'],10);
    expect(validateBilling({...input,'currency':'JPY','amount':'1234'})['amount_minor'],1234);
  });
  test('月・金額・通貨・期間・種類を検証する', () {
    for (final patch in [
      {'month':'2026-13'},{'month':'2026-1'},{'provider':'other'},
      {'kind':'other'},{'currency':'EUR'},{'amount':12.34},{'amount':'-1'},
      {'amount':'NaN'},{'amount':'1.234'},{'amount':'999999999999'},
      {'currency':'JPY','amount':'1.01'},{'period':''},{'period':'a'*201},
    ]) { expect(() => validateBilling({...input,...patch}),throwsFormatException); }
  });
  test('未認証の閲覧と保存はDBに触れず403', () async {
    final c=UnusedConnection();
    expect((await AdminBilling.read(c,Request('GET',Uri.parse('http://localhost/admin/billing?month=2026-10')))).statusCode,403);
    expect((await AdminBilling.save(c,Request('POST',Uri.parse('http://localhost/admin/billing'),body:'{}'))).statusCode,403);
  });
}
