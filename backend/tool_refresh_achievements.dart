import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'app/PlayerAchievements.dart';
import 'app/AchievementSupplement.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.first), client = http.Client();
  final cache = Directory('/tmp/koko-achievements-$year')..createSync(recursive: true);
  Future<String> get(String url) async {
    final file = File('${cache.path}/${Uri.encodeComponent(url)}');
    if (file.existsSync()) return file.readAsStringSync();
    final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode} $url');
    final body = utf8.decode(r.bodyBytes);
    file.writeAsStringSync(body);
    return body;
  }

  final errors = <String>[];
  try {
    final rows = await Postgres.withConnection((c) => c.execute('SELECT code_org,id_team,payload FROM t_team_strength WHERE int_year=\$1', parameters: [year]));
    final awards = <String, List<Map<String, dynamic>>>{};
    final urls = [
      for (var y = 2000; y <= year; y++)
        for (final league in ['cl', 'pl']) (y, 'https://npb.jp/award/$y/$league.html')
    ];
    for (var i = 0; i < urls.length; i += 4) {
      await Future.wait(urls.skip(i).take(4).map((entry) async {
        try {
          for (final e in npbAwardEntries(await get(entry.$2), entry.$1, entry.$2).entries) {
            awards.putIfAbsent(e.key, () => []).addAll(e.value);
          }
        } catch (e) {
          errors.add('$e');
        }
      }));
    }
    final byName = <String, List<Map<String, dynamic>>>{};
    for (var y = 2002; y <= year; y++) {
      String? champion;
      for (final type in ['month', 'series']) {
        final url = type == 'month' ? 'https://npb.jp/award/$y/month.html' : 'https://npb.jp/nippons/$y/award.html';
        try {
          final body = await get(url);
          final parsed = type == 'month' ? npbMonthlyEntries(body, y, url) : npbSeriesEntries(body, y, url);
          for (final e in parsed.entries) {
            awards.putIfAbsent(e.key, () => []).addAll(e.value);
          }
          if (type == 'series') {
            final h = html.parse(body).querySelectorAll('h4').where((e) => e.text.contains('優勝チーム賞')).firstOrNull;
            champion = h?.nextElementSibling?.querySelector('.award_left p')?.text.trim();
          }
        } catch (e) {
          errors.add('$e');
        }
      }
      for (final league in ['central', 'pacific']) {
        final url = 'https://npb.jp/bis/yearly/${league}league_$y.html';
        try {
          for (final e in npbQualifiedEntries(await get(url), y, url, japanChampion: champion).entries) {
            byName.putIfAbsent(e.key, () => []).addAll(e.value);
          }
        } catch (e) {
          errors.add('$e');
        }
      }
    }
    final allNpb = [
      for (final row in rows)
        if (row[0] == 'npb') ...usageMaps(usageMap(row[2] is String ? jsonDecode(row[2] as String) : row[2])['roster'])
    ];
    final supplements = await achievementSupplement(year, get, [for (final row in rows) ...usageMaps(usageMap(row[2] is String ? jsonDecode(row[2] as String) : row[2])['roster'])]);
    for (final row in rows) {
      final org = '${row[0]}', team = usageMap(row[2] is String ? jsonDecode(row[2] as String) : row[2]);
      final roster = usageMaps(team['roster']), updates = <Map<String, dynamic>>[];
      for (var i = 0; i < roster.length; i += 6) {
        await Future.wait(roster.skip(i).take(6).map((p) async {
          final key = '${p['player_key']}', id = '${p['source_player_id']}';
          try {
            final badges = <Map<String, dynamic>>[...?supplements[key]];
            if (org == 'npb') {
              final url = 'https://npb.jp/bis/players/$id.html';
              badges.addAll(statisticalAchievements(npbCareerSeasons(await get(url)), url, 'NPB', year));
              badges.addAll(awards[key] ?? []);
              final name = usageName('${p['name']}');
              if (allNpb.where((p) => usageName('${p['name']}') == name).length == 1) {
                badges.addAll(byName[name] ?? []);
              }
              for (var y = 2000; y <= year; y++) {
                final labels = badges.where((b) => b['year'] == y).map((b) => '${b['label']}').toList();
                if (labels.any((s) => s.contains('首位打者')) && labels.any((s) => s.contains('本塁打')) && labels.any((s) => s.contains('打点'))) {
                  badges.add(achievement('三冠王', y, 'https://npb.jp/award/$y/', kind: 'record'));
                }
              }
            } else {
              final url = 'https://statsapi.mlb.com/api/v1/people/$id?hydrate=stats(group=[hitting,pitching],type=[yearByYear])';
              final data = usageMaps(usageMap(jsonDecode(await get(url)))['people']);
              final seasons = <Map<String, dynamic>>[];
              for (final group in usageMaps(data.firstOrNull?['stats'])) {
                final byYear = <int, List<Map<String, dynamic>>>{};
                for (final split in usageMaps(group['splits'])) {
                  if (usageInt(usageMap(split['sport'])['id']) != 1) continue;
                  byYear.putIfAbsent(usageInt(split['season']), () => []).add(split);
                }
                for (final e in byYear.entries) {
                  final combined = e.value.where((p) => p['team'] == null).firstOrNull;
                  final selected = combined != null ? [combined] : e.value;
                  final stat = <String, dynamic>{'year': e.key};
                  for (final split in selected) {
                    final v = usageMap(split['stat']);
                    for (final f in {'homeRuns': 'hr', 'stolenBases': 'sb', 'rbi': 'rbi', 'hits': 'hits', 'wins': 'wins', 'saves': 'saves', 'strikeOuts': 'strikeouts'}.entries) {
                      final pitching = usageMap(group['group'])['displayName'] == 'pitching';
                      if (pitching != ['wins', 'saves', 'strikeouts'].contains(f.value)) {
                        continue;
                      }
                      stat[f.value] = usageInt(stat[f.value]) + usageInt(v[f.key]);
                    }
                    if (v['avg'] != null) stat['avg'] = v['avg'];
                  }
                  seasons.add(stat);
                }
              }
              badges.addAll(statisticalAchievements(seasons, url, 'MLB', year));
              final awardUrl = 'https://statsapi.mlb.com/api/v1/people/$id/awards';
              for (final a in usageMaps(usageMap(jsonDecode(await get(awardUrl)))['awards'])) {
                final y = usageInt(a['season']);
                if (y <= 0 || y > year) continue;
                badges.add({...achievement('${a['name']}', y, awardUrl, kind: 'title', detail: '${a['date'] ?? ''}'), 'id': '$y/${a['name']}/${a['date'] ?? a['id']}'});
              }
            }
            final unique = {for (final b in badges) '${b['id']}': b}.values.toList()..sort((a, b) => usageInt(b['year']).compareTo(usageInt(a['year'])));
            updates.add({
              'key': key,
              'payload': {'achievements': unique, 'achievements_checked_at': DateTime.now().toIso8601String()}
            });
          } catch (e) {
            errors.add('$key $e');
          }
        }));
      }
      await Postgres.withConnection((c) async {
        await c.execute('''INSERT INTO t_strength_player_status(code_org,int_year,id_team,player_key,payload)
      SELECT \$1,\$2,\$3,p->>'key',p->'payload' FROM jsonb_array_elements(\$4::jsonb) p
      ON CONFLICT(code_org,int_year,id_team,player_key) DO UPDATE SET payload=t_strength_player_status.payload||EXCLUDED.payload,updated_at=NOW()''', parameters: [org, year, row[1], jsonEncode(updates)]);
        await c.execute('''UPDATE t_team_strength t SET payload=jsonb_set(payload,'{roster}',
      (SELECT jsonb_agg(p||COALESCE((SELECT s.payload FROM t_strength_player_status s WHERE s.code_org=t.code_org AND s.int_year=t.int_year AND s.id_team=t.id_team AND s.player_key=p->>'player_key'),'{}'::jsonb)) FROM jsonb_array_elements(t.payload->'roster') p)) WHERE int_year=\$1 AND code_org=\$2 AND id_team=\$3''', parameters: [year, org, row[1]]);
      });
      print('${team['name_team']}: ${updates.length}人の功績を登録');
    }
    File('${cache.path}/errors.json').writeAsStringSync(jsonEncode(errors));
    print('完了・取得エラー${errors.length}件（${cache.path}/errors.json）');
    exit(0);
  } finally {
    client.close();
  }
}
