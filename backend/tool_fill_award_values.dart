import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'app/AwardValues.dart';

Future<void> main() async {
 final file=File('data/records.json');
 final data=jsonDecode(file.readAsStringSync());
 final jobs=<String,List<Map<String,dynamic>>>{};
 for(final s in data['npb']['awards']) {
  for(final c in s['categories']) {
   for(final p in c['players']) {
    final url='${p['source']}';
    if(url.contains('/award/') && url.endsWith('.html')) {
     jobs.putIfAbsent(url,()=>[]).add({'label':c['label'],'player':p});
    }
   }
  }
 }
 String name(dynamic x)=>'$x'.replaceAll(RegExp(r'[\s　]'),'');
 var count=0;
 final client=http.Client();
 try {
  final entries=jobs.entries.toList();
  for(var i=0;i<entries.length;i+=4) {
   await Future.wait(entries.skip(i).take(4).map((job) async {
    final response=await client.get(Uri.parse(job.key)).timeout(const Duration(seconds:30));
    if(response.statusCode!=200) throw StateError('HTTP ${response.statusCode}: ${job.key}');
    final cards=html.parse(utf8.decode(response.bodyBytes)).querySelectorAll('a[href*="/players/"]');
    for(final entry in job.value) {
     final p=entry['player'];
     for(final card in cards) {
      if(name(card.querySelector('.name')?.text)!=name(p['name'])) continue;
      final actual=npbAwardValue(card.querySelector('h6')?.text ?? '',card.text);
      final expected=npbAwardValue(entry['label'],card.text);
      if(actual.isEmpty || expected.isEmpty || actual['unit']!=expected['unit'] || actual['value']!=expected['value']) continue;
      p.addAll(expected); count++; break;
     }
    }
   }));
  }
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  print('記録値保存: $count 件');
 } finally {client.close();}
}
