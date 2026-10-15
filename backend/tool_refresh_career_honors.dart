import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'app/CareerEvidence.dart';
import 'app/PlayerAchievements.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.firstOrNull ?? '2026');
  final client = http.Client(), errors = <String>[];
  final cache = Directory('/tmp/koko-achievements-$year')
    ..createSync(recursive: true);
  Future<String> get(String url) async {
    final file = File('${cache.path}/${Uri.encodeComponent(url)}');
    if (file.existsSync()) return file.readAsStringSync();
    final r =
        await client.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}: $url');
    final text = utf8.decode(r.bodyBytes);
    file.writeAsStringSync(text);
    return text;
  }

  final rows = await Postgres.withConnection((c) => c.execute(
      'SELECT code_org,id_team,payload FROM t_team_strength WHERE int_year=\$1',
      parameters: [year]));
  final teams = [
    for (final r in rows)
      {
        'org': r[0],
        'id_team': r[1],
        'team': usageMap(r[2] is String ? jsonDecode(r[2] as String) : r[2])
      }
  ];
  final roster = [
    for (final t in teams) ...usageMaps(usageMap(t['team'])['roster'])
  ];
  final byKey = {for (final p in roster) '${p['player_key']}': p};
  final updates = <String, Map<String, dynamic>>{};
  final aliases = <String, String>{
    'Shohei Ohtani': '大谷翔平',
    'Yoshinobu Yamamoto': '山本由伸',
    'Yu Darvish': 'ダルビッシュ有',
    'Kodai Senga': '千賀滉大',
    'Shota Imanaga': '今永昇太',
    'Seiya Suzuki': '鈴木誠也',
    'Masataka Yoshida': '吉田正尚',
    'Yusei Kikuchi': '菊池雄星',
    'Tomoyuki Sugano': '菅野智之',
    'Roki Sasaki': '佐々木朗希',
    'Yuki Matsui': '松井裕樹',
    'Shintaro Fujinami': '藤浪晋太郎',
    'Kenta Maeda': '前田健太',
    'Shinnosuke Ogasawara': '小笠原慎之介',
    'Munetaka Murakami': '村上宗隆',
    'Kazuma Okamoto': '岡本和真',
    'Tatsuya Imai': '今井達也',
    'Lars Nootbaar': 'ラーズ・ヌートバー',
  };
  final byName = <String, Set<String>>{};
  for (final p in roster) {
    byName
        .putIfAbsent(
            evidenceName(aliases[p['name']] ?? '${p['name']}'), () => {})
        .add('${p['player_key']}');
  }
  void add(String key, Map<String, dynamic> badge) {
    if (!byKey.containsKey(key) || usageInt(badge['year']) > year) return;
    final update = updates.putIfAbsent(key, () => {});
    (update.putIfAbsent(
            'additional_achievements', () => <Map<String, dynamic>>[]) as List)
        .add(badge);
  }

  void addName(String name, Map<String, dynamic> badge) {
    final keys = byName[evidenceName(name)] ?? {};
    if (keys.length == 1) add(keys.single, badge);
  }

  // Career paths and first-round selection from NPB's labeled biographies.
  final npb =
      roster.where((p) => '${p['player_key']}'.startsWith('npb:')).toList();
  for (var i = 0; i < npb.length; i += 6) {
    await Future.wait(npb.skip(i).take(6).map((p) async {
      final key = '${p['player_key']}',
          url = 'https://npb.jp/bis/players/${p['source_player_id']}.html';
      try {
        final parsed = npbCareerEvidence(await get(url), url);
        if (parsed['career_history'] != null)
          updates.putIfAbsent(key, () => {})['career_history'] =
              parsed['career_history'];
        for (final b in usageMaps(parsed['badges'])) add(key, b);
      } catch (e) {
        errors.add('$key $e');
      }
    }));
  }
  print('NPBプロフィール ${updates.length}人');
  // Only published awards, not votes or nominees. Future unpublished years are skipped.
  for (var y = 2000; y <= year; y += 4) {
    await Future.wait([
      for (var n = y; n < y + 4 && n <= year; n++)
        for (final type in ['glove', 'shosawa'])
          () async {
            final url = 'https://npb.jp/award/$n/$type.html';
            try {
              for (final e in namedAwardEvidence(await get(url), n, url,
                  glove: type == 'glove')) {
                if (e['player_key'] != null &&
                    byKey.containsKey(e['player_key']))
                  add(e['player_key'], e['badge']);
                else
                  addName(e['name'], e['badge']);
              }
            } catch (e) {
              errors.add('$e');
            }
          }()
    ]);
  }
  print('NPB受賞データ取得完了');
  // MLB draft data identifies the actual school at selection; do not invent earlier schools.
  for (var y = 2000; y <= year; y += 3) {
    await Future.wait([
      for (var n = y; n < y + 3 && n <= year; n++)
        () async {
          final url = 'https://statsapi.mlb.com/api/v1/draft/$n?limit=5000';
          try {
            final data = usageMap(jsonDecode(await get(url)));
            for (final round in usageMaps(usageMap(data['drafts'])['rounds']))
              for (final pick in usageMaps(round['picks'])) {
                final key = 'mlb:${usageMap(pick['person'])['id']}';
                if (!byKey.containsKey(key)) continue;
                final school = usageMap(pick['school']),
                    code = '${school['schoolClass'] ?? ''}';
                final category = code.startsWith('HS')
                    ? '高校'
                    : RegExp(r'4YR|JC|2YR|COL').hasMatch(code)
                        ? '大学'
                        : null;
                if (category != null && school['name'] != null) {
                  final paths = updates.putIfAbsent(key, () => {}).putIfAbsent(
                      'career_history', () => <Map<String, dynamic>>[]) as List;
                  if (!paths.any((p) => p['team'] == school['name']))
                    paths.add({
                      'category': category,
                      'team': school['name'],
                      'source_url': url,
                      'detail': '$n年MLBドラフト時の所属校（${school['country'] ?? ''}）。'
                    });
                }
                if (pick['pickRound'] == '1')
                  add(
                      key,
                      achievement('MLBドラフト1巡目', n, url,
                          kind: 'draft',
                          detail:
                              '全体${pick['pickNumber']}番目。指名時の記録で、入団を意味しません。'));
              }
          } catch (e) {
            errors.add('$e');
          }
        }()
    ]);
  }
  print('MLB出身校取得完了');
  final representativePages = [
    (2021, 'tokyo2020', '東京五輪'),
    (2023, 'wbc', 'WBC'),
    (2017, 'wbc', 'WBC'),
    (2019, 'premier12', 'プレミア12'),
    (2024, 'premier12', 'プレミア12'),
    (2026, 'wbc', 'WBC'),
  ];
  for (final e in representativePages) {
    if (e.$1 > year) continue;
    final url =
        'https://www.japan-baseball.jp/jp/team/topteam/${e.$1}/${e.$2}/player.html';
    try {
      final doc = html.parse(await get(url));
      for (final row in doc.querySelectorAll('tr')) {
        if (!['投手', '捕手', '内野手', '外野手']
            .contains(row.querySelector('.position')?.text.trim())) continue;
        final name = row.querySelector('.name')?.text.trim();
        if (name == null) continue;
        addName(
            name,
            achievement('侍ジャパン代表選出（${e.$3}）', e.$1, url,
                kind: 'national_team', detail: '公式のトップチーム大会出場選手一覧に掲載。'));
        final keys = byName[evidenceName(name)] ?? {};
        if (keys.length == 1 &&
            keys.single.startsWith('mlb:') &&
            updates[keys.single]?['career_history'] == null) {
          var a = row.parent;
          while (a != null && a.localName != 'a') {
            a = a.parent;
          }
          final href = a?.attributes['href'];
          if (href != null && href.contains('/profile/')) {
            final profileUrl = Uri.parse(url).resolve(href).toString();
            final profile =
                npbCareerEvidence(await get(profileUrl), profileUrl);
            if (profile['career_history'] != null) {
              updates.putIfAbsent(keys.single, () => {})['career_history'] = [
                for (final c in usageMaps(profile['career_history']))
                  {...c, 'detail': '侍ジャパン公式プロフィールの経歴。'}
              ];
            }
          }
        }
      }
    } catch (e) {
      errors.add('$e');
    }
  }
  final callup =
      'https://www.japan-baseball.jp/jp/games/jpnned2025/player_jpn.html';
  if (year >= 2025)
    try {
      final doc = html.parse(await get(callup));
      for (final a in doc.querySelectorAll('a[href*="/profile/"]')) {
        final text = evidenceName(a.querySelector('dl.name dt')?.text ?? '');
        for (final e in byName.entries)
          if (e.key.length >= 3 && text == e.key && e.value.length == 1) {
            add(
                e.value.single,
                achievement('侍ジャパン招集（オランダ戦）', 2025, callup,
                    kind: 'callup', detail: '侍ジャパンシリーズ2025の公式出場選手一覧に掲載。'));
          }
      }
    } catch (e) {
      errors.add('$e');
    }
  // A transparent usage threshold, rather than granting every squad member a regular badge.
  for (final event in [
    (
      2021,
      ['20210728', '20210731', '20210802', '20210804', '20210807'],
      '東京五輪金メダルメンバー（レギュラー級）',
      3,
      'https://www.japan-baseball.jp/jp/games/tokyo2020/'
    ),
  ]) {
    if (year < event.$1) continue;
    final starts = <String, int>{},
        pitching = <String, int>{},
        pitchingStarts = <String, int>{};
    var complete = true;
    for (final date in event.$2) {
      final url =
          'https://www.japan-baseball.jp/jp/team/topteam/score/${date}_1/';
      try {
        final doc = html.parse(await get(url));
        var found = false;
        for (final div in doc.querySelectorAll(
            '#startingOrder div.top, #startingOrder div.bottom')) {
          if (div.querySelector('h5')?.text.trim() != '日本') continue;
          found = true;
          for (final name in div.querySelectorAll('dd.player')) {
            final key = evidenceName(name.text);
            starts[key] = (starts[key] ?? 0) + 1;
          }
        }
        if (!found) throw StateError('Japan starting lineup missing: $url');
        final table = html.parse(await get('${url}table.html'));
        for (final heading in table.querySelectorAll('h5')) {
          if (heading.text.trim() != '日本') continue;
          var sibling = heading.nextElementSibling;
          while (sibling != null && sibling.localName != 'h5') {
            for (final grid in sibling.querySelectorAll('table')) {
              if (!grid
                  .querySelectorAll('thead th')
                  .any((h) => h.text.trim() == '投手')) continue;
              final pitchers = grid.querySelectorAll('tbody td.player');
              for (var i = 0; i < pitchers.length; i++) {
                final name = evidenceName(pitchers[i].text);
                pitching[name] = (pitching[name] ?? 0) + 1;
                if (i == 0)
                  pitchingStarts[name] = (pitchingStarts[name] ?? 0) + 1;
              }
            }
            sibling = sibling.nextElementSibling;
          }
        }
      } catch (e) {
        complete = false;
        errors.add('$e');
      }
    }
    if (!complete) continue;
    for (final name in {...starts.keys, ...pitching.keys}) {
      if ((starts[name] ?? 0) >= event.$4 ||
          (pitchingStarts[name] ?? 0) >= 2 ||
          (pitching[name] ?? 0) >= 3) {
        addName(
            name,
            achievement(event.$3, event.$1, event.$5,
                kind: 'championship',
                detail:
                    '公式の全${event.$2.length}試合を集計：野手先発${starts[name] ?? 0}試合、投手先発${pitchingStarts[name] ?? 0}試合、登板${pitching[name] ?? 0}試合。野手${event.$4}先発以上、投手2先発または3登板以上をレギュラー級とするアプリ独自基準。'));
      }
    }
  }
  if (year >= 2023) {
    const scheduleUrl =
        'https://statsapi.mlb.com/api/v1/schedule?sportId=51&teamId=843&season=2023';
    try {
      final schedule = usageMap(jsonDecode(await get(scheduleUrl)));
      final games = [
        for (final d in usageMaps(schedule['dates'])) ...usageMaps(d['games'])
      ];
      if (games.length != 7 ||
          games.any(
              (g) => usageMap(g['status'])['abstractGameState'] != 'Final'))
        throw StateError('Incomplete 2023 WBC schedule');
      final totals = <String, Map<String, int>>{};
      for (final game in games) {
        final url =
            'https://statsapi.mlb.com/api/v1/game/${game['gamePk']}/boxscore';
        final box = usageMap(jsonDecode(await get(url)));
        for (final side in usageMap(box['teams']).values) {
          final team = usageMap(side);
          if (usageMap(team['team'])['id'] != 843) continue;
          for (final v in usageMap(team['players']).values) {
            final p = usageMap(v), id = '${usageMap(p['person'])['id']}';
            final total = totals.putIfAbsent(
                id, () => {'bat': 0, 'start': 0, 'pitch': 0});
            if (p['battingOrder'] != null &&
                '${p['battingOrder']}'.endsWith('00'))
              total['bat'] = total['bat']! + 1;
            final pitching = usageMap(usageMap(p['stats'])['pitching']);
            total['start'] =
                total['start']! + usageInt(pitching['gamesStarted']);
            if (usageInt(pitching['pitchesThrown']) > 0 ||
                usageInt(pitching['battersFaced']) > 0)
              total['pitch'] = total['pitch']! + 1;
          }
        }
      }
      final ids = totals.entries
          .where((e) =>
              e.value['bat']! >= 4 ||
              e.value['start']! >= 2 ||
              e.value['pitch']! >= 3)
          .map((e) => e.key)
          .toList()
        ..sort();
      final peopleUrl =
          'https://statsapi.mlb.com/api/v1/people?personIds=${ids.join(',')}';
      for (final person
          in usageMaps(usageMap(jsonDecode(await get(peopleUrl)))['people'])) {
        final v = totals['${person['id']}']!;
        final badge = achievement('WBC優勝メンバー（レギュラー級）', 2023, scheduleUrl,
            kind: 'championship',
            detail:
                '公式の全7試合を集計：野手先発${v['bat']}試合、投手先発${v['start']}試合、登板${v['pitch']}試合。野手4先発以上、投手2先発または3登板以上をレギュラー級とするアプリ独自基準。');
        add('mlb:${person['id']}', badge);
        final matching = npb
            .where((p) =>
                p['date_birth'] == person['birthDate'] &&
                usageMaps(updates['${p['player_key']}']
                        ?['additional_achievements'])
                    .any((a) =>
                        a['year'] == 2023 && a['label'] == '侍ジャパン代表選出（WBC）'))
            .toList();
        if (matching.length == 1)
          add('${matching.single['player_key']}', badge);
      }
    } catch (e) {
      errors.add('$e');
    }
  }
  const nohitUrl = 'https://npb.jp/history/alltime/nohitnorun.html';
  try {
    final doc = html.parse(await get(nohitUrl));
    for (final row in doc.querySelectorAll('tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.isEmpty) continue;
      final match = RegExp(r'(19\d{2}|20\d{2})[.年/]').firstMatch(row.text);
      if (match == null) continue;
      final y = int.parse(match[1]!);
      for (final cell in cells) {
        final name = evidenceName(
            cell.text.replaceAll('※', '').replaceAll('◎', '').trim());
        if (byName.containsKey(name))
          addName(
              name,
              achievement(
                  row.querySelectorAll('th').any((h) => h.text.trim() == '☆')
                      ? '完全試合'
                      : 'ノーヒットノーラン',
                  y,
                  nohitUrl,
                  kind: 'rare_game',
                  detail: 'NPB公式の無安打無得点試合記録。'));
      }
    }
  } catch (e) {
    errors.add('$e');
  }
  var count = 0;
  for (final t in teams) {
    final payloads = <Map<String, dynamic>>[];
    for (final p in usageMaps(usageMap(t['team'])['roster'])) {
      final key = '${p['player_key']}', update = updates[key];
      if (update == null) continue;
      final badges = {
        for (final b in [
          ...usageMaps(p['additional_achievements']),
          ...usageMaps(update['additional_achievements'])
        ])
          '${b['id']}': b
      };
      update['additional_achievements'] = badges.values.toList();
      update['career_honors_checked_at'] = DateTime.now().toIso8601String();
      payloads.add({'key': key, 'payload': update});
      count++;
    }
    if (payloads.isEmpty) continue;
    await Postgres.withConnection((c) => c.runTx((tx) async {
          await tx.execute(
              '''INSERT INTO t_strength_player_status(code_org,int_year,id_team,player_key,payload)
      SELECT \$1,\$2,\$3,p->>'key',p->'payload' FROM jsonb_array_elements(\$4::jsonb) p
      ON CONFLICT(code_org,int_year,id_team,player_key) DO UPDATE SET payload=t_strength_player_status.payload||EXCLUDED.payload,updated_at=NOW()''',
              parameters: [t['org'], year, t['id_team'], jsonEncode(payloads)]);
          await tx.execute(
              '''UPDATE t_team_strength t SET payload=jsonb_set(payload,'{roster}',
      (SELECT jsonb_agg(p||COALESCE((SELECT s.payload FROM t_strength_player_status s WHERE s.code_org=t.code_org AND s.int_year=t.int_year AND s.id_team=t.id_team AND s.player_key=p->>'player_key'),'{}'::jsonb)) FROM jsonb_array_elements(t.payload->'roster') p)) WHERE int_year=\$1 AND code_org=\$2 AND id_team=\$3''',
              parameters: [year, t['org'], t['id_team']]);
        }));
  }
  File('${cache.path}/career-honors-errors.json')
      .writeAsStringSync(jsonEncode(errors));
  print('登録 $count人 / 取得エラー ${errors.length}件');
  client.close();
  exit(0);
}
