import 'dart:convert';
import 'package:test/test.dart';
import '../app/DraftVideos.dart';
void main() {
  test('Select named features by numerical views, excluding Shorts and game broadcasts', () {
    Map row(String id, String title, String views, {String? url}) => {'videoRenderer': {'videoId': id, 'title': {'simpleText': title}, 'viewCountText': {'simpleText': views}, if(url != null) 'url':url}};
    final html='var ytInitialData = ${jsonEncode({'contents': {'twoColumnSearchResultsRenderer': {'primaryContents': [
      row('aaa00000001','柴﨑 聖人 密着','900 回視聴'),
      row('aaa00000002','柴崎聖人 特集','12,000 回視聴'),
      row('aaa00000003','別の選手 特集','100,000 回視聴'),
      row('aaa00000004','柴崎聖人','200,000 回視聴',url:'/shorts/aaa00000004'),
      row('aaa00000005','柴崎聖人 先発 全打席ハイライト','900,000 回視聴'),
    ]}}})};';
    final videos=draftFeatureVideos(html,'柴崎聖人');
    expect(videos.map((v)=>v['video_id']),['aaa00000002','aaa00000001']);
    expect(videos.first['view_count'],12000);
  });
}
