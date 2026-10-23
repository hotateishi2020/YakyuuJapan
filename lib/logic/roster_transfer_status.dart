import 'predict_groups.dart';
import 'strength_usage.dart';

/// 退団の確定を優先し、開幕前からの所属選手と未確定の噂は在籍に残す。
int rosterTransferBlock(
    Map<String, dynamic> player, Map<String, dynamic> team, int year) {
  if (rosterDepartureLabel(player) != null) return 2;
  if (player['new_arrival'] != true) return 1;
  final arrivalYear = usageInt(player['arrival_year']);
  if (arrivalYear != year && arrivalYear != year + 1) return 1;
  if (arrivalYear == year + 1) return 0;
  if (player['arrival_period'] == '昨オフ') return 1;
  final arrival = DateTime.tryParse('${player['arrival_as_of']}');
  final npb = [1, 2].contains(usageInt(team['id_league'])) ||
      (usageInt(team['id_team']) >= 1 && usageInt(team['id_team']) <= 12);
  final opening = (npb ? npbSeasonOpeningDate(year) : null) ??
      DateTime.tryParse('${team['opening_date']}');
  if (arrival != null &&
      (arrival.year < year || (opening != null && !arrival.isAfter(opening)))) {
    return 1;
  }
  return 0;
}

int compareRosterUsage(
    Map<String, dynamic> a, Map<String, dynamic> b, Map<String, dynamic> team) {
  final aLevel = rosterMainLevel(a), bLevel = rosterMainLevel(b);
  final level = (aLevel == 0 ? 5 : aLevel).compareTo(bLevel == 0 ? 5 : bLevel);
  if (level != 0) return level;
  final workload = (rosterWorkload(b, team, bLevel) ?? -1)
      .compareTo(rosterWorkload(a, team, aLevel) ?? -1);
  return workload != 0 ? workload : '${a['name']}'.compareTo('${b['name']}');
}

/// 守備位置よりも、移籍加入・新人ドラフト・育成ドラフトの区分を優先する。
int rosterArrivalGroupPriority(Map<String, dynamic> player) {
  final method = '${player['move_method'] ?? ''}'.toUpperCase();
  final type = '${player['arrival_draft_type'] ?? ''}';
  if (RegExp(r'FA|ＦＡ|トレード|現役ドラフト').hasMatch(method) || type.contains('現役')) return 0;
  if (type.contains('育成') || method.contains('育成ドラフト')) return 2;
  return 1;
}

/// 移籍加入を先頭にし、支配下・育成の新人は指名順位を維持する。
int compareRosterArrivalDraft(
    Map<String, dynamic> a, Map<String, dynamic> b, Map<String, dynamic> team) {
  (int, int) order(Map<String, dynamic> p) {
    if (rosterArrivalGroupPriority(p) == 0) return (0, 0);
    final method = '${p['move_method'] ?? ''}';
    final match = RegExp(r'(?:新人|育成|現役)?ドラフト\s*(\d+)位').firstMatch(method);
    final rank = usageInt(p['arrival_draft_rank']);
    if (rank <= 0 && match == null) return (3, 0);
    final type = '${p['arrival_draft_type'] ?? method}';
    return (type.contains('育成') ? 2 : 1,
        rank > 0 ? rank : int.parse(match!.group(1)!));
  }
  final ao = order(a), bo = order(b);
  final type = ao.$1.compareTo(bo.$1);
  if (type != 0) return type;
  final rank = ao.$2.compareTo(bo.$2);
  return rank != 0 ? rank : compareRosterUsage(a, b, team);
}

List<Map<String, dynamic>> rosterWithDraftArrivals(
    List<Map<String, dynamic>> roster,
    List<Map<String, dynamic>> picks,
    Map<String, dynamic> team,
    int year) {
  String normalize(dynamic value) => '$value'.replaceAll(RegExp(r'[\s　]+'), '');
  const aliases = {
    '読売ジャイアンツ': '巨人',
    '阪神タイガース': '阪神',
    '横浜DeNAベイスターズ': 'DeNA',
    '広島東洋カープ': '広島',
    '東京ヤクルトスワローズ': 'ヤクルト',
    '中日ドラゴンズ': '中日',
    '福岡ソフトバンクホークス': 'ソフトバンク',
    '北海道日本ハムファイターズ': '日本ハム',
    '千葉ロッテマリーンズ': 'ロッテ',
    'オリックス・バファローズ': 'オリックス',
    '埼玉西武ライオンズ': '西武',
    '東北楽天ゴールデンイーグルス': '楽天'
  };
  final teamName = aliases[team['name_team']] ?? team['name_team'];
  final result = [...roster];
  for (final pick in picks) {
    if (pick['team'] != teamName ||
        RegExp('拒否|入団せず|辞退').hasMatch('${pick['status']}')) {
      continue;
    }
    final existing = result.indexWhere((p) => normalize(p['name']) == normalize(pick['name']));
    if (existing >= 0) {
      final player = result[existing];
      if (player['new_arrival'] == true && usageInt(player['arrival_year']) >= year) {
        result[existing] = {...player,
          'arrival_draft_rank': pick['rank'],
          'arrival_draft_type': pick['type'],
        };
      }
      continue;
    }
    final active = pick['type'] == '現役';
    result.add({
      'name': pick['name'],
      'player_key': 'draft:$year:$teamName:${normalize(pick['name'])}',
      'position_group': pick['position'],
      'arrival_draft_rank': pick['rank'],
      'arrival_draft_type': pick['type'],
      'new_arrival': true,
      'arrival_year': year + 1,
      'move_method': active
          ? '現役ドラフト'
          : '${pick['type'] == '育成' ? '育成' : '新人'}ドラフト${pick['rank']}位',
      'move_method_year': year,
      'draft_status': pick['status'] ?? (active ? '移籍確定' : '指名'),
      'previous_team': {'name': pick['from'], 'label': pick['from']},
    });
  }
  return result;
}
