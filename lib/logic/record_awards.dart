/// Normalize equivalent award names without combining distinct selection rules.
String recordAwardLabel(Object? value) {
  final label = '${value ?? ''}'
      .replaceAll(RegExp(r'[\s　]'), '')
      .replaceAll('(', '（')
      .replaceAll(')', '）');
  if (RegExp(r'^(MVP|最優秀選手)(賞)?（[春秋]）$').hasMatch(label)) {
    return 'リーグMVP${label.substring(label.indexOf('（'))}';
  }
  if (label.startsWith('ベストナイン')) {
    return label.replaceFirst('ベストナイン賞', 'ベストナイン');
  }
  if (label.startsWith('ベストDH')) {
    return label.replaceFirst('ベストDH賞', 'ベストDH');
  }
  return const {
        '沢村栄治賞': '沢村賞',
        'MVP': 'リーグMVP',
        '最優秀選手': 'リーグMVP',
        '最優秀選手賞': 'リーグMVP',
        '最優秀新人': '新人王',
        '最優秀新人賞': '新人王',
        '最多安打者': '最多安打',
        '最多安打者賞': '最多安打',
        '最多本塁打者': '本塁打王',
        '最多本塁打者賞': '本塁打王',
        '最多本塁打': '本塁打王',
        '最多打点者': '打点王',
        '最多打点者賞': '打点王',
        '最多打点': '打点王',
        '最多盗塁者': '盗塁王',
        '最多盗塁者賞': '盗塁王',
        '最多盗塁': '盗塁王',
        '最高出塁率者': '最高出塁率',
        '最高出塁率者賞': '最高出塁率',
        '最優秀防御率投手': '最優秀防御率',
        '最優秀防御率投手賞': '最優秀防御率',
        '最多勝': '最多勝利',
        '最多勝利投手': '最多勝利',
        '最多勝利投手賞': '最多勝利',
        '最多セーブ投手': '最多セーブ',
        '最多セーブ投手賞': '最多セーブ',
        '最優秀中継ぎ投手': '最優秀中継ぎ',
        '最優秀中継ぎ投手賞': '最優秀中継ぎ',
        '最多三振奪取投手': '最多奪三振',
        '最多三振奪取投手賞': '最多奪三振',
        '最多奪三振投手': '最多奪三振',
        '最多奪三振投手賞': '最多奪三振',
        '勝率第一位投手': '最高勝率',
        '勝率第1位投手': '最高勝率',
        '最優秀投手（13勝以上の勝率第1位投手）': '最高勝率',
        'カムバック選手賞': 'カムバック賞',
        '新人選手特別賞': '新人特別賞',
      }[label] ??
      label;
}

List<Map<String, dynamic>> normalizeRecordAwards(
    Iterable<Map<String, dynamic>> categories) {
  final grouped = <String, Map<String, dynamic>>{};
  String name(Object? value) =>
      '${value ?? ''}'.replaceAll(RegExp(r'[\s　・･.]'), '');
  for (final category in categories) {
    final label = recordAwardLabel(category['label']);
    final group = grouped.putIfAbsent(
        label,
        () =>
            {...category, 'label': label, 'players': <Map<String, dynamic>>[]});
    final players = group['players'] as List<Map<String, dynamic>>;
    for (final raw in category['players'] as List? ?? const []) {
      final player = Map<String, dynamic>.from(raw as Map);
      final index = players.indexWhere((p) =>
          p['id_player'] != null && player['id_player'] != null
              ? '${p['id_player']}' == '${player['id_player']}'
              : name(p['name']).isNotEmpty &&
                  name(p['name']) == name(player['name']) &&
                  name(p['team']) == name(player['team']));
      if (index < 0) {
        players.add(player);
      } else {
        final existing = players[index];
        final numeric = num.tryParse('${existing['value']}') != null;
        players[index] = {
          ...existing,
          ...player,
          if (numeric) 'value': existing['value'],
          if (numeric && existing['unit'] != null) 'unit': existing['unit'],
        };
      }
    }
  }
  return grouped.values.toList();
}

String recordShortestTeam(Map<String, dynamic> row, {bool preferCanonical = false}) {
  final explicit =
      '${row['name_shortest'] ?? row['team_shortest'] ?? ''}'.trim();
  if (explicit.isNotEmpty && !preferCanonical) return explicit == 'オイ' ? 'オ' : explicit;
  final team = '${row['team'] ?? ''}';
  const names = {
    '巨人': '巨',
    '読売': '巨',
    '阪神': '神',
    'DeNA': 'De',
    '横浜': '横',
    '広島': '広',
    '中日': '中',
    'ヤクルト': 'ヤ',
    'ソフトバンク': 'ソ',
    '日本ハム': '日',
    '西武': '西',
    '楽天': '楽',
    'オリックス': 'オ',
    'ロッテ': 'ロ',
    'オイシックス': 'オ',
    'ハヤテ': 'ハ',
    'くふう': 'ハ',
  };
  for (final entry in names.entries) {
    if (team.contains(entry.key)) return entry.value;
  }
  return explicit.isNotEmpty ? explicit : team;
}
