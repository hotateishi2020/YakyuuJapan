import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'ContractSupplements.dart';

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
    : [];
int _int(Object? value) => int.tryParse('$value') ?? 0;
String _name(Object? value) => '${value ?? ''}'.replaceAll(RegExp(r'[\s　・･]'), '');
String _birth(Object? value) => '${value ?? ''}'.split(RegExp(r'[ T]')).first;

Future<void> attachJapaneseMlbContracts(Connection conn, List<Map<String, dynamic>> players, int year) async {
  final rows = await conn.execute("SELECT id_team,payload->'contracts' AS contracts,payload->'roster' AS roster FROM t_team_strength WHERE code_org='mlb' AND int_year=\$1", parameters: [year]);
  final records = <Map<String, dynamic>>[];
  for (final row in rows) {
    Object? decode(Object? value) => value is String ? jsonDecode(value) : value;
    final roster = _maps(decode(row[2]));
    for (final contract in _maps(decode(row[1]))) {
      final person = roster.where((p) => p['player_key'] == contract['player_key']).firstOrNull;
      records.add({...contract, 'id_team': row[0], 'date_birth': person?['date_birth']});
    }
  }
  // The injured player has no season roster entry but a verified active contract.
  records.add({'id_team': 41, 'name': 'ダルビッシュ有', 'date_birth': '1986-08-16', 'player_key': 'mlb:506433'});
  for (final player in players) {
    final teams = {player['id_team'], ...?player['team_ids'] as List?}.map((id) => '$id').toSet();
    final matches = records.where((r) => teams.contains('${r['id_team']}') &&
        ((_name(player['name_player']).isNotEmpty && _name(player['name_player']) == _name(r['name'])) ||
        (_birth(player['date_birth']).isNotEmpty && _birth(player['date_birth']) == _birth(r['date_birth'])))).toList();
    // Names or birthdays alone must not select between different people.
    if (matches.map((r) => r['player_key']).toSet().length != 1) continue;
    final labels = <String>{};
    final salaries = <String>{};
    final sources = <String>{};
    for (final match in matches) {
      final record = supplementContracts('mlb', match);
      final salary = japaneseMlbSalaryLabel(record, year);
      if (salary != 'ー') salaries.add(salary);
      final label = japaneseMlbContractLabel(record, year);
      if (label != 'ー') labels.add(label);
      for (final p in _maps(record['periods'])) {
        if (_int(p['start_year']) <= year && _int(p['end_year']) >= year && p['source_url'] != null) sources.add('${p['source_url']}');
      }
    }
    if (labels.length == 1) player['contract_label'] = labels.single;
    if (salaries.length == 1) player['salary_label'] = salaries.single;
    player['contract_sources'] = sources.toList();
  }
}

String _dollars(num amount) {
  final unit = amount >= 100000000 ? 100000000 : 10000;
  final value = (amount / unit).toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$value${unit == 100000000 ? '億' : '万'}ドル';
}

/// Use the selected season's salary, not the average of a multi-year contract.
String japaneseMlbSalaryLabel(Map<String, dynamic> record, int year) {
  if (year == 2026 && record['player_key'] == 'mlb:506433') return '返上';
  final amounts = _maps(record['salary_history'])
      .where((s) => _int(s['year']) == year && s['currency'] == 'USD')
      .map((s) => num.tryParse('${s['amount']}'))
      .whereType<num>().where((amount) => amount.isFinite && amount >= 0).toSet();
  return amounts.length == 1 ? _dollars(amounts.single) : 'ー';
}

/// Select a contract covering the requested season, never infer an end from pay.
String japaneseMlbContractLabel(Map<String, dynamic> record, int year) {
  final periods = _maps(record['periods']).where((p) =>
      _int(p['start_year']) > 0 && _int(p['start_year']) <= year && _int(p['end_year']) >= year).toList()
    ..sort((a, b) => _int(b['start_year']).compareTo(_int(a['start_year'])));
  if (periods.isEmpty) return 'ー';
  final current = periods.where((p) => p['start_year'] == periods.first['start_year']).toList();
  if (current.length > 1) return 'ー';
  final period = current.single;
  final start = _int(period['start_year']), end = _int(period['end_year']);
  final duration = end - start + 1;
  final raw = '${period['total_label'] ?? ''} ${period['detail'] ?? ''}';
  final total = RegExp(r'USD\s*([\d,]+(?:\.\d+)?)').firstMatch(raw);
  String amount = '金額未確認';
  if (total != null) {
    amount = _dollars(num.parse(total[1]!.replaceAll(',', '')));
  } else if ('${period['total_label'] ?? ''}'.trim().isNotEmpty) {
    amount = '${period['total_label']}';
  } else if (duration == 1) {
    final salaries = _maps(record['salary_history']).where((s) => _int(s['year']) == year && s['currency'] == 'USD' && _int(s['amount']) > 0).toList();
    if (salaries.length == 1) amount = _dollars(_int(salaries.single['amount']));
  }
  return '$duration年 $amount（$end年まで）';
}
