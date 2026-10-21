import 'dart:convert';
import 'package:test/test.dart';
import '../app/VideoContentFilter.dart';
import '../app/VideoChannels.dart';
import '../app/TverFeed.dart';
import '../app/VideoFeed.dart';

void main() {
  test('TVer team episodes move to teams and general episodes join programs', () {
    final team = videoChannels.firstWhere((c) => c.tabLabel == '阪神');
    final tver = videoChannels.singleWhere((c) => c.id == 'tver');
    final grouped = groupVideoChannels([team, tver], [
      {...team.toJson(), 'status':'ok', 'videos': <Map<String,dynamic>>[]},
      {...tver.toJson(), 'status':'ok', 'videos': [
        {'id':'epteam', 'title':'阪神タイガースの特集', 'platform':'tver'},
        {'id':'epdraft', 'title':'プロ野球ドラフト特番', 'platform':'tver'},
      ]},
    ]);
    expect(grouped.where((c) => c['category'] == 'tver'), isEmpty);
    expect((grouped.firstWhere((c) => c['id'] == team.id)['videos'] as List).map((v) => v['id']), ['epteam']);
    expect((grouped.firstWhere((c) => c['category'] == 'program')['videos'] as List).map((v) => v['id']), ['epdraft']);
  });

  test('mixed channels include baseball and exclude unrelated subjects', () {
    expect(matchesVideoContent('baseball', '野球球団の経営を考える'), isTrue);
    expect(matchesVideoContent('baseball', '大谷翔平の価値'), isTrue);
    expect(matchesVideoContent('baseball', 'サッカー日本代表の経営'), isFalse);
    expect(matchesVideoContent('baseball', 'AIと経営'), isFalse);
  });
  test('Hakutsuru requires Satozaki and a baseball guest', () {
    expect(matchesVideoContent('satozaki', '里崎智也と鳥谷敬が対談'), isTrue);
    expect(
        matchesVideoContent('satozaki', '乾杯！',
            description: '里崎智也が元プロ野球選手をゲストに迎えます。'),
        isTrue);
    for (final title in [
      '里崎智也と鈴木啓太',
      '里崎と松本薫',
      '里崎と大友愛',
      '里崎の日本酒レビュー',
      '鳥谷敬の日本酒'
    ]) {
      expect(matchesVideoContent('satozaki', title), isFalse, reason: title);
    }
    expect(
        matchesVideoContent('satozaki', '里崎と鈴木啓太',
            description: 'サッカー対談 https://example.com 鳥谷敬の関連動画'),
        isFalse);
  });
  test('channel search reads only selected channel results and excludes Shorts',
      () {
    const id = 'UC8yHePe_RgUBE-waRWy6olw';
    final html = 'var ytInitialData = ${jsonEncode({
          'metadata': {
            'channelMetadataRenderer': {'externalId': id}
          },
          'contents': {
            'twoColumnBrowseResultsRenderer': {
              'tabs': [
                {
                  'expandableTabRenderer': {
                    'title': '検索',
                    'selected': true,
                    'content': [
                      {
                        'videoRenderer': {
                          'videoId': 'regular0001',
                          'title': {'simpleText': '野球経営'}
                        }
                      },
                      {
                        'videoRenderer': {
                          'videoId': 'short000001',
                          'title': {'simpleText': '野球'},
                          'url': '/shorts/short000001'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          }
        })};';
    expect(
        parseRegularVideosPage(html, id, tab: 'search')
            .videos
            .map((v) => v['id']),
        ['regular0001']);
    expect(() => parseRegularVideosPage(html, 'wrong', tab: 'search'),
        throwsFormatException);
  });
  final now = DateTime.utc(2026, 10, 18);
  Map<String, dynamic> episode(String id,
          {String title = 'プロ野球ドラフト',
          bool available = true,
          int? end,
          String? thumbnail}) =>
      {
        'type': 'episode',
        'content': {
          'id': id,
          'title': title,
          'isAvailable': available,
          'endAt': end ??
              now.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
          'thumbnailPath': thumbnail ?? '/images/$id.jpg',
          'broadcastDateLabel': '10月17日(土) 20:00',
          'broadcasterName': '放送局',
        }
      };
  test(
      'TVer includes only available baseball episodes, deduplicates, normalizes date',
      () {
    final parsed = parseTverSearch({
      'code': 0,
      'result': {
        'contents': [
          episode('epone'),
          episode('epone'),
          episode('eptwo', title: 'サッカー'),
          episode('epexpired', end: now.millisecondsSinceEpoch ~/ 1000),
          episode('epunavailable', available: false),
          episode('epbadimage', thumbnail: 'https://example.com/image.jpg'),
          {'type': 'series', 'content': episode('epseries')['content']},
        ]
      }
    }, now);
    expect(parsed, hasLength(1));
    expect(parsed.single['url'], 'https://tver.jp/episodes/epone');
    expect(parsed.single['published_sort_at'], '2026-10-17T11:00:00.000Z');
    expect(parsed.single['platform'], 'tver');
    final tver = videoChannels.singleWhere((c) => c.id == 'tver');
    expect(selectChannelVideos(tver, parsed, now), hasLength(1));
    expect(selectChannelVideos(tver, parsed, now.add(const Duration(days: 2))),
        isEmpty);
  });
  test(
      'TVer routes only classified professional baseball, including old cached entries',
      () {
    final npb = videoChannels.singleWhere((c) => c.id == 'tver');
    final mlb = mlbVideoChannels.singleWhere((c) => c.id == 'tver');
    final titles = {
      'npb': 'プロ野球ドラフト会議',
      'team': '阪神タイガース 優勝への道',
      'mlb': '大リーグ ワールドシリーズ',
      'player': '大谷翔平 ドジャースの激闘',
      'wbc': 'WBC 大谷翔平とMLBのスター',
      'kids': '小学生の野球大会',
      'school': '高校野球 甲子園への道',
      'unknown': '野球の未来',
      'mixed': 'NPBとMLBの最新ニュース',
    };
    final cached = [
      for (final entry in titles.entries)
        {'id': entry.key, 'title': entry.value}
    ];
    expect(filterVideoOrganization(npb, cached).map((v) => v['id']),
        ['npb', 'team', 'wbc']);
    expect(filterVideoOrganization(mlb, cached).map((v) => v['id']),
        ['mlb', 'player']);
    final parsed = parseTverSearch({
      'code': 0,
      'result': {
        'contents': [
          for (final entry in titles.entries)
            episode('ep${entry.key}', title: entry.value)
        ]
      }
    }, now);
    expect(parsed.map((v) => v['id']),
        ['epnpb', 'epteam', 'epmlb', 'epplayer', 'epwbc']);
  });
  test('new channels preserve NPB MLB and WBC separation', () {
    final npb = videoChannels.singleWhere((c) => c.name == 'PIVOT【野球関連】');
    final mlb = mlbVideoChannels.singleWhere((c) => c.id == npb.id);
    final input = [
      {'id': 'a', 'title': '野球の未来'},
      {'id': 'b', 'title': '大谷翔平 ドジャースの優勝'},
      {'id': 'c', 'title': 'WBCの大谷翔平'},
      {'id': 'draft', 'title': '【ドラフト戦略】大谷翔平・山本由伸 MLBとの育成の違い'},
      {'id': 'draft2', 'title': 'ドラフト会議を解説'},
    ];
    expect(filterVideoOrganization(npb, input).map((v) => v['id']), ['a', 'c', 'draft', 'draft2']);
    expect(filterVideoOrganization(mlb, input).map((v) => v['id']), ['b']);
  });
  test('メジャー流出・移籍はNPB、新チャンネルは対象動画だけを表示', () {
    final pivot = videoChannels.singleWhere((c)=>c.name=='PIVOT【野球関連】');
    final mlb = mlbVideoChannels.singleWhere((c)=>c.id==pivot.id);
    final videos = [
      {'id':'out','title':'メジャー流出が止まらない MLBへの移籍'},
      {'id':'move','title':'山本由伸のメジャー移籍を振り返る'},
      {'id':'game','title':'MLB ドジャースの試合'},
    ];
    expect(filterVideoOrganization(pivot,videos).map((v)=>v['id']),['out','move']);
    expect(filterVideoOrganization(mlb,videos).map((v)=>v['id']),['game']);
    final news = videoChannels.singleWhere((c)=>c.id=='UCUQ0AtI3k10_CyLYcu4WRVA');
    expect(broadcastVideoTeams(news,'中日ドラゴンズ 新入団選手会見'),{'UC57LcTUKgjDg_K_VJXnmCTg'});
    expect(broadcastVideoTeams(news,'名古屋市の交通ニュース'),isEmpty);
    final play = videoChannels.singleWhere((c)=>c.id=='UCfjDQXxizH9OOdGGJcZ9uEQ');
    expect(matchesVideoContent(play.contentFilter,'古田敦也がプロ野球を語る'),isTrue);
    expect(matchesVideoContent(play.contentFilter,'前園真聖のサッカー対談'),isFalse);
  });

}
