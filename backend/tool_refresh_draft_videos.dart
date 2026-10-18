import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/DraftVideos.dart';

/// Run from backend: dart run tool_refresh_draft_videos.dart [year]
/// Updates bundled metadata only. The app never searches videos per player.
Future<void> main(List<String> args) async {
  final year = args.isEmpty ? 2026 : int.parse(args.first);
  final file = File('assets/data/draft_$year.json');
  final data = jsonDecode(file.readAsStringSync()) as Map<String,dynamic>;
  final players = (data['players'] as List).cast<Map<String,dynamic>>();
  final client = http.Client();
  final checked = DateTime.now().toUtc().toIso8601String();
  var matched = 0, failed = 0;
  try {
    for (var offset=0;offset<players.length;offset+=1) {
      await Future.wait(players.skip(offset).take(1).map((p) async {
        if (p['feature_video_checked_at'] != null && !args.contains('--refresh')) return;
        try {
          final uri=Uri.https('www.youtube.com','/results',{'search_query':'${p['name']} 野球','sp':'CAMSAhAB','hl':'ja'});
          final response=await client.get(uri,headers:{'user-agent':'Mozilla/5.0','accept-language':'ja'}).timeout(const Duration(seconds:25));
          if(response.statusCode!=200) throw HttpException('HTTP ${response.statusCode}');
          final videos=draftFeatureVideos(utf8.decode(response.bodyBytes), '${p['name']}');
          p['feature_videos']=videos.map((v)=>{...v,'checked_at':checked,'search_url':uri.toString()}).toList();
          p['feature_video_checked_at']=checked;
          p['feature_video_status']='ok';
          if(videos.isNotEmpty) matched++;
          print('${p['name']}: ${videos.length} candidates${videos.isEmpty?'':' / ${videos.first['view_count']} views'}');
        } catch(e) {failed++; p['feature_video_status']='unavailable'; stderr.writeln('${p['name']}: video search unavailable');}
      }));
      if (failed > 0) break; // Back off on provider failures; keep already saved videos.
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    data['feature_video_audit']={'checked_at':checked,'matched_players':players.where((p) => (p['feature_videos'] as List? ?? []).isNotEmpty).length,'failed_players':failed,'scope':'YouTube再生数順検索。氏名がタイトルにある通常動画の取得結果内で比較。'};
    file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(data)}\n');
    print('matched=$matched failed=$failed');
  } finally {client.close();}
}
