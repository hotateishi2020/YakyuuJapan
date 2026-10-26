import 'dart:io';
import 'app/GameBench.dart';
import 'app/YahooHtml.dart';
import 'tools/Postgres.dart';
Future<void> main(List<String> args) async {
  final dates = args.isNotEmpty ? args : [for (var i=1;i>=0;i--) DateTime.now().toUtc().add(Duration(hours:9,days:-i)).toIso8601String().substring(0,10)];
  await Postgres.withConnection((conn) async {
    await GameBench.ensure(conn);
    for (final date in dates) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) throw ArgumentError('YYYY-MM-DD required');
      final games = await conn.execute(r'''SELECT g.id,g.id_team_home,g.id_team_away,h.name_short,a.name_short,h.id_league
        FROM t_game g JOIN m_team h ON h.id=g.id_team_home JOIN m_team a ON a.id=g.id_team_away
        WHERE g.datetime_start::date=$1::date AND NOT COALESCE(g.flg_delete,false)''',parameters:[date]);
      for (final org in ['npb','mlb']) {
        final relevant = games.where((g)=>org=='npb' ? [1,2].contains(g[5]) : [3,4].contains(g[5])).toList();
        if (relevant.isEmpty) continue;
        try {
          final url = Uri.parse('https://baseball.yahoo.co.jp/$org/schedule/?date=${date.replaceAll('-','')}');
          final doc = await YahooHtml.fetchDocument(url);
          final seen = <String>{};
          for (final link in doc.querySelectorAll('a[href*="/game/"]')) {
            final href = link.attributes['href']!;
            final match = RegExp(r'/(npb|mlb)/game/\d+').firstMatch(href);
            if (match == null || !seen.add(match[0]!)) continue;
            final topUrl = url.resolve('${match[0]}/top');
            final top = await YahooHtml.fetchDocument(topUrl);
            final headings = top.querySelectorAll('#benc_mem > .bb-splits .bb-splitsHead').map((e)=>e.text.trim()).toList();
            if (headings.length != 2) continue;
            final targets = relevant.where((g)=>'${g[3]}'==headings[0] && '${g[4]}'==headings[1]).toList();
            if (targets.length != 1) continue;
            final g = targets.single;
            await GameBench.save(conn,top,g[0] as int,g[1] as int,g[2] as int);
            print('$date game=${g[0]} bench=${parseGameBench(top,g[1] as int,g[2] as int).length}');
          }
        } catch(e) { print('$date $org bench fetch failed: $e'); }
      }
    }
  });
  exit(0);
}
