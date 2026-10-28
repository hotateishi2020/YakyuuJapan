String _text(dynamic v) => v == null ? '' : '$v'.trim();
String _day(dynamic v) => _text(v).split(RegExp('[ T]')).first;
String _venueKey(dynamic v) => _text(v).toLowerCase().replaceAll(RegExp(r'[\s　・･]'), '').replaceAll('ｈｏｋｋａｉｄｏ', 'hokkaido');

/// The stage overrides the league for postseason games.
String todayMapGameHeader(Map<String, dynamic> game) {
  final code = _text(game['code_game']).toUpperCase();
  final home = int.tryParse('${game['id_league_home']}');
  final away = int.tryParse('${game['id_league_away']}');
  const stages = {'CS': 'CS 1st STAGE', 'CS1': 'CS 1st STAGE', 'CS2': 'CS FINAL STAGE', 'CSF': 'CS FINAL STAGE', 'JS': '日本シリーズ', 'WS': 'ワールドシリーズ', 'ALCS': 'ALCS', 'NLCS': 'NLCS', 'ALDS': 'ALDS', 'NLDS': 'NLDS', 'ALWC': 'ALWC', 'NLWC': 'NLWC'};
  if (stages.containsKey(code)) return stages[code]!;
  if (const {'WC', 'DS', 'LCS'}.contains(code)) {
    return home == 3 && away == 3
        ? 'AL${code == 'LCS' ? 'CS' : code}'
        : home == 4 && away == 4
            ? 'NL${code == 'LCS' ? 'CS' : code}'
            : code;
  }
  if (home == away) return const {1: 'セ・リーグ', 2: 'パ・リーグ', 3: 'ア・リーグ', 4: 'ナ・リーグ'}[home] ?? '試合';
  if ({1, 2}.contains(home) && {1, 2}.contains(away)) return '交流戦';
  if ({3, 4}.contains(home) && {3, 4}.contains(away)) return 'インターリーグ';
  return '試合';
}

/// Unknown venues remain unlocated; never substitute a team's home stadium.
List<Map<String, dynamic>> todayMapEntries(Map<String, dynamic> data) {
  final today = _day(data['date']);
  List<Map<String, dynamic>> maps(dynamic v) => v is List ? v.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList() : [];
  final venues = maps(data['venues']);
  final result = <String, Map<String, dynamic>>{};
  void add(Map<String, dynamic> row) {
    final label = _text(row['venue']);
    final key = _venueKey(label);
    final exact = venues.where((v) => [v['name'], v['match'], ...(v['aliases'] as List? ?? [])].any((s) => key.isNotEmpty && _venueKey(s) == key)).toList();
    final partial = exact.isNotEmpty ? exact : venues.where((v) => [v['name'], v['match'], ...(v['aliases'] as List? ?? [])].any((s) => key.length >= 4 && _venueKey(s).length >= 4 && (_venueKey(s).contains(key) || key.contains(_venueKey(s))))).toList();
    final location = partial.length == 1 ? partial.single : <String, dynamic>{};
    final lat = num.tryParse('${row['latitude'] ?? location['latitude']}');
    final lon = num.tryParse('${row['longitude'] ?? location['longitude']}');
    final valid = lat != null && lon != null && lat.isFinite && lon.isFinite && lat.abs() <= 85 && lon.abs() <= 180;
    final id = '${row['kind']}|${row['title']}|$label|${row['time']}';
    result[id] = {...row, if (valid) 'latitude': lat, if (valid) 'longitude': lon, 'located': valid};
  }

  for (final game in maps(data['games'])) {
    if (_day(game['date_game'] ?? game['date']) != today || RegExp('中止|延期|未実施').hasMatch(_text(game['state']))) {
      continue;
    }
    add({'kind': '試合', 'header': todayMapGameHeader(game), 'title': '${game['name_team_away']} vs ${game['name_team_home']}', 'venue': game['name_stadium'] ?? game['venue'], 'time': game['time_game'] ?? '', 'latitude': game['latitude'], 'longitude': game['longitude']});
  }
  for (final event in maps(data['events'])) {
    final from = _day(event['date_from_temp'] ?? event['date_from']);
    final to = _day(event['date_to']).isEmpty ? from : _day(event['date_to']);
    final title = _text(event['title_event'] ?? event['title']);
    final code = _text(event['calendar_code']);
    if (from.isEmpty || from.compareTo(today) > 0 || to.compareTo(today) < 0 || event['calendar_kind'] == 'ticket' || RegExp('中止|延期').hasMatch(title)) {
      continue;
    }
    final kind = RegExp('自主トレ').hasMatch(title + code)
        ? '自主トレ'
        : RegExp('キャンプ|camp').hasMatch(title + code)
            ? 'キャンプ'
            : RegExp('トーク|talk').hasMatch(title + code)
                ? 'トークショー'
                : RegExp('来日|visit').hasMatch(title + code)
                    ? '来日イベント'
                    : RegExp('式典|表彰|AWARD|awards|セレモニー|入団会見').hasMatch(title + code)
                        ? '式典'
                        : RegExp('試合|マッチ|紅白|オールスター|ファン|festival|game|tryout').hasMatch(title + code)
                            ? 'イベント'
                            : '';
    if (kind.isEmpty) continue;
    final detailLines = _text(event['detail']).split('\n');
    final legacyVenue = detailLines.length >= 4 && RegExp(r'^20\d{2}-').hasMatch(detailLines.first) ? detailLines[2] : '';
    add({'kind': kind, 'title': title, 'venue': event['venue'] ?? event['location'] ?? legacyVenue, 'time': event['start_time'] ?? '', 'detail': event['detail'] ?? '', 'latitude': event['latitude'], 'longitude': event['longitude'], 'source_url': event['source_url']});
  }
  return result.values.toList();
}
