import '../tools/json_utils.dart';

/// Merge supplements without double-counting awards already supplied by the API.
List<Map<String, dynamic>> playerHonors(Map<String, dynamic> player) {
  final result = <String, Map<String, dynamic>>{};
  for (final raw in [
    ...listMapFromJson(player['achievements']),
    ...listMapFromJson(player['additional_achievements'])
  ]) {
    var label = '${raw['label']}';
    label = label
        .replaceAll('沢村栄治賞', '沢村賞')
        .replaceAll('ゴールデン・グラブ', 'ゴールデングラブ')
        .replaceAll('WBC優勝レギュラー', 'WBC優勝メンバー（レギュラー級）');
    label = label.replaceAllMapped(
        RegExp(r'(AL|NL)?\s*Cy Young(?: Award)?', caseSensitive: false),
        (m) =>
            '${m[1] == 'AL' ? 'ア・リーグ ' : m[1] == 'NL' ? 'ナ・リーグ ' : ''}サイ・ヤング賞');
    final normalized = label.replaceAll(RegExp(r'[\s・]'), '');
    final key = '${raw['year']}/$normalized';
    result[key] = {...raw, 'label': label};
  }
  final perfectYears = result.values
      .where((a) => a['label'] == '完全試合')
      .map((a) => a['year'])
      .toSet();
  return result.values
      .where((a) =>
          !(a['label'] == 'ノーヒットノーラン' && perfectYears.contains(a['year'])))
      .toList();
}
