import 'app/ContractTransferShares.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/StrengthUsage.dart';
import 'app/ContractSupplements.dart';
import 'app/ContractExchange.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  await refreshContractTransfers(year);
  final client = http.Client();
  try {
    final history = usageMap(jsonDecode(await StrengthUsage.get(client, 'https://frontofficemoves.com/data/contracts.json')));
    final payroll = usageMap(jsonDecode(await StrengthUsage.get(client, 'https://frontofficemoves.com/data/payroll.json')));
    if (usageInt(payroll['season']) != year) {
      throw StateError('年俸データの年度が一致しません');
    }
    final rates = parseContractExchangeRates(await StrengthUsage.get(client, 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml'));
    final salaries = <String, Map<String, dynamic>>{};
    for (final club in usageMap(payroll['clubs']).entries) {
      for (final raw in usageMap(usageMap(club.value)['players']).values) {
        final p = usageMap(raw);
        if (usageInt(p['id']) <= 0 || usageInt(p['s']) <= 0) continue;
        // Prefer current roster salary to dead-money entries for the same player.
        if (salaries.containsKey('${p['id']}') && p['sec'] != 'active') {
          continue;
        }
        salaries['${p['id']}'] = {...p, 'team': club.key};
      }
    }
    final teams = await Postgres.withConnection((c) => c.execute("SELECT id_team,payload FROM t_team_strength WHERE code_org='mlb' AND int_year=\$1", parameters: [year]));
    for (final row in teams) {
      final team = usageMap(row[1] is String ? jsonDecode(row[1] as String) : row[1]);
      final records = <Map<String, dynamic>>[];
      for (final p in usageMaps(team['roster'])) {
        final id = '${p['source_player_id']}';
        final annual = <int, Map<String, dynamic>>{};
        final periods = <Map<String, dynamic>>[];
        for (final c in usageMaps(history[id])) {
          final start = usageInt(c['ds']) > 0 ? usageInt(c['ds']) : usageInt(c['yr']);
          final years = usageInt(c['dy']) > 0 ? usageInt(c['dy']) : usageInt(c['y']);
          final period = start > 0 && years > 0 ? '$start〜${start + years - 1}年' : '${c['d'] ?? '日付不明'}締結・${years > 0 ? '$years年契約' : '期間非公表'}（開始・終了年未確認）';
          periods.add({...contractExchange(c['d'], rates), 'period': period, 'start_year': start > 0 ? start : null, 'end_year': start > 0 && years > 0 ? start + years - 1 : null, 'team': c['t'], 'detail': usageInt(c['tv']) > 0 ? '契約総額 USD ${c['dt'] ?? c['tv']}（年俸とは別）' : '契約金額未確認'});
          if (usageInt(c['yr']) > 0 && usageInt(c['y']) == 1 && usageInt(c['tv']) > 0) {
            final y = usageInt(c['yr']);
            annual[y] = {...contractExchange(c['d'], rates), 'year': y, 'amount': usageInt(c['tv']), 'currency': 'USD', 'team': c['t']};
          }
        }
        final salary = salaries[id];
        if (salary != null) {
          // Use a unique dated contract covering this season. Undated or
          // ambiguous contracts must not borrow another contract's FX rate.
          final candidates = usageMaps(history[id]).where((c) {
            final date = DateTime.tryParse('${c['d']}');
            if (date == null || c['t'] != salary['team']) return false;
            final start = usageInt(c['ds']) > 0 ? usageInt(c['ds']) : usageInt(c['yr']);
            final length = usageInt(c['dy']) > 0 ? usageInt(c['dy']) : usageInt(c['y']);
            if (length <= 0) return false;
            if (start > 0) return year >= start && year < start + length;
            // Without an explicit start, only match an annual amount as well.
            return year >= date.year && year <= date.year + length && usageInt(c['aav']) == usageInt(salary['s']);
          }).toList();
          annual[year] = {if (candidates.length == 1) ...contractExchange(candidates.single['d'], rates), 'year': year, 'amount': usageInt(salary['s']), 'currency': 'USD', 'team': salary['team'], 'deferred': usageInt(salary['d']), 'paid': usageInt(salary['a'])};
        }
        if (annual.isEmpty && periods.isEmpty) continue;
        records.add({
          'player_key': p['player_key'],
          'name': p['name'],
          'salary_history': annual.values.toList(),
          'affiliation_history': [
            for (final c in usageMaps(history[id]))
              if (usageInt(c['yr']) > 0 && c['t'] != null) {'year': usageInt(c['yr']), 'team': c['t']},
            if (salary != null) {'year': year, 'team': salary['team']},
          ],
          'periods': periods,
          'source_url': 'https://frontofficemoves.com/payrolls',
          'retrieved_at': DateTime.now().toUtc().toIso8601String()
        });
      }
      await Postgres.withConnection((c) => c.execute("UPDATE t_team_strength SET payload=payload || \$1::jsonb,updated_at=NOW() WHERE code_org='mlb' AND int_year=\$2 AND id_team=\$3", parameters: [
            jsonEncode({'contracts': records.map((r) => supplementContracts('mlb', r)).toList()}),
            year,
            row[0]
          ]));
      print('${team['name_team']}: ${records.length}人');
    }
  } finally {
    client.close();
  }
  exit(0);
}
