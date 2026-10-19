import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'OrgLeague.dart';
import 'StadiumImages.dart';
import 'StrengthUsage.dart';

String catalogName(Object? value) => '$value'
    .replaceAll(RegExp(r'[\s　・･.]'), '')
    .replaceAll('髙', '高')
    .replaceAll('﨑', '崎');
String catalogFranchise(String name) {
  const aliases = {
    '巨人': ['ジャイアンツ', '巨人'],
    '阪神': ['タイガース', '阪神'],
    '中日': ['ドラゴンズ', '中日', '名古屋'],
    'ヤクルト': ['スワローズ', 'アトムズ', 'ヤクルト'],
    'DeNA': ['ベイスターズ', 'ホエールズ', '大洋', 'ロビンス'],
    '広島': ['カープ', '広島'],
    'ソフトバンク': ['ホークス', '南海', 'グレートリング'],
    '西武': ['ライオンズ', 'クリッパーズ'],
    '日本ハム': ['ファイターズ', 'フライヤーズ', 'セネタース'],
    'ロッテ': ['マリーンズ', 'オリオンズ', '大映'],
    '楽天': ['イーグルス', '楽天'],
    'オリックス': ['オリックス', 'ブレーブス', '阪急'],
    '近鉄': ['近鉄', 'パールス'],
  };
  for (final entry in aliases.entries) {
    if (entry.value.any(name.contains)) return entry.key;
  }
  return name;
}

final _catalogCache =
    <String, ({DateTime modified, Map<String, dynamic> data})>{};
Map<String, dynamic> catalogFile(String name) {
  final file = [File('data/$name.json'), File('backend/data/$name.json')]
      .where((f) => f.existsSync())
      .firstOrNull;
  if (file == null) return {};
  final modified = file.lastModifiedSync();
  final cached = _catalogCache[name];
  if (cached != null && cached.modified == modified) return cached.data;
  final data = usageMap(jsonDecode(file.readAsStringSync()));
  _catalogCache[name] = (modified: modified, data: data);
  return data;
}

List<Map<String, dynamic>> uniformGroups(List<Map<String, dynamic>> history,
    {required int year}) {
  final groups = <String, Map<String, dynamic>>{};
  for (final row in history) {
    final number = '${row['number']}';
    if (!RegExp(r'^\d{1,3}$').hasMatch(number) ||
        usageInt(number) > 300 ||
        usageInt(row['first_year']) > year) continue;
    final key = '${row['id_team']}|$number|${catalogName(row['name'])}';
    final last = usageInt(row['last_year']);
    final old = groups[key];
    if (old == null) {
      groups[key] = {...row};
    } else {
      if (last > usageInt(old['last_year']) ||
          (last == usageInt(old['last_year']) &&
              row['current_roster'] == true)) {
        final first = old['first_year'];
        groups[key] = {...row, 'first_year': first};
      }
      if (usageInt(row['first_year']) < usageInt(groups[key]!['first_year']))
        groups[key]!['first_year'] = row['first_year'];
    }
  }
  final result = groups.values.toList()
    ..sort((a, b) {
      final cmp = usageInt(b['last_year'])
          .clamp(0, year)
          .compareTo(usageInt(a['last_year']).clamp(0, year));
      return cmp != 0
          ? cmp
          : (b['current_roster'] == true ? 1 : 0)
              .compareTo(a['current_roster'] == true ? 1 : 0);
    });
  for (final row in result) {
    row['period'] =
        '${row['first_year']}–${usageInt(row['last_year']) > year ? year : row['last_year']}年';
  }
  return result;
}

List<Map<String, dynamic>> membershipCandidates(
    List<Map<String, dynamic>> career,
    List<Map<String, dynamic>> annual,
    Set<String> members) {
  const targets = {'hits': 2000, 'wins': 200, 'saves': 250};
  const statIds = {'hits': 2, 'wins': 10, 'saves': 19};
  final people = <String, Map<String, dynamic>>{};
  for (final metric in career) {
    final target = targets[metric['key']];
    if (target == null) continue;
    for (final row in usageMaps(metric['leaders'])) {
      final name = catalogName(row['name']);
      if (row['status'] != 'active' || members.contains(name)) continue;
      final value = usageInt(row['value']);
      final remaining = (target - value).clamp(0, target);
      // Annual league rows can be split by a mid-season transfer. Sum only distinct player/team records supplied by SQL.
      final pace = annual
          .where((r) =>
              catalogName(r['name']) == name &&
              usageInt(r['id_stats']) == statIds[metric['key']])
          .fold<int>(0, (s, r) => s + usageInt(r['value']));
      final estimate = remaining == 0
          ? 0.0
          : pace > 0
              ? remaining / pace
              : null;
      final candidate = <String, dynamic>{
        ...row,
        'label': metric['label'],
        'target': target,
        'remaining': remaining,
        'pace': pace,
        'estimate': estimate
      };
      final old = people[name];
      if (old == null ||
          (estimate ?? double.infinity) <
              ((old['estimate'] as num?)?.toDouble() ?? double.infinity))
        people[name] = candidate;
    }
  }
  return people.values.toList()
    ..sort((a, b) {
      final cmp = ((a['estimate'] as num?)?.toDouble() ?? double.infinity)
          .compareTo((b['estimate'] as num?)?.toDouble() ?? double.infinity);
      return cmp != 0 ? cmp : '${a['name']}'.compareTo('${b['name']}');
    });
}

class BaseballCatalog {
  static Future<Map<String, dynamic>> read(Connection conn,
      {required OrgKind org,
      required int year,
      required String section}) async {
    final base = catalogFile('baseball-catalog');
    if (section == 'hall') {
      final annual = await conn.execute('''
        SELECT DISTINCT ON (s.id_player,s.id_team,s.id_stats) p.name_full AS name,s.id_stats,s.stats AS value
        FROM (SELECT id_player,id_team,id_stats,stats FROM t_stats_player_latest WHERE \$1=EXTRACT(YEAR FROM CURRENT_DATE)::int
          UNION ALL SELECT id_player,id_team,id_stats,stats FROM t_stats_player WHERE int_year=\$1 AND \$1<>EXTRACT(YEAR FROM CURRENT_DATE)::int AND NOT COALESCE(flg_delete,false)) s
        JOIN m_player p ON p.id=s.id_player WHERE s.id_stats IN (2,10,19)
      ''', parameters: [year]);
      final combined = usageMaps(
          usageMap(catalogFile('combined_career_records')['career'])['npb']);
      final active = usageMaps(base['active_career']);
      final merged = [
        for (final metric in active)
          {
            ...metric,
            'leaders': <String, Map<String, dynamic>>{
              for (final r in usageMaps(metric['leaders']))
                catalogName(r['name']): r,
              for (final m in combined.where((m) => m['key'] == metric['key']))
                for (final r in usageMaps(m['leaders'])
                    .where((r) => r['combined'] == true))
                  catalogName(r['name']): r,
            }.values.toList()
          }
      ];
      final members = usageMaps(base['members']);
      return {
        'hall': usageMaps(base[org.code == 'npb' ? 'hall' : 'mlb_hall'])
            .where((r) => usageInt(r['year']) <= year)
            .toList(),
        'members': members,
        'candidates': year == usageInt(base['year'])
            ? membershipCandidates(
                merged,
                annual.map((r) => r.toColumnMap()).toList(),
                members.map((r) => catalogName(r['name'])).toSet())
            : [],
        'note':
            '名球会はNPB選手・元選手の団体です。会員一覧は${base['checked_at']}確認。候補は${base['year']}年の通算記録を使用し、異なる年度では予測しません。殿堂一覧には指導者・特別表彰者も含みます。'
      };
    }
    final teams = (await conn.execute(
            '''SELECT id AS id_team,name_short AS name_team,name_full,name_shortest,color_back,color_font
      FROM m_team WHERE id_league IN (${org.leagueIds.join(',')}) AND NOT COALESCE(flg_delete,false) ORDER BY id'''))
        .map((r) => r.toColumnMap())
        .toList();
    final snapshots = await conn.execute(
        'SELECT id_team,payload FROM t_team_strength WHERE int_year=\$1 AND code_org=\$2',
        parameters: [year, org.code]);
    final sourceTeams = <int, dynamic>{};
    for (final snapshot in snapshots) {
      final raw = snapshot[1];
      final payload = usageMap(raw is String ? jsonDecode(raw) : raw);
      sourceTeams[usageInt(payload['source_team_id'])] = snapshot[0];
    }
    if (snapshots.isNotEmpty) {
      final activeTeams = snapshots.map((s) => s[0]).toSet();
      teams.removeWhere((t) => !activeTeams.contains(t['id_team']));
    }
    for (final team in teams) {
      team['org'] = org.code;
    }
    if (section == 'stadiums') {
      final rows = await conn.execute(
          '''SELECT s.id,s.name_full AS name,s.name_short,s.id_team,t.name_short AS name_team
        FROM m_stadium s JOIN m_team t ON t.id=s.id_team WHERE t.id_league IN (${org.leagueIds.join(',')})
        AND NOT COALESCE(s.flg_delete,false) ORDER BY s.id_team,s.id''');
      final supplemental =
          usageMaps(catalogFile('stadium-catalog')['stadiums']);
      return {
        'stadiums': [
          for (final info
              in supplemental.where((s) => (s['org'] ?? 'npb') == org.code))
            (() {
              final team = teams
                  .where((t) => org.code == 'npb'
                      ? catalogFranchise('${t['name_full']}') ==
                          catalogFranchise('${info['team']}')
                      : t['id_team'] ==
                          sourceTeams[usageInt(info['source_team_id'])])
                  .firstOrNull;
              final matching = rows
                  .map((r) => r.toColumnMap())
                  .where((r) => r['id_team'] == team?['id_team'])
                  .toList();
              final row = matching
                  .where((r) =>
                      catalogName('${r['name']}')
                          .contains(catalogName(info['match'])) ||
                      catalogName('${r['name_short']}')
                          .contains(catalogName(info['match'])))
                  .firstOrNull;
              final name = '${info['name']}';
              var image =
                  StadiumImages.lookup(name.replaceAll('MAZDA', 'マツダ')).inside;
              if (image.isEmpty && row != null)
                image = StadiumImages.lookup('${row['name_short']}').inside;
              return {
                ...?team,
                ...info,
                'name': name,
                'name_team': team?['name_team'] ?? info['team'],
                'image': image.isEmpty ? null : image
              };
            })()
        ]
      };
    }
    final players = (await conn.execute(
            '''SELECT id,name_full AS name,name_last,uniform_number,id_team,year_retire
      FROM m_player WHERE NOT COALESCE(flg_delete,false)'''))
        .map((r) => r.toColumnMap())
        .toList();
    final officialPeople = {for(final p in usageMaps(base['npb_people'])) catalogName(p['name']):p};
    final playerByName = {for (final p in players) catalogName(p['name']): p};
    final current = <Map<String, dynamic>>[];
    for (final snapshot in snapshots) {
      final raw = snapshot[1];
      final payload = usageMap(raw is String ? jsonDecode(raw) : raw);
      sourceTeams[usageInt(payload['source_team_id'])] = snapshot[0];
      for (final p in usageMaps(payload['roster'])) {
        if ('${p['uniform_number'] ?? ''}'.isEmpty) continue;
        current.add({
          'name': p['name'],
          'number': '${p['uniform_number']}',
          'id_team': snapshot[0],
          'first_year': year,
          'last_year': year,
          'status': 'active',
          'current_roster': true
        });
      }
    }
    if (org.code == 'npb' && year == usageInt(base['year'])) {
      for (final p in players.where((p) =>
          usageInt(p['year_retire']) == 0 &&
          teams.any((t) => t['id_team'] == p['id_team']))) {
        if ('${p['uniform_number'] ?? ''}'.isEmpty) continue;
        current.add({
          'name': p['name'],
          'number': '${p['uniform_number']}',
          'id_team': p['id_team'],
          'first_year': year,
          'last_year': year,
          'status': 'active',
          'current_roster': true
        });
      }
    }
    if (org.code == 'npb' && year == usageInt(base['year'])) {
      for (final person in usageMaps(base['npb_people'])
          .where((p) => p['status'] == 'active' && p['number'] != null)) {
        final team = teams
            .where((t) =>
                catalogFranchise('${t['name_full']}') ==
                catalogFranchise('${person['team']}'))
            .firstOrNull;
        if (team != null)
          current.add({
            ...person,
            'id_team': team['id_team'],
            'first_year': year,
            'last_year': year,
            'current_roster': true
          });
      }
    }
    final source = org.code == 'npb'
        ? usageMaps(base['uniforms'])
        : usageMaps(base['mlb_uniforms']);
    final history = <Map<String, dynamic>>[];
    for (final r in source) {
      final team = teams
          .where((t) => org.code == 'npb'
              ? catalogFranchise('${t['name_team']}') ==
                  catalogFranchise('${r['team']}')
              : t['id_team'] == sourceTeams[usageInt(r['source_team_id'])])
          .firstOrNull;
      if (team == null) continue;
      history.add({...r, 'id_team': team['id_team']}..remove('source'));
    }
    final activeNames = {
      ...current.map((r) => catalogName(r['name'])),
      ...source
          .where((r) => usageInt(r['last_year']) == usageInt(base['year']))
          .map((r) => catalogName(r['name']))
    };
    for (final row in [...history, ...current]) {
      final p = playerByName[catalogName(row['name'])];
      row['surname'] = row['surname'] ??
          ('${p?['name_last'] ?? ''}'.isNotEmpty
              ? p!['name_last']
              : '${row['name']}'.split(RegExp(r'[\s　]+')).first);
      row['status'] = row['status'] != null && row['status'] != 'unknown'
          ? row['status']
          : (activeNames.contains(catalogName(row['name']))
              ? 'active'
              : usageInt(p?['year_retire']) > 0
                  ? 'retired'
                  : org.code=='npb' && officialPeople[catalogName(row['name'])]?['status']=='npb_ob' ? 'former' : 'unknown');
    }
    final grouped = uniformGroups([...history, ...current], year: year);
    final reserved = usageMaps(catalogFile('uniform-reserved')['numbers']);
    for (final row in grouped) {
      final team = teams.where((t) => t['id_team'] == row['id_team']).first;
      final mark = reserved
          .where((r) =>
              r['org'] == org.code &&
              catalogFranchise('${r['team']}') ==
                  catalogFranchise('${team['name_team']}') &&
              '${r['number']}' == '${row['number']}' &&
              usageInt(r['since']) <= year)
          .firstOrNull;
      if (mark != null) row['number_status'] = mark['status'];
      if (org.code == 'mlb' && row['number'] == '42' && year >= 1997)
        row['number_status'] = 'permanent';
    }
    for (final mark in reserved
        .where((r) => r['org'] == org.code && usageInt(r['since']) <= year)) {
      final team = teams
          .where((t) =>
              catalogFranchise('${t['name_team']}') ==
              catalogFranchise('${mark['team']}'))
          .firstOrNull;
      if (team == null ||
          grouped.any((r) =>
              r['id_team'] == team['id_team'] && r['number'] == mark['number']))
        continue;
      grouped.add({
        'id_team': team['id_team'],
        'number': mark['number'],
        'name': mark['name'],
        'surname': mark['name'],
        'status': mark['status'],
        'number_status': mark['status'],
        'period': '${mark['since']}年から指定'
      });
    }
    return {
      'teams': teams,
      'uniforms': grouped,
      'coverage':
          '${org.code == 'mlb' ? 'MLB公式歴代名簿の代表番号（番号変更の全履歴ではありません）。' : ''}登録済みの歴代着用履歴＋${year}年度名簿。空欄は未使用ではなく未収録を含みます。人数は同一選手を重複除外。履歴出典：NPB名鑑／球団名簿。'
    };
  }
}
