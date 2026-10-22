import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'Auth.dart';

String billingMonth(dynamic value) {
  if (value is! String || !RegExp(r'^20\d{2}-(0[1-9]|1[0-2])$').hasMatch(value)) {
    throw const FormatException('対象月はYYYY-MMで指定してください');
  }
  return value;
}

Map<String, dynamic> validateBilling(dynamic value) {
  if (value is! Map) throw const FormatException('入力形式が正しくありません');
  final month = billingMonth(value['month']);
  if (!['neon', 'render'].contains(value['provider']) ||
      !['accrued', 'invoiced'].contains(value['kind'])) {
    throw const FormatException('サービスまたは金額の種類が正しくありません');
  }
  final currency = value['currency'];
  if (!['USD', 'JPY'].contains(currency)) throw const FormatException('通貨を選択してください');
  final amount = value['amount'];
  if (amount is! String || !RegExp(currency == 'JPY' ? r'^\d{1,9}$' : r'^\d{1,9}(\.\d{1,2})?$').hasMatch(amount)) {
    throw const FormatException('金額は0以上、USDは小数2桁まで、JPYは整数で入力してください');
  }
  final parts = amount.split('.');
  final minor = int.parse(parts.first) * (currency == 'USD' ? 100 : 1) +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  final period = value['period'];
  if (period is! String || period.trim().isEmpty || period.length > 200) {
    throw const FormatException('利用対象期間を200文字以内で入力してください');
  }
  return {'month': month, 'provider': value['provider'], 'kind': value['kind'],
    'currency': currency, 'amount_minor': minor, 'period': period.trim()};
}

class AdminBilling {
  static Future<void> ensure(Connection conn) => conn.execute('''
    CREATE TABLE IF NOT EXISTS t_admin_billing (
      provider text NOT NULL CHECK (provider IN ('neon','render')),
      month text NOT NULL,
      kind text NOT NULL CHECK (kind IN ('accrued','invoiced')),
      currency text NOT NULL CHECK (currency IN ('USD','JPY')),
      amount_minor bigint NOT NULL CHECK (amount_minor>=0),
      period text NOT NULL,
      checked_at timestamptz NOT NULL DEFAULT now(),
      updated_by integer NOT NULL REFERENCES m_user(id),
      PRIMARY KEY (provider,month,kind)
    )''').then((_) {});

  static Response json(int status, Object body) => Response(status,
      body: jsonEncode(body), headers: {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'});

  static Future<Response> read(Connection conn, Request request) async {
    if (await Auth.adminUserId(conn, request) == null) return json(403, {'error': '管理者だけが利用できます'});
    String month;
    try { month = billingMonth(request.url.queryParameters['month']); }
    on FormatException catch (e) { return json(400, {'error': e.message}); }
    await ensure(conn);
    final rows = await conn.execute('SELECT provider,month,kind,currency,amount_minor,period,checked_at::text FROM t_admin_billing WHERE month=\$1 ORDER BY provider,kind', parameters: [month]);
    return json(200, {'month': month, 'entries': rows.map((r) => r.toColumnMap()).toList(), 'source': 'manual'});
  }

  static Future<Response> save(Connection conn, Request request) async {
    final admin = await Auth.adminUserId(conn, request);
    if (admin == null) return json(403, {'error': '管理者だけが利用できます'});
    Map<String, dynamic> input;
    try {
      final body = await request.readAsString();
      if (body.length > 4000) return json(400, {'error': '入力内容が長すぎます'});
      input = validateBilling(jsonDecode(body));
    } on FormatException catch (e) { return json(400, {'error': e.message}); }
    await ensure(conn);
    await conn.execute('''INSERT INTO t_admin_billing
      (provider,month,kind,currency,amount_minor,period,updated_by)
      VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7)
      ON CONFLICT (provider,month,kind) DO UPDATE SET
      currency=EXCLUDED.currency,amount_minor=EXCLUDED.amount_minor,
      period=EXCLUDED.period,updated_by=EXCLUDED.updated_by,checked_at=now()''',
      parameters: [input['provider'],input['month'],input['kind'],input['currency'],input['amount_minor'],input['period'],admin]);
    return json(200, {'saved': true});
  }
}
