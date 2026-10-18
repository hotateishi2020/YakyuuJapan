import 'package:html/parser.dart' as html;
import 'ExtendedPlayerMetrics.dart';
import 'StrengthUsage.dart';

/// Public Standard fielding rows only; never derive counts from rounded rates.
int? parseCatcherCount(String body, int year) {
  final values = <String,int>{};
  for(final row in html.parse(body).querySelectorAll('tr')) {
    final c = row.querySelectorAll('td').map((e)=>e.text.trim()).toList();
    if(c.length != 26 || c[0] != '$year' || c[3] != '１軍' || c[4] != 'C') continue;
    final count = int.tryParse(c[21]);
    if(count != null) values[c[2]] = count;
  }
  return values.isEmpty ? null : values.values.reduce((a,b)=>a+b);
}

Future<void> refreshNpbCatcherCounts(int year, List<Map<String,dynamic>> players, Future<String> Function(String) get) async {
  String normalize(String s)=>s.replaceAll(RegExp(r'[\s　]'),'');
  final candidates = {for(final p in players) if(p['org']=='npb' && usageMaps(p['metrics']).any((m)=>m['title']=='盗塁阻止率' || m['title']=='盗塁阻止数')) normalize('${p['name']}'):p};
  final root = Uri.parse('https://1point02.jp/op/gnav/leaders/pl/pbs_standard.aspx?cp=101');
  final index = html.parse(await get('$root'));
  final teams = index.querySelectorAll('a[href*="tm_playerlist.aspx"]').map((a)=>root.resolve(a.attributes['href']!)).toSet();
  final links = <String,String>{};
  for(final uri in teams) {
    final url=uri.replace(queryParameters:{...uri.queryParameters,'sn':'$year'});
    final page=html.parse(await get('$url'));
    for(final a in page.querySelectorAll('a[href*="pl="]')) {
      final name=normalize(a.text);
      if(!candidates.containsKey(name)) continue;
      final id=url.resolve(a.attributes['href']!).queryParameters['pl'];
      if(id!=null) links[name]='https://1point02.jp/op/gnav/player/stats/player_stats_fs.aspx?pl=$id';
    }
  }
  final entries=links.entries.toList();
  for(var i=0;i<entries.length;i+=5) {
    await Future.wait(entries.skip(i).take(5).map((e) async {
      final count=parseCatcherCount(await get(e.value),year);
      if(count==null) return;
      final metrics=candidates[e.key]!['metrics'] as List;
      metrics.removeWhere((m)=>m['title']=='盗塁阻止率' || m['title']=='盗塁阻止数');
      metrics.add({...metric('盗塁阻止数',count), 'source':e.value,'catcher_metric':true});
    }));
  }
}
