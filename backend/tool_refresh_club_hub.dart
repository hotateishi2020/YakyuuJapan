import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'app/ClubData.dart';
import 'app/StrengthUsage.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first), client = http.Client();
  final file = File('data/club-hub-npb-$year.json');
  final old = file.existsSync() ? usageMap(jsonDecode(file.readAsStringSync())) : <String, dynamic>{};
  final supplements = readClubFile('club-hub-sources-$year.json');
  final clubs = <Map<String, dynamic>>[];
  Future<String> get(String url) async {
    final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode} $url');
    return utf8.decode(r.bodyBytes);
  }

  final sources = <String, List<(String, String)>>{
    't': [('https://m.hanshintigers.jp/sponsor/official.html', 'img[src*="/images/sponsor/"]'), ('https://m.hanshintigers.jp/sponsor/partner.html', 'img[src*="/images/sponsor/"]')],
    'db': [('https://www.baystars.co.jp/sponsor/list', 'img[src*="/images/sponsor/"]')],
    'd': [('https://www.dragons.jp/sponsor/2026/', 'img[src*="/sponsor/image/"]')],
    'f': [('https://www.fighters.co.jp/expansion/partnership/', 'img[src*="img/logo-"]')],
    's': [('https://www.yakult-swallows.co.jp/', 'img.p-footer__sponsor-img')],
    'h': [('https://www.softbankhawks.co.jp/sponsor/officialsponsorlist.html', 'img[data-src*="sponsor"],img[src*="sponsor"]')],
    'b': [('https://www.buffaloes.co.jp/company/sponsor.html', 'img[data-src*="sponsor"],img[src*="sponsor"]')],
    'e': [('https://www.rakuteneagles.jp/company/sponsor/', 'img[data-src*="sponsor"],img[src*="sponsor"]')],
  };
  try {
    for (final entry in npbClubNames.entries) {
      final code = entry.key, staff = <Map<String, dynamic>>[], sponsors = <Map<String, dynamic>>[];
      final url = 'https://npb.jp/announcement/$year/managers_$code.html';
      final doc = html.parse(await get(url));
      for (final tr in doc.querySelectorAll('tr')) {
        if (tr.classes.contains('xxx')) continue;
        final cells = tr.querySelectorAll('td');
        if (cells.length != 3 || !RegExp(r'^\d+$').hasMatch(cells[1].text.trim())) {
          continue;
        }
        final role = cells[0].text.trim().replaceAll(RegExp(r'\s+'), ' '), name = cells[2].text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (name.isEmpty) continue;
        final category = role.contains('副監督')
            ? '副監督'
            : role == '監督' || role == '一軍監督' || role.contains('監督代行')
                ? '監督'
                : role.contains('コーチ') || role.contains('監督')
                    ? 'コーチ'
                    : '特殊スタッフ';
        staff.add({'name': name, 'role': role, 'category': category, 'source': url, 'as_of': '$year 年度登録'});
      }
      if (staff.isEmpty) throw StateError('監督・コーチ登録を取得できません: $code');
      final supplement = usageMaps(supplements['clubs']).where((c) => c['code'] == code).firstOrNull ?? {};
      staff.addAll(usageMaps(supplement['staff']));
      if (args.contains('--staff-only')) {
        sponsors.addAll(usageMaps(usageMaps(old['clubs']).where((c) => c['code'] == code).firstOrNull?['sponsors']));
      }
      for (final source in args.contains('--staff-only') ? <(String, String)>[] : sources[code] ?? <(String, String)>[]) {
        try {
          final page = html.parse(await get(source.$1));
          for (final img in page.querySelectorAll(source.$2)) {
            final name = (img.attributes['alt']?.trim().isNotEmpty == true
                        ? img.attributes['alt']
                        : code == 'h'
                            ? img.parent?.parent?.querySelectorAll('td').lastOrNull?.text
                            : null)
                    ?.trim() ??
                '';
            final src = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
            if (name.isEmpty || src.isEmpty || src.endsWith('/sp.gif') || RegExp('スポンサー|メニュー|SPONSOR|募集|プログラム', caseSensitive: false).hasMatch(name) || sponsors.any((s) => s['name'] == name)) {
              continue;
            }
            sponsors.add({'name': name, 'logo': Uri.parse(source.$1).resolve(src).toString(), 'category': '公式スポンサー', 'source': source.$1});
          }
        } catch (e) {
          stderr.writeln(e);
        }
      }
      for (final extra in usageMaps(supplement['sponsors'])) {
        final matches = sponsors.where((s) => s['name'] == extra['name'] || extra['match'] != null && '${s['name']}'.contains('${extra['match']}')).toList();
        if (matches.isEmpty) {
          sponsors.add({...extra});
        } else {
          for (final s in matches) {
            s.addAll(extra);
          }
        }
      }
      // Keep a cached original image on our origin; avoid broken cross-origin canvas rendering.
      final dir = Directory('public/club-logos/$year/$code')..createSync(recursive: true);
      for (var i = 0; i < sponsors.length; i++) {
        final s = sponsors[i], logo = s['logo'];
        if (logo == null || '$logo'.startsWith('/')) continue;
        try {
          final uri = Uri.parse('$logo'), ext = uri.path.split('.').last.toLowerCase();
          if (!['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(ext)) continue;
          final imageKey = sha256.convert(utf8.encode('$logo')).toString().substring(0, 20);
          final img = File('${dir.path}/$imageKey.$ext');
          if (!img.existsSync()) {
            final previous = usageMaps(old['clubs']).where((c) => c['code'] == code).firstOrNull;
            final cached = usageMaps(previous?['sponsors']).where((p) => p['original_logo'] == logo).firstOrNull;
            final cachedFile = cached == null ? null : File('public${cached['logo']}');
            if (cachedFile != null && cachedFile.existsSync()) {
              cachedFile.copySync(img.path);
            }
          }
          if (!img.existsSync()) {
            final r = await client.get(uri).timeout(const Duration(seconds: 20));
            if (r.statusCode != 200 || !(r.headers['content-type'] ?? '').startsWith('image/')) {
              continue;
            }
            img.writeAsBytesSync(r.bodyBytes);
          }
          s['original_logo'] = logo;
          s['logo'] = '/club-logos/$year/$code/$imageKey.$ext';
        } catch (e) {
          stderr.writeln('Logo $code $i: $e');
        }
      }
      clubs.add({'code': code, 'name': entry.value, 'staff': staff, 'sponsors': sponsors});
      print('$code: ${staff.length} staff, ${sponsors.length} sponsors');
    }
    final result = {...old, 'year': year, 'checked_at': DateTime.now().toUtc().toIso8601String(), 'clubs': clubs, 'training_groups': supplements['training_groups'] ?? []};
    File('${file.path}.tmp').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    File('${file.path}.tmp').renameSync(file.path);
  } finally {
    client.close();
  }
}
