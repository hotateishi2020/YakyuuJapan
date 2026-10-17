/// ECB rates are quoted per EUR; dividing JPY by USD gives JPY per USD.
Map<String, double> parseContractExchangeRates(String xml) {
  final result = <String, double>{};
  for (final day in RegExp(r"""<Cube\s+time=['"]([0-9-]+)['"]>([\s\S]*?)</Cube>""").allMatches(xml)) {
    double? rate(String currency) {
      final match = RegExp("""currency=['"]$currency['"]\\s+rate=['"]([0-9.]+)['"]""").firstMatch(day[2]!);
      return double.tryParse(match?[1] ?? '');
    }

    final usd = rate('USD'), jpy = rate('JPY');
    if (usd != null && usd > 0 && jpy != null && jpy > 0) {
      result[day[1]!] = jpy / usd;
    }
  }
  if (result.isEmpty) throw const FormatException('ECB為替履歴を解析できません');
  return result;
}

Map<String, dynamic> contractExchange(dynamic signedDate, Map<String, double> rates) {
  final date = DateTime.tryParse('$signedDate');
  if (date == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('$signedDate')) {
    return {};
  }
  for (var offset = 0; offset <= 7; offset++) {
    final key = date.subtract(Duration(days: offset)).toIso8601String().substring(0, 10);
    final rate = rates[key];
    if (rate != null) {
      return {
        'signed_date': '$signedDate',
        'usd_jpy_rate': rate,
        'exchange_date': key,
        'exchange_source': 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml',
      };
    }
  }
  return {'signed_date': '$signedDate'};
}
