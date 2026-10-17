import 'package:html/parser.dart' as html;
import 'RecordCatalog.dart';
import 'StrengthUsage.dart';

List<Map<String, dynamic>> parseNpbRecord(String body, {required bool career}) {
  final result = <Map<String, dynamic>>[];
  for (final row in html.parse(body).querySelectorAll('tr.hilist')) {
    final cells = row.querySelectorAll('td');
    final name = row.querySelector('.hiplayer')?.text.trim();
    if (name == null || cells.length < 5) continue;
    final rank = int.tryParse(cells[0].text.trim());
    if (rank == null) continue;
    result.add({
      'name': name,
      'rank': rank,
      'value': cells[3].text.trim(),
      'status': career
          ? (cells[1].text.contains('*') ? 'active' : 'retired')
          : 'unknown',
      if (!career) 'team': cells[2].text.replaceAll(RegExp(r'[()]'), '').trim(),
      if (!career)
        'year': int.tryParse(cells[4].text.replaceAll(RegExp(r'[^0-9]'), '')),
      if (career) 'period': cells[4].text.trim(),
    });
  }
  if (result.isEmpty) throw const FormatException('公式記録表を確認できません');
  return career
      ? result.where((p) => usageInt(p['rank']) <= 50).toList()
      : result.where((p) => p['rank'] == 1).toList();
}

List<Map<String, dynamic>> parseMlbRecord(
    Map<String, dynamic> data, RecordMetric metric,
    {required bool career}) {
  final splits = [
    for (final stat in usageMaps(data['stats'])) ...usageMaps(stat['splits'])
  ];
  if (splits.isEmpty) throw const FormatException('MLB公式記録を確認できません');
  final best = usageMap(splits.first['stat'])[metric.mlb];
  final result = [
    for (final split in splits)
      if (career || usageMap(split['stat'])[metric.mlb] == best)
        {
          'name': usageMap(split['player'])['fullName'],
          'player_id': usageMap(split['player'])['id'],
          'value': usageMap(split['stat'])[metric.mlb],
          'status': usageMap(split['player'])['active'] == true
              ? 'active'
              : usageMap(split['player'])['active'] == false
                  ? 'retired'
                  : 'unknown',
          if (!career) 'year': int.tryParse('${split['season']}'),
          if (!career) 'team': usageMap(split['team'])['name'],
        }
  ];
  if (career) {
    var rank = 1;
    for (var i = 0; i < result.length; i++) {
      if (i == 0 || '${result[i]['value']}' != '${result[i - 1]['value']}') rank = i + 1;
      result[i]['rank'] = rank;
    }
    return result.where((p) => usageInt(p['rank']) <= 50).toList();
  }
  return result;
}
