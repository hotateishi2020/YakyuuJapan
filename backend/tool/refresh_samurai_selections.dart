import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

/// Official senior national-team selections, including announced replacements
/// and withdrawals. Coaches and provisional training candidates are excluded.
Future<void> main(List<String> args) async {
  final client = http.Client();
  Future<String> fetch(String url) async {
    final cache = File('/tmp/koko-samurai-cache/${Uri.encodeComponent(url)}');
    if (args.contains('--cached') && cache.existsSync()) {
      return cache.readAsStringSync();
    }
    final response =
        await client.get(Uri.parse(url)).timeout(const Duration(seconds: 40));
    if (response.statusCode != 200) {
      throw StateError('$url: ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes);
    cache.parent.createSync(recursive: true);
    cache.writeAsStringSync(body);
    return body;
  }

  const base = 'https://www.japan-baseball.jp';
  final archive = html.parse(await fetch('$base/jp/team/topteam/game.html'));
  final events = archive
      .querySelectorAll('a[href]')
      .map((a) => a.attributes['href']!)
      .map((p) => RegExp(r'^/jp/team/topteam/(\d{4})/([^/]+)/').firstMatch(p))
      .whereType<RegExpMatch>()
      .map((m) => '${m[1]}/${m[2]}')
      .toSet()
      .toList()
    ..sort();
  final records = <Map<String, dynamic>>[];
  for (var start = 0; start < events.length; start += 4) {
    await Future.wait(events.skip(start).take(4).map((event) async {
      final url = const ['2017/jpntpe', '2018/jpntpe'].contains(event)
          ? '$base/jp/games/jpntpe${event.split('/').first}/player.html'
          : '$base/jp/team/topteam/$event/player.html';
      final doc = html.parse(await fetch(url));
      final year = int.parse(event.split('/').first);
      final category = event.contains('/wbc')
          ? 'wbc'
          : event.contains('/tokyo2020')
              ? 'olympics'
              : event.contains('/premier12')
                  ? 'premier12'
                  : 'other';
      final seen = <String>{};
      for (final a in doc.querySelectorAll('a[href*="/profile/"]')) {
        final name =
            (a.querySelector('td.name dt') ?? a.querySelector('td.name'))
                ?.text
                .trim();
        var unit = a.parent;
        while (unit != null && !unit.classes.contains('unit')) {
          unit = unit.parent;
        }
        final position =
            (a.querySelector('td.position') ?? unit?.querySelector('h4'))
                ?.text
                .trim();
        if (name == null ||
            !const ['投手', '捕手', '内野手', '外野手', '指名打者'].contains(position)) {
          continue;
        }
        final profile =
            Uri.parse(url).resolve(a.attributes['href']!.trim()).toString();
        if (!seen.add(profile)) continue;
        records.add({
          'name': name,
          'year': year,
          'category': category,
          'event': event,
          'source': url,
          'profile': profile
        });
      }
      print('$event: ${seen.length}');
      if (seen.isEmpty && category != 'other') {
        throw StateError('Empty roster: $url');
      }
    }));
  }
  final profiles = records.map((r) => r['profile'] as String).toSet().toList();
  final births = <String, String>{};
  for (var start = 0; start < profiles.length; start += 4) {
    await Future.wait(profiles.skip(start).take(4).map((url) async {
      final doc = html.parse(await fetch(url));
      final m = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日')
          .firstMatch(doc.querySelector('.birth')?.text ?? '');
      if (m == null) {
        print('Missing birth: $url');
        return;
      }
      births[url] = '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}';
    }));
    print('Profiles: ${births.length}/${profiles.length}');
  }
  final birthSupplements = jsonDecode(
      File('data/samurai_profile_birthdates.json').readAsStringSync()) as Map;
  for (final r in records) {
    r['birth_date'] = births[r['profile']];
    if (r['birth_date'] == null) {
      final sameName = records
          .where((p) => p['name'] == r['name'])
          .map((p) => births[p['profile']])
          .whereType<String>()
          .toSet();
      if (sameName.length == 1) r['birth_date'] = sameName.single;
    }
    if (r['birth_date'] == null) {
      final extra =
          birthSupplements['${r['name']}'.replaceAll(RegExp(r'\s'), '')];
      if (extra is Map) {
        r['birth_date'] = extra['birth_date'];
        r['birth_source'] = extra['source'];
      }
    }
    if (r['birth_date'] == null) {
      throw StateError('Unresolved birthday: ${r['name']}');
    }
  }
  for (final entry in {
    'https://npb.jp/wbc/2006/roster.html': (2006, 'wbc'),
    'https://npb.jp/wbc/2009/roster.html': (2009, 'wbc'),
    'https://npb.jp/wbc/2013/roster.html': (2013, 'wbc'),
    'https://npb.jp/olympic/2008/olympic_roster.html': (2008, 'olympics'),
  }.entries) {
    final doc = html.parse(await fetch(entry.key));
    var position = '';
    var count = 0;
    for (final tr in doc.querySelectorAll('tbody tr')) {
      final th = tr.querySelector('th');
      if (th != null) position = th.text.replaceAll(RegExp(r'\s'), '');
      if (!RegExp(r'^(投手|捕手|内野手|外野手)(（|$)').hasMatch(position)) continue;
      final name = tr.querySelector('td.name')?.text.trim();
      final m =
          RegExp(r'(\d{4})\.\s*(\d{1,2})\.\s*(\d{1,2})').firstMatch(tr.text);
      if (name == null || m == null) continue;
      records.add({
        'name': name,
        'birth_date':
            '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}',
        'year': entry.value.$1,
        'category': entry.value.$2,
        'event': '${entry.value.$1}/${entry.value.$2}',
        'source': entry.key
      });
      count++;
    }
    print('${entry.key}: $count');
    if (count < 24) throw StateError('Incomplete historic roster');
  }
  records.sort((a, b) =>
      '${a['event']}/${a['name']}'.compareTo('${b['event']}/${b['name']}'));
  File('data/samurai_selections.json')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({
        'scope':
            'Japan senior national team official selections (not coaches or training candidates)',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'selections': records
      })}\n');
  client.close();
}
