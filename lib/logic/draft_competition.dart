/// 同じ年度・指名区分の抽選落選記録から、競合に参加した球団を対応付ける。
List<Map> draftPicksWithCompetition(List<Map> picks) {
  String normalize(String value) => value.replaceAll(RegExp(r'[\s\u3000]'), '').replaceAll('髙', '高').replaceAll('﨑', '崎');
  final contenders = <String, Set<String>>{};
  String key(Map pick, String name) => '${pick['type'] ?? ''}:${normalize(name)}';
  for (final pick in picks) {
    for (final part in '${pick['note'] ?? ''}'.split('・')) {
      if (!part.endsWith('×')) continue;
      final name = part.substring(0, part.length - 1);
      contenders.putIfAbsent(key(pick, name), () => {}).add('${pick['team']}');
    }
  }
  return [for (final pick in picks) (() {
    final others = contenders[key(pick, '${pick['name']}')] ?? <String>{};
    final teams = others.isEmpty ? <String>[] : <String>{'${pick['team']}', ...others}.toList();
    return <String, dynamic>{
      ...pick,
      'competition_teams': teams,
      'competition': pick['competition'] ?? (teams.length > 1 ? teams.length : null),
    };
  })()];
}

/// 競合数と抽選落選回数は別情報。再入札でも競合した場合は両方を表示する。
List<String> draftNominationLabels(Map result) {
  if ('${result['rank']}' != '1' || result['type'] == '育成') return const [];
  if (!result.containsKey('note') && !result.containsKey('competition')) return const [];
  final count = int.tryParse('${result['competition']}') ?? 0;
  final losses = '${result['note'] ?? ''}'.split('・').where((part) => part.trim().endsWith('×')).length;
  return [
    if (count > 1) '$count球団競合',
    if (losses == 0 && count <= 1) '単独指名',
    if (losses > 0) '${List.filled(losses, 'ハズレ').join()}1位',
  ];
}
