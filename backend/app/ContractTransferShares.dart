import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'StrengthUsage.dart';
import 'NpbRosterTransactions.dart';

File contractTransferFile(int year) => File('${Directory('backend/data').existsSync() ? 'backend/' : ''}data/contract-transfers-$year.json');
final _transferCache = <int, Map<String, dynamic>>{};

/// Proration is an estimate, not evidence of the clubs' private settlement.
/// Preserve published allocations, including retained-salary arrangements.
Map<String, dynamic> allocateTransferSalary(Map<String, dynamic> salary,
    List<Map<String, dynamic>> moves, DateTime start, DateTime endExclusive) {
  if (salary['team_shares'] is List && (salary['team_shares'] as List).isNotEmpty && salary['share_method'] != 'tenure_estimate') return salary;
  final amount = usageInt(salary['amount']);
  if (amount <= 0 || !endExclusive.isAfter(start)) return salary;
  final events = <String, Map<String, dynamic>>{};
  for (final move in moves) {
    final date = DateTime.tryParse('${move['date']}');
    if (date == null || !date.isAfter(start) || !date.isBefore(endExclusive)) continue;
    if ('${move['from'] ?? ''}'.isEmpty || '${move['to'] ?? ''}'.isEmpty || move['from'] == move['to']) continue;
    events['${move['date']}/${move['from']}/${move['to']}'] = move;
  }
  final ordered = events.values.toList()..sort((a,b) => '${a['date']}'.compareTo('${b['date']}'));
  if (ordered.isEmpty) return salary;
  var team = '${ordered.first['from']}';
  var cursor = start;
  final days = <String, int>{};
  for (final move in ordered) {
    // An incomplete chain may hide releases, signings or missing transactions.
    if (move['from'] != team) return salary;
    final date = DateTime.parse('${move['date']}');
    days[team] = (days[team] ?? 0) + date.difference(cursor).inDays;
    cursor = date;
    team = '${move['to']}';
  }
  days[team] = (days[team] ?? 0) + endExclusive.difference(cursor).inDays;
  final totalDays = endExclusive.difference(start).inDays;
  var remaining = amount;
  final shares = <Map<String, dynamic>>[];
  for (final entry in days.entries.where((e) => e.value > 0)) {
    final part = entry.key == days.keys.last ? remaining : (amount * entry.value / totalDays).floor();
    remaining -= part;
    if (part <= 0) return salary;
    shares.add({'team': entry.key, 'amount': part, 'estimated': true,
      'method': 'tenure_estimate', 'days': entry.value, 'total_days': totalDays,
      'detail': '在籍日数按分の目安（${start.toIso8601String().substring(0,10)}〜${endExclusive.subtract(const Duration(days:1)).toIso8601String().substring(0,10)}）。移籍日から新球団に割当。球団間の負担金・精算、個別の支払条件は未反映。',
      'source_url': ordered.map((m) => '${m['source_url']}').toSet().join('\n')});
  }
  if (shares.length < 2) return salary;
  return {...salary, 'team_shares': shares, 'share_method': 'tenure_estimate', 'transfer_history': ordered};
}

Map<String, dynamic> supplementTransferShares(String org, Map<String, dynamic> record) {
  final salaries = usageMaps(record['salary_history']);
  if (salaries.isEmpty) return record;
  return {...record, 'salary_history': [for (final salary in salaries) (() {
    final year = usageInt(salary['year']);
    final file = contractTransferFile(year);
    final data = _transferCache.putIfAbsent(year, () => file.existsSync() ? usageMap(jsonDecode(file.readAsStringSync())) : <String,dynamic>{});
    final section = usageMap(data[org]);
    final start = DateTime.tryParse('${section['start']}'), end = DateTime.tryParse('${section['end_exclusive']}');
    if (start == null || end == null) return salary;
    return allocateTransferSalary(salary, usageMaps(section['moves']).where((m) => m['player_key'] == record['player_key']).toList(), start, end);
  })()]};
}

/// Refresh once before a contract import, using official transaction dates.
Future<Map<String, dynamic>> refreshContractTransfers(int year) async {
  final client = http.Client();
  try {
    Future<Map<String,dynamic>> json(String path) async => usageMap(jsonDecode(await StrengthUsage.get(client, 'https://statsapi.mlb.com/api/v1/$path')));
    final season = usageMaps((await json('seasons/$year?sportId=1'))['seasons']).single;
    final start = '${season['regularSeasonStartDate']}';
    final end = '${season['regularSeasonEndDate']}';
    final teams = {for (final t in usageMaps((await json('teams?sportId=1&season=$year'))['teams'])) usageInt(t['id']): '${t['abbreviation']}'};
    final url = 'https://statsapi.mlb.com/api/v1/transactions?startDate=$start&endDate=$end&sportId=1';
    final tx = usageMaps(usageMap(jsonDecode(await StrengthUsage.get(client,url)))['transactions']);
    final mlb = <Map<String,dynamic>>[];
    for (final t in tx) {
      if (!['TR','CLW'].contains(t['typeCode'])) continue;
      final from = teams[usageInt(usageMap(t['fromTeam'])['id'])], to = teams[usageInt(usageMap(t['toTeam'])['id'])];
      if (from == null || to == null || from == to) continue;
      mlb.add({'player_key':'mlb:${usageMap(t['person'])['id']}', 'name':usageMap(t['person'])['fullName'],
        'date':t['effectiveDate'] ?? t['date'], 'from':from, 'to':to, 'source_url':url, 'type':t['typeCode']});
    }
    final npbUrl = 'https://npb.jp/announcement/$year/pn_traded.html';
    final npb = parseNpbTransactions(await StrengthUsage.get(client,npbUrl),npbUrl,year)
      .where((t) => t['kind']=='arrival' && '${t['status_as_of']}'.compareTo('$year-03-01')>=0 && '${t['status_as_of']}'.compareTo('$year-11-01')<0)
      .map((t) => <String,dynamic>{'player_key':t['player_key'], 'name':t['name'], 'date':t['status_as_of'], 'from':t['previous_team_name'], 'to':t['team'], 'source_url':npbUrl}).toList();
    final result = <String,dynamic>{'year':year, 'retrieved_at':DateTime.now().toUtc().toIso8601String(),
      'mlb':{'start':start, 'end_exclusive':DateTime.parse(end).add(const Duration(days:1)).toIso8601String().substring(0,10), 'moves':mlb},
      // NPB's remuneration period is February–November. Calendar-day allocation
      // here is explicitly illustrative, not the contractual settlement rule.
      'npb':{'start':'$year-02-01','end_exclusive':'$year-12-01','moves':npb,
        'period_source':'https://jpbpa.net/wp-content/uploads/jpbpa-pdf/ag2024.pdf'}};
    final file = contractTransferFile(year);
    file.parent.createSync(recursive:true);
    final temp=File('${file.path}.tmp')..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    temp.renameSync(file.path); _transferCache[year]=result;
    return result;
  } finally { client.close(); }
}

/// A transfer does not change the player's historical contract identity.
/// Fill absent destination records only by the same official player key.
List<Map<String,dynamic>> shareTransferredContracts(List<Map<String,dynamic>> records,
    List<Map<String,dynamic>> roster, List<Map<String,dynamic>> known, int year) {
  final result=[for(final r in records) Map<String,dynamic>.from(r)];
  final rosterKeys=roster.map((p)=>'${p['player_key']}').toSet();
  final candidates=<String,List<Map<String,dynamic>>>{};
  for(final r in known) {
    final key='${r['player_key']}';
    if(!rosterKeys.contains(key))continue;
    if(!usageMaps(r['salary_history']).any((s)=>s['year']==year && usageMaps(s['team_shares']).length>1))continue;
    candidates.putIfAbsent(key,()=>[]).add(r);
  }
  for(final entry in candidates.entries) {
    final annual=entry.value.expand((r)=>usageMaps(r['salary_history'])).where((s)=>s['year']==year).toList();
    if(annual.map((s)=>'${s['amount']}/${s['currency']}').toSet().length!=1)continue;
    final index=result.indexWhere((r)=>r['player_key']==entry.key);
    if(index<0) { result.add({...entry.value.first,'contract_shared_by_player_key':true}); }
    else if(!usageMaps(result[index]['salary_history']).any((s)=>s['year']==year)) {
      result[index]={...result[index],'salary_history':[...usageMaps(result[index]['salary_history']),annual.first]};
    }
  }
  return result;
}
