import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;

/// Read-only audit of every candidate against official representative rosters and profile sources.
Future<void> main(List<String> args) async {
  final koshien = args.contains('--koshien');
  final players = (jsonDecode(File('assets/data/draft_2026.json').readAsStringSync())['players'] as List).cast<Map>();
  String norm(String s) => s.replaceAll(RegExp(r'[\s　]'), '').replaceAll('髙', '高').replaceAll('澤', '沢');
  final client = http.Client();
  final facts = <Map<String, dynamic>>[];
  try {
    for (final type in koshien ? <String>[] : ['univ', '18u']) {
      final index = html.parse(utf8.decode((await client.get(Uri.parse('https://www.japan-baseball.jp/jp/team/$type/player/'))).bodyBytes));
      final urls = index.querySelectorAll('a[href]').map((a) => a.attributes['href']!.split('#').first)
        .where((u) => RegExp('/$type/20(1[6-9]|2[0-6])/.*player.html').hasMatch(u)).toSet();
      for (final path in urls) {
        final url = Uri.parse('https://www.japan-baseball.jp').resolve(path).toString();
        final doc = html.parse(utf8.decode((await client.get(Uri.parse(url))).bodyBytes));
        final names = doc.querySelectorAll('td.name').map((a) => norm(a.text)).toSet();
        final title = doc.querySelector('title')?.text.split('|').first.trim() ?? '';
        for (final p in players) {
          if (names.contains(norm(p['name']))) facts.add({'name':p['name'], 'kind':'national_team', 'year':int.parse(RegExp(r'/([0-9]{4})/').firstMatch(url)![1]!), 'label':'${type == 'univ' ? '大学' : '高校'}日本代表：$title', 'source':url});
        }
      }
    }
    for (var offset = 0; offset < players.length; offset += 5) {
      await Future.wait(players.skip(offset).take(5).map((p) async {
        for (final url in (p['sources'] as List).cast<String>().where((u) => u.contains('findfriends.jp/player/'))) {
          try {
            final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds:20));
            final decoder = await Process.start('iconv', ['-f', 'EUC-JP', '-t', 'UTF-8']);
            decoder.stdin.add(response.bodyBytes);
            await decoder.stdin.close();
            final doc = html.parse(await utf8.decoder.bind(decoder.stdout).join());
            if (await decoder.exitCode != 0) throw StateError('profile encoding');
            for (final row in doc.querySelectorAll('tr')) {
              if (!row.text.contains('選手紹介')) continue;
              for (final sentence in row.text.split('。')) {
                if (koshien || RegExp('高校通算|首位打者|ベストナイン|最優秀|最多勝|本塁打王|打点王|盗塁王|日本代表').hasMatch(sentence)) facts.add({'name':p['name'],'kind':'profile_review','text':sentence.trim(),'source':url});
              }
            }
          } catch (e) {stderr.writeln('${p['name']}: $e');}
        }
      }));
    }
    final output = koshien ? '/tmp/draft-koshien-audit.json' : '/tmp/draft-career-audit.json';
    File(output).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(facts));
    print('${facts.length} facts: $output');
  } finally { client.close(); }
}
