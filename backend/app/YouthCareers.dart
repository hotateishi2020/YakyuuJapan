import 'dart:convert';
import 'dart:io';
import 'CareerEvidence.dart';
import 'StrengthUsage.dart';

final _youthEvidence = usageMaps(jsonDecode(File.fromUri(
    Platform.script.resolve('data/youth_career_evidence.json')).readAsStringSync()));

List<Map<String, dynamic>> withYouthCareers(Map<String, dynamic> player,
    List<Map<String, dynamic>> history) {
  final name = evidenceName('${player['name'] ?? ''}');
  final entries = [
    ...history,
    for (final row in _youthEvidence)
      if (evidenceName('${row['name']}') == name)
        {'category': row['category'], 'team': row['team'],
          'source_url': row['source_url'], 'detail': '協会公式の出身選手一覧で確認した所属歴。'},
  ];
  return {for (final entry in entries) '${entry['category']}:${entry['team']}': entry}.values.toList();
}
