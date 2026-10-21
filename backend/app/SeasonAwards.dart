import 'AllStarHistory.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

String _text(Element? e) => (e?.text ?? '').replaceAll(RegExp(r'[\s　]+'), ' ').trim();
String _team(Element? e) => _text(e).replaceAll(RegExp(r'^[（(]|[）)]$'), '');

/// Extract facts only; surrounding prize descriptions and article prose are not stored.
List<Map<String, dynamic>> parseSeasonAwardPage(String body, String path, int year) {
  if (path == 'allstar/$year/roster.html') {
    return [
      for (final row in parseNpbAllStarRoster(body, year)) {...row, 'key': 'allstar_roster', 'detail': row['position'], 'confirmed': true}
    ];
  }
  final doc = html.parse(body), rows = <Map<String, dynamic>>[];
  final source = 'https://npb.jp/$path';
  final code = RegExp(r'/(?:ll[bp]_)?(2e|2c|2w|el|wl|e|w)\.html$').firstMatch(path)?[1];
  final farmLeague = const {'2e': '東地区', '2c': '中地区', '2w': '西地区', 'el': 'イースタン', 'wl': 'ウエスタン', 'e': 'イースタン', 'w': 'ウエスタン'}[code];
  void add(String key, String name, {String team = '', String detail = ''}) {
    if (name.isEmpty || name == '未定') return;
    rows.add({'key': key, 'name': name.replaceFirst(RegExp(r'\s*選手$'), ''), 'team': team, 'detail': detail, 'source': source, 'confirmed': true});
  }

  final league = path.endsWith('/cl.html')
      ? 'セ・リーグ'
      : path.endsWith('/pl.html')
          ? 'パ・リーグ'
          : '';
  if (farmLeague != null && path.contains('/stats/ll')) {
    for (final section in doc.querySelectorAll('.unit-half__section')) {
      final metric = const {'安打': '最多安打', '奪三振': '最多奪三振'}[_text(section.querySelector('h5'))];
      if (metric == null) continue;
      String? best;
      for (final row in section.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 3) continue;
        final value = _text(cells[2]);
        best ??= value;
        if (value != best) break;
        final match = RegExp(r'^(.*?)\s*[（(]([^）)]+)[）)]$').firstMatch(_text(cells[1]));
        if (match == null) continue;
        const teams = {'G': '巨人', 'T': '阪神', 'D': '中日', 'C': '広島', 'S': 'ヤクルト', 'DB': 'DeNA', 'H': 'ソフトバンク', 'F': '日本ハム', 'L': '西武', 'M': 'ロッテ', 'B': 'オリックス', 'E': '楽天', 'Ｏ': 'オイシックス', 'O': 'オイシックス', 'Ｈ': 'ハヤテ', '巨': '巨人', '神': '阪神', '中': '中日', '広': '広島', 'ヤ': 'ヤクルト', 'デ': 'DeNA', 'ソ': 'ソフトバンク', '日': '日本ハム', '西': '西武', 'ロ': 'ロッテ', 'オ': 'オリックス', '楽': '楽天', 'ハ': 'ハヤテ'};
        add('farm_major', match[1]!, team: match[2] == 'Ｈ' ? 'ハヤテ' : teams[String.fromCharCodes(match[2]!.runes.map((c) => c >= 0xff21 && c <= 0xff3a ? c - 0xfee0 : c))] ?? match[2]!, detail: '$farmLeague $metric');
        rows.last.addAll({'farm_league': farmLeague, 'award_label': metric, 'value': value, 'statistical': true, 'confirmed': false});
      }
    }
  } else if (path.startsWith('bis/') && path.contains('/stats/std_')) {
    if (doc.querySelectorAll('.contents p').any((p) => _text(p) == '全日程終了')) {
      final table = doc.querySelector('table.tablefix2');
      final row = table?.querySelector('tbody tr');
      final name = _text(row?.querySelector('td'));
      add('league_champion', name, detail: path.endsWith('std_c.html') ? 'セ・リーグ' : 'パ・リーグ');
    }
  } else if (path.contains('/roster.html')) {
    for (final table in doc.querySelectorAll('table')) {
      var position = '';
      for (final row in table.querySelectorAll('tr')) {
        final heading = row.querySelector('.position');
        if (heading != null) position = _text(heading);
        final name = row.querySelector('td.name');
        if (name == null || ['監督', 'コーチ'].contains(position)) continue;
        add(path.startsWith('freshas') ? 'fresh_roster' : 'allstar_roster', _text(name), team: _team(row.querySelector('td.team')), detail: position);
      }
    }
  } else if (path.endsWith('/month.html') || path.endsWith('/sayonara.html')) {
    var leagueName = '', role = '';
    for (final el in doc.querySelectorAll('.contents h5, .contents h6, .contents tr')) {
      if (el.localName == 'h5') leagueName = _text(el);
      if (el.localName == 'h6') role = _text(el);
      final cells = el.children.where((e) => ['td', 'th'].contains(e.localName)).toList();
      if (el.localName == 'tr' && cells.length >= 3 && RegExp(r'[0-9０-９].*月').hasMatch(_text(cells[0])) && _text(cells[1]).isNotEmpty) {
        add(path.endsWith('/sayonara.html') ? 'sayonara' : 'monthly', _text(cells[1]), team: _team(cells[2]), detail: '$leagueName $role ${_text(cells[0])}');
      }
    }
  } else if (path.startsWith('award/')) {
    var section = '';
    for (final card in doc.querySelectorAll('.contents h4, [class*="player_unit"]')) {
      if (card.localName == 'h4') {
        section = _text(card);
        continue;
      }
      final name = _text(card.querySelector('.name'));
      final label = _text(card.querySelector('h6'));
      final team = _team(card.querySelector('.team'));
      String? key;
      if (path.endsWith('/hikeshi.html')) {
        key = 'hikeshi';
      } else if (path.endsWith('/speedup.html')) {
        key = 'speedup';
      } else if (label.contains('最優秀監督')) {
        key = 'manager';
      } else if (section.contains('コミッショナー特別表彰')) {
        key = 'commissioner_special';
      } else if (section.contains('連盟特別表彰') && label.contains('功労賞')) {
        key = 'league_merit';
      } else if (section.contains('連盟特別表彰') && label == '特別賞') {
        key = 'league_special';
      } else if (path.endsWith('/glove.html')) {
        key = 'glove';
      } else if (label.contains('正力松太郎')) {
        key = label.contains('特別賞') ? 'shoriki_special' : 'shoriki';
      } else if (label.contains('沢村')) {
        key = 'sawamura';
      } else if (label.contains('長嶋茂雄')) {
        key = 'nagashima';
      } else if (label.contains('ベストナイン') || label.contains('ベストDH')) {
        key = 'best9';
      } else if (label.contains('最優秀選手')) {
        key = 'league_mvp';
      } else if (label.contains('最優秀新人')) {
        key = 'rookie';
      } else if (RegExp(r'首位打者|最多|最高|防御率|勝率第一|最優秀中継ぎ').hasMatch(label)) {
        key = 'major';
      }
      if (key != null) {
        add(farmLeague != null ? 'farm_major' : key, name, team: team, detail: '${farmLeague ?? league} $label'.trim());
        if (key == 'glove') {
          final comment = _text(card);
          final count = RegExp(r'(\d+)[回度]目').firstMatch(comment)?[1];
          final playerId = RegExp(r'/players/(\d+)\.html').firstMatch(card.outerHtml)?[1];
          if (count != null || comment.contains('初受賞')) rows.last['career_count'] = int.tryParse(count ?? '') ?? 1;
          if (playerId != null) rows.last['source_player_id'] = playerId;
        }
        if (farmLeague != null && rows.isNotEmpty) rows.last.addAll({'farm_league': farmLeague, 'award_label': label});
        final stat = card.querySelectorAll('.comment').map(_text).where((t) => RegExp(r'^(打率|安打|本塁打|打点|盗塁|出塁率|防御率|勝率|勝利|セーブ|ホールドポイント|奪三振)\s').hasMatch(t)).firstOrNull;
        if (stat != null && rows.isNotEmpty) rows.last['value'] = stat;
      }
    }
  } else if (path.endsWith('/award.html') || RegExp(r'/award_\d.html$').hasMatch(path)) {
    var label = '';
    for (final el in doc.querySelectorAll('.contents h4, .contents h5, .contents dt.name')) {
      if (el.localName != 'dt') {
        label = _text(el);
        continue;
      }
      final series = path.startsWith('nippons');
      if (!(series ? RegExp(r'最優秀選手|最高殊勲選手|敢闘選手|優秀選手') : RegExp(r'最優秀選手|最高殊勲選手')).hasMatch(label)) {
        continue;
      }
      final key = series
          ? label.contains('敢闘選手')
              ? 'series_fighting'
              : RegExp(r'最優秀選手|最高殊勲選手').hasMatch(label)
                  ? 'series_mvp'
                  : 'series_outstanding'
          : path.startsWith('freshas')
              ? 'fresh_mvp'
              : path.startsWith('interleague')
                  ? 'interleague_mvp'
                  : 'allstar_mvp';
      add(key, _text(el),
          team: _team(el.parent?.querySelector('.team')),
          detail: path.contains('award_1')
              ? '第1戦'
              : path.contains('award_2')
                  ? '第2戦'
                  : '');
    }
    if (path.startsWith('nippons')) {
      for (final wrap in doc.querySelectorAll('.wrap')) {
        if (_text(wrap.querySelector('h4')) == '優勝チーム賞') {
          add('series_champion', _text(wrap.querySelector('.award_left p')));
        }
      }
    }
    if (path.startsWith('interleague')) {
      add('interleague_champion', _text(doc.querySelector('.award_team dd')));
    }
  } else if (path == 'nippons/$year/') {
    for (final name in doc.querySelectorAll('#team_profile .name dd')) {
      add('series_entrants', _text(name));
    }
  }
  return rows;
}

class SeasonAwards {
  static final _running = <int>{};
  static final _checked = <int, DateTime>{};
  static File file(int year) {
    final root = Directory('data').existsSync() ? 'data' : 'backend/data';
    return File('$root/season_awards/$year.json');
  }

  static Map<String, dynamic> read(int year, {bool refresh = true}) {
    final f = file(year);
    Map<String, dynamic> data = {};
    if (f.existsSync()) {
      try {
        data = Map<String, dynamic>.from(jsonDecode(f.readAsStringSync()));
      } catch (_) {/* retain a retryable empty state */}
    }
    final checked = _checked[year] ?? DateTime.tryParse('${data['checked_at']}');
    if (refresh && !_running.contains(year) && (checked == null || DateTime.now().difference(checked).inHours >= 6)) {
      unawaited(update(year).catchError((Object e) {
        stderr.writeln('Season awards refresh failed ($year): $e');
        return <String, dynamic>{};
      }));
    }
    return data;
  }

  static Future<Map<String, dynamic>> update(int year) async {
    if (!_running.add(year)) return read(year, refresh: false);
    _checked[year] = DateTime.now();
    final client = http.Client();
    final old = read(year, refresh: false);
    final pages = Map<String, dynamic>.from(old['pages'] as Map? ?? {});
    pages.removeWhere((key, _) => key.startsWith('https://sports.yahoo.co.jp/') && key.contains('?page='));
    final errors = <String>[];
    final paths = [
      for (final page in [
        'cl',
        'pl',
        'glove',
        'shosawa',
        'npb',
        'month',
        'sayonara',
        'speedup',
        if (year >= 2026) 'hikeshi',
        if (year >= 2026) ...['2e', '2c', '2w'] else ...['el', 'wl']
      ])
        'award/$year/$page.html',
      for (final league in (year >= 2026 ? ['2e', '2c', '2w'] : ['e', 'w']))
        for (final type in ['llb', 'llp']) 'bis/$year/stats/${type}_$league.html',
      'bis/$year/stats/std_c.html',
      'bis/$year/stats/std_p.html',
      'nippons/$year/award.html',
      'nippons/$year/',
      'interleague/$year/award.html',
      'allstar/$year/award_1.html',
      'allstar/$year/award_2.html',
      'allstar/$year/roster.html',
      'freshas/$year/award.html',
      'freshas/$year/roster.html',
    ];
    try {
      for (var i = 0; i < paths.length; i += 3) {
        await Future.wait(paths.skip(i).take(3).map((path) async {
          try {
            final response = await client.get(Uri.parse('https://npb.jp/$path')).timeout(const Duration(seconds: 20));
            if (response.statusCode == 404) {
              return; // Not yet published, or not held in that year.
            }
            if (response.statusCode != 200) {
              throw StateError('HTTP ${response.statusCode}');
            }
            final rows = parseSeasonAwardPage(utf8.decode(response.bodyBytes), path, year);
            // Verified highlights belong to a particular recipient/month.
            // Keep them when the official recipient list is refreshed.
            if (path.endsWith('/sayonara.html')) {
              final previous = (pages[path] as List? ?? const []).whereType<Map>();
              for (final row in rows) {
                final match = previous.where((old) => old['name'] == row['name'] && old['detail'] == row['detail'] && old['team'] == row['team']).firstOrNull;
                if (match != null) {
                  for (final key in match.keys.where((key) => '$key'.startsWith('highlight_'))) {
                    row['$key'] = match[key];
                  }
                }
              }
            }
            // Never erase successfully imported recipients after a layout change/transient response.
            if (rows.isNotEmpty) pages[path] = rows;
          } catch (e) {
            errors.add('$path: $e');
          }
        }));
      }
      final weeklyIndex = {2025: 'https://sports.yahoo.co.jp/contents/17973', 2026: 'https://sports.yahoo.co.jp/contents/22023'}[year];
      if (weeklyIndex != null) {
        try {
          final response = await client.get(Uri.parse(weeklyIndex)).timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) {
            throw StateError('HTTP ${response.statusCode}');
          }
          final doc = html.parse(utf8.decode(response.bodyBytes));
          final links = doc.querySelectorAll('a[href]').where((a) => a.text.contains('【週間MVP】')).map((a) => a.attributes['href']!.split('?').first).where((s) => s.startsWith('https://sports.yahoo.co.jp/column/detail/$year')).toSet();
          final jobs = [
            for (final link in links)
              for (final page in [1, 2]) '$link?p=$page'
          ];
          for (var i = 0; i < jobs.length; i += 3) {
            await Future.wait(jobs.skip(i).take(3).map((url) async {
              try {
                final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
                if (r.statusCode == 404) {
                  return; // Some weekly articles have only one page.
                }
                if (r.statusCode != 200) {
                  throw StateError('HTTP ${r.statusCode}');
                }
                final rows = parseSportsNaviWeekly(utf8.decode(r.bodyBytes), url);
                if (rows.isNotEmpty) pages[url] = rows;
              } catch (e) {
                errors.add('$url: $e');
              }
            }));
          }
        } catch (e) {
          errors.add('$weeklyIndex: $e');
        }
      }
      final data = {'year': year, 'checked_at': DateTime.now().toUtc().toIso8601String(), 'pages': pages, 'errors': errors};
      final f = file(year);
      await f.parent.create(recursive: true);
      final temp = File('${f.path}.tmp');
      await temp.writeAsString(jsonEncode(data));
      await temp.rename(f.path);
      return data;
    } finally {
      client.close();
      _running.remove(year);
    }
  }
}

List<Map<String, dynamic>> readSeasonAwardSupplement(String org, int year) {
  final root = Directory('data').existsSync() ? 'data' : 'backend/data';
  final file = File('$root/season_award_supplement.json');
  if (!file.existsSync()) return [];
  return [
    for (final row in jsonDecode(file.readAsStringSync()) as List)
      if (row['org'] == org && row['year'] == year) Map<String, dynamic>.from(row)
  ];
}

List<Map<String, dynamic>> parseSportsNaviWeekly(String body, String url) {
  final doc = html.parse(body);
  final date = RegExp(r'/detail/(\d{4})(\d{2})(\d{2})').firstMatch(url);
  if (date == null) return [];
  final rows = <Map<String, dynamic>>[];
  var category = '';
  for (final el in doc.querySelectorAll('.cm-articleParagraph__text')) {
    final text = _text(el);
    final context = RegExp(r'([セパ])[・･]リーグ(?:の|は)?(野手|投手)(?:部門)?').firstMatch(text);
    if (context != null) category = '${context[1]}・リーグ ${context[2]}';
    for (final b in el.querySelectorAll('b, strong')) {
      final match = RegExp(r'^1位\s+(.+?)[（(](.+?)[）)]$').firstMatch(_text(b));
      if (match == null || category.isEmpty) continue;
      rows.add({'key': 'weekly', 'name': match[1], 'team': match[2], 'detail': '${date[1]}/${date[2]}/${date[3]}発表 $category', 'confirmed': true, 'source': url});
    }
  }
  return rows;
}
