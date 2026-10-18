import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../app/VideoChannels.dart';
import '../app/VideoClassification.dart';
import '../app/VideoTeamRouting.dart';
import '../app/VideoFeed.dart';

http.Response response(String body, int status) => http.Response(body, status,
    headers: {'content-type': 'text/plain; charset=utf-8'});

const channel = VideoChannel(
    'UC1234567890123456789012', 'テスト球団', 'teams', 'https://example.com');
String feed({String id = 'oldVideo001'}) => '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:yt="http://www.youtube.com/xml/schemas/2015">
<yt:channelId>${channel.id}</yt:channelId>
<entry><yt:videoId>$id</yt:videoId><title>練習 &amp; インタビュー</title><published>2026-10-01T10:00:00Z</published></entry>
<entry><yt:videoId>newVideo002</yt:videoId><title>最新動画</title><published>2026-10-02T10:00:00Z</published></entry>
<entry><yt:videoId>newVideo002</yt:videoId><title>重複</title><published>2026-10-02T10:00:00Z</published></entry>
<entry><yt:videoId>future00003</yt:videoId><title>公開前</title><published>2099-10-01T10:00:00Z</published></entry>
</feed>''';
String page({String? id, String title = '動画'}) =>
    'var ytInitialData = ${jsonEncode({
          'metadata': {
            'channelMetadataRenderer': {'externalId': id ?? channel.id}
          },
          'contents': {
            'twoColumnBrowseResultsRenderer': {
              'tabs': [
                {
                  'tabRenderer': {
                    'selected': true,
                    'title': title,
                    'content': {
                      'richGridRenderer': {
                        'contents': [
                          {
                            'lockupViewModel': {
                              'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
                              'contentId': 'future00003',
                              'contentImage': {'badge': '配信予定'},
                              'metadata': {
                                'lockupMetadataViewModel': {
                                  'title': {'content': '公開前'}
                                }
                              }
                            }
                          },
                          {
                            'lockupViewModel': {
                              'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
                              'contentId': 'newVideo002',
                              'metadata': {
                                'lockupMetadataViewModel': {
                                  'title': {'content': '日本語の"引用"と {括弧}'},
                                  'metadata': {
                                    'contentMetadataViewModel': {
                                      'metadataRows': [
                                        {
                                          'metadataParts': [
                                            {
                                              'text': {'content': '2 日前'}
                                            }
                                          ]
                                        }
                                      ]
                                    }
                                  }
                                }
                              }
                            }
                          },
                          {
                            'videoRenderer': {
                              'videoId': 'oldVideo001',
                              'title': {
                                'runs': [
                                  {'text': '旧形式'}
                                ]
                              },
                              'publishedTimeText': {'simpleText': '3 日前'}
                            }
                          },
                        ]
                      }
                    }
                  }
                },
                {
                  'tabRenderer': {
                    'title': 'ホーム',
                    'content': {
                      'videoRenderer': {
                        'videoId': 'unrelated01',
                        'title': {'simpleText': '対象外'}
                      }
                    }
                  }
                },
              ]
            }
          },
        })};';

String regularPage(List<Map<String, dynamic>> items, {String? token}) =>
    '"INNERTUBE_CLIENT_VERSION":"test-version"; var ytInitialData = ${jsonEncode({
          'metadata': {
            'channelMetadataRenderer': {'externalId': channel.id}
          },
          'contents': {
            'twoColumnBrowseResultsRenderer': {
              'tabs': [
                {
                  'tabRenderer': {
                    'selected': true,
                    'title': '動画',
                    'content': {
                      'richGridRenderer': {
                        'contents': [
                          ...items,
                          if (token != null)
                            {
                              'continuationItemRenderer': {
                                'continuationEndpoint': {
                                  'continuationCommand': {'token': token}
                                }
                              }
                            },
                        ]
                      }
                    }
                  }
                }
              ]
            }
          }
        })};';

Map<String, dynamic> item(int index, {String label = '1 時間前'}) => {
      'videoRenderer': {
        'videoId': 'v${index.toString().padLeft(10, '0')}',
        'title': {'simpleText': '動画$index'},
        'publishedTimeText': {'simpleText': label}
      }
    };
String watch(String id, DateTime date) =>
    'var ytInitialPlayerResponse = ${jsonEncode({
          'videoDetails': {'videoId': id, 'channelId': channel.id},
          'microformat': {
            'playerMicroformatRenderer': {'publishDate': date.toIso8601String()}
          },
        })};';

void main() {
  test('WBC always takes priority over MLB names and league tags', () {
    for (final title in [
      '【WBC】大谷翔平とドジャースのMLB選手',
      'WBC2026 アメリカ代表を解説',
      '２０２６ＷＢＣ MLB組の参加',
      'ワールド・ベースボール・クラシック メジャー選手の活躍',
      'World Baseball Classic: Yankees players',
      'w.b.c. ドジャース選手',
      'NPBとMLBのWBC代表比較',
    ]) {
      expect(videoOrganizations(title), {'npb'}, reason: title);
    }
    expect(videoOrganizations('MLBワールドシリーズ ドジャース'), {'mlb'});
    expect(isWbcVideo('AWBCanalysis'), isFalse);
  });
  test('cached WBC videos move to NPB for both experts and MNsports', () {
    for (final label in ['MNsports', '武田一浩チャンネル']) {
      final npb = videoChannels.singleWhere((c) => c.name == label);
      final mlb = mlbVideoChannels.singleWhere((c) => c.id == npb.id);
      final cached = {...npb.toJson(), 'status': 'stale', 'videos': [
        {'id': 'wbc', 'title': 'WBC 大谷翔平とドジャースのMLB選手', 'published_at': '2026-03-01T00:00:00Z'},
      ]};
      final npbResult = groupVideoChannels([npb], [cached]);
      final mlbResult = groupVideoChannels([mlb], [cached]);
      expect((npbResult.single['videos'] as List).single['id'], 'wbc');
      expect(mlbResult.single['videos'], isEmpty);
      expect(selectChannelVideos(npb, (cached['videos'] as List).cast<Map<String,dynamic>>(), DateTime.utc(2026,10,19)), hasLength(1));
    }
  });

  test('single-team expert videos move exclusively without being lost to team limits', () {
    final team = videoChannels.singleWhere((c) => c.tabLabel == '巨人');
    final expert = videoChannels.singleWhere((c) => c.tabLabel == '武田一浩');
    final clips = [
      {'id': 'one', 'title': '巨人の戦力分析', 'published_at': '2026-01-01T00:00:00Z'},
      {'id': 'two', 'title': '巨人と阪神の比較'},
      {'id': 'broad', 'title': '巨人は何位？12球団順位予想'},
      {'id': 'unknown', 'title': '投球フォーム解説'},
    ];
    final result = groupVideoChannels([team, expert], [
      {...team.toJson(), 'status': 'ok', 'videos': [
        for (var i=0;i<30;i++) {'id': 'official$i', 'title': '練習', 'published_at': '2026-10-01T00:00:00Z'},
      ]},
      {...expert.toJson(), 'status': 'ok', 'videos': clips},
    ]);
    final teamVideos = result.first['videos'] as List;
    expect(teamVideos.where((v) => v['id'] == 'one'), hasLength(1));
    expect(teamVideos.last['source_name'], '武田一浩チャンネル');
    expect(result.first['display_mode'], 'all');
    expect((result.last['videos'] as List).map((v) => v['id']), ['two', 'broad', 'unknown']);
    expect(expertVideoTeam('MLBデトロイト・タイガースの戦力'), 'mlb-team-tigers');
    expect(expertVideoTeam('MLBジャイアンツの補強'), 'mlb-team-giants');
    expect(expertVideoTeam('NPBとMLB 巨人の育成を比較'), isNull);
  });
  test('MLB expert single-team clips move into dated team groups with attribution', () {
    final expert = mlbVideoChannels.singleWhere((c) => c.tabLabel == '武田一浩');
    final result = groupVideoChannels([expert], [{
      ...expert.toJson(), 'status': 'partial', 'videos': [
        {'id': 'old', 'title': 'ドジャースの補強', 'published_at': '2026-10-01T00:00:00Z'},
        {'id': 'new', 'title': 'ドジャースの戦力', 'published_at': '2026-10-02T00:00:00Z'},
        {'id': 'many', 'title': 'ドジャースとヤンキースの対戦'},
      ],
    }]);
    expect((result.first['videos'] as List).map((v) => v['id']), ['many']);
    final team = result.singleWhere((c) => c['id'] == 'mlb-team-dodgers');
    expect(team['category'], 'mlb_teams');
    expect(team['status'], 'partial');
    expect((team['videos'] as List).map((v) => v['id']), ['new', 'old']);
    expect(team['videos'][0]['source_name'], '武田一浩チャンネル');
  });

  test('all experts are available in both leagues and unknown videos go to NPB', () {
    final expert = videoChannels.singleWhere((c) => c.tabLabel == '武田一浩');
    expect(expert.id, 'UCXvYPXTrbyjr0uCIWOrH6Mw');
    final mlb = mlbVideoChannels.singleWhere((c) => c.id == expert.id);
    final clips = [
      {'id': 'npb', 'title': '阪神の投手陣を解説'},
      {'id': 'mlb', 'title': 'ドジャース大谷翔平の活躍'},
      {'id': 'unknown', 'title': '投球フォームの基本'},
      {'id': 'both', 'title': 'NPBとMLBの違い'},
    ];
    expect(filterVideoOrganization(expert, clips).map((v) => v['id']), ['npb', 'unknown', 'both']);
    expect(filterVideoOrganization(mlb, clips).map((v) => v['id']), ['mlb', 'both']);
    for (final original in videoChannels.where((c) => c.category == 'ob')) {
      final copy = mlbVideoChannels.singleWhere((c) => c.id == original.id);
      expect(copy.daily, original.daily);
      expect(copy.limit, original.limit);
      expect(copy.tabLabel, original.tabLabel);
    }
    final cached = {...expert.toJson(), 'status': 'stale', 'videos': clips};
    expect((groupVideoChannels([mlb], [cached]).first['videos'] as List).map((v) => v['id']), ['both']);
    expect((groupVideoChannels([expert], [cached]).single['videos'] as List).map((v) => v['id']), ['npb', 'unknown', 'both']);
  });

  test(
      'progress counts completed channels, including failures, without fetching on polls',
      () async {
    const first =
        VideoChannel('UC1234567890123456789012', '一つ目', 'league', 'x');
    const second =
        VideoChannel('UC1234567890123456789013', '二つ目', 'league', 'x');
    final pending = Completer<http.Response>();
    var calls = 0;
    final service = VideoFeedService(
        channels: [first, second],
        client: MockClient((request) async {
          calls++;
          if (request.url.path.contains(second.id)) return pending.future;
          return response(page(id: first.id), 200);
        }));
    addTearDown(service.dispose);
    final loading = service.read();
    await Future<void>.delayed(Duration.zero);
    expect(service.cached()['progress'],
        {'active': true, 'completed': 1, 'total': 2, 'percent': 50});
    expect(calls, 2);
    pending.complete(response('', 503));
    await loading;
    expect(service.cached()['progress'],
        {'active': false, 'completed': 2, 'total': 2, 'percent': 100});
    expect(calls, 2);
  });

  test('日時取得失敗時も23時間前を4週間前より先に並べ、推定値を公開日時にしない', () {
    final reference = DateTime.utc(2026, 10, 18, 3);
    final values = [
      withVideoSortTime({'id': 'old', 'published_label': '4 週間前'}, reference),
      withVideoSortTime({'id': 'new', 'published_label': '23 時間前'}, reference),
      withVideoSortTime(
          {'id': 'middle', 'published_label': '3 days ago'}, reference),
      withVideoSortTime({
        'id': 'exact',
        'published_at': '2026-10-18T00:00:00Z',
        'published_label': '1 日前'
      }, reference),
    ];
    expect(sortVideosByPublishedAt(values).map((v) => v['id']),
        ['exact', 'new', 'middle', 'old']);
    expect(values.first.containsKey('published_at'), isFalse);
    expect(values.last.containsKey('published_sort_at'), isFalse);
    expect(estimateVideoPublishedAt('6 か月前', reference),
        reference.subtract(const Duration(days: 180)));
  });

  test('混在動画はタイムゾーンを考慮して新しい順、日時不明は末尾に保持する', () {
    final sorted = sortVideosByPublishedAt([
      {'id': 'unknown1'},
      {'id': 'old', 'published_at': '2026-10-18T09:30:00+09:00'},
      {'id': 'new', 'published_at': '2026-10-18T01:00:00Z'},
      {'id': 'unknown2', 'published_at': 'invalid'},
      {'id': 'same', 'published_at': '2026-10-18T10:00:00+09:00'},
    ]);
    expect(sorted.map((v) => v['id']),
        ['new', 'same', 'old', 'unknown1', 'unknown2']);
    expect(
        videoChannels
            .where((c) => c.category == 'teams' || c.category == 'related')
            .every((c) => c.limit == 30),
        isTrue);
  });

  test('パテレは日本時間の2日前から全件、10件未満なら期間外から補完する', () {
    final pl = videoChannels.first;
    expect(pl.lookbackDays, 2);
    expect(pl.minimumVideos, 10);
    expect(
        videoChannels
            .where((c) => c.id != pl.id)
            .every((c) => c.minimumVideos == 0 && c.lookbackDays == 1),
        isTrue);
    final now = DateTime.utc(2026, 10, 18, 3);
    final boundary = DateTime.utc(2026, 10, 15, 15);
    expect(videoWindowStart(now, lookbackDays: 2), boundary);
    final recent = [
      for (var i = 0; i < 12; i++)
        {
          'id': 'r$i',
          'published_at': boundary.add(Duration(minutes: i)).toIso8601String()
        }
    ];
    final old = [
      for (var i = 0; i < 12; i++)
        {
          'id': 'old$i',
          'published_at':
              boundary.subtract(Duration(seconds: i + 1)).toIso8601String()
        }
    ];
    expect(selectChannelVideos(pl, [...old, ...recent], now), hasLength(12));
    final fallback = selectChannelVideos(
        pl,
        [
          ...old,
          ...recent.take(2),
          {
            'id': 'future',
            'published_at': now.add(const Duration(days: 1)).toIso8601String()
          }
        ],
        now);
    expect(fallback.map((v) => v['id']),
        ['r1', 'r0', for (var i = 0; i < 8; i++) 'old$i']);
    expect(selectChannelVideos(pl, recent.take(3).toList(), now), hasLength(3));
  });
  test('パテレの少数取得時は続きの古い通常動画から10件まで補う', () async {
    const pl = VideoChannel('UC1234567890123456789012', 'パテレ', 'league', 'x',
        daily: true, lookbackDays: 2, minimumVideos: 10);
    final now = DateTime.utc(2026, 10, 18, 3);
    var pages = 0;
    final service = VideoFeedService(
        channels: [pl],
        now: () => now,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/videos'))
            return response(
                regularPage([item(0, label: '2 日前'), item(1, label: '3 日前')],
                    token: 'next'),
                200);
          if (r.method == 'POST') {
            pages++;
            return response(
                jsonEncode({
                  'items': [for (var i = 2; i < 15; i++) item(i, label: '3 日前')]
                }),
                200);
          }
          if (r.url.path == '/watch') {
            final id = r.url.queryParameters['v']!;
            final i = int.parse(id.substring(1));
            return response(
                watch(
                    id,
                    DateTime.utc(2026, 10, 15, 15)
                        .subtract(Duration(seconds: i))),
                200);
          }
          return response('', 503);
        }));
    addTearDown(service.dispose);
    final result = await service.refresh();
    expect(pages, 1);
    expect(result['channels'][0]['status'], 'ok');
    expect(result['channels'][0]['videos'], hasLength(10));
    expect(service.cached()['channels'][0]['videos'], hasLength(10));
    expect(result['channels'][0]['lookback_days'], 2);
  });

  test('公式の新着30件があっても鷹BAKAとももスポの最新動画を残す', () {
    final team = videoChannels.firstWhere((c) => c.tabLabel == 'ソフトバンク');
    final related =
        videoChannels.where((c) => c.teamIds.contains(team.id)).toList();
    final result = groupVideoChannels([
      team,
      ...related
    ], [
      {
        ...team.toJson(),
        'status': 'ok',
        'videos': [
          for (var i = 0; i < 30; i++)
            {
              'id': 'official$i',
              'title': '公式動画',
              'published_at':
                  '2026-10-18T00:${(59 - i).toString().padLeft(2, '0')}:00Z'
            }
        ]
      },
      {
        ...related[0].toJson(),
        'status': 'ok',
        'videos': [
          {
            'id': 'momo',
            'title': 'ホークス取材',
            'published_at': '2026-10-03T00:00:00Z'
          }
        ]
      },
      {
        ...related[1].toJson(),
        'status': 'partial',
        'videos': [
          {'id': 'taka', 'title': '鷹BAKA最新', 'published_label': '1 週間前'},
          {'id': 'oldTaka', 'title': '鷹BAKA過去', 'published_label': '2 週間前'}
        ]
      },
    ]);
    final videos = result.single['videos'] as List;
    expect(videos, hasLength(30));
    expect(
        videos.map((v) => v['id']), containsAll(['official0', 'momo', 'taka']));
    expect(videos.any((v) => v['id'] == 'oldTaka'), isFalse);
    expect(videos.where((v) => v['id'] == 'taka').single['source_name'],
        '鷹BAKA軍団');
    expect(result.single['status'], 'partial');
  });

  test('チャンネル並列更新でもYouTubeへの同時GETは3件以内', () async {
    var active = 0, peak = 0;
    final definitions = [
      for (var i = 0; i < 8; i++)
        VideoChannel('UC${i.toString().padLeft(22, '0')}', '球団$i', 'teams', 'x')
    ];
    final service = VideoFeedService(
        channels: definitions,
        client: MockClient((r) async {
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          return response(page(id: r.url.pathSegments[1]), 200);
        }));
    addTearDown(service.dispose);
    await service.refresh();
    expect(peak, 3);
    expect(service.cached()['channels'], hasLength(8));
  });

  test('一部の公開日時取得失敗で取得済みの当日動画を消さない', () async {
    const daily = VideoChannel('UC1234567890123456789012', '日次', 'league', 'x',
        daily: true);
    final now = DateTime.utc(2026, 10, 18, 3);
    var refresh = false;
    final service = VideoFeedService(
        channels: [daily],
        now: () => now,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/videos'))
            return response(regularPage([item(refresh ? 2 : 1)]), 200);
          if (r.url.queryParameters['v'] == 'v0000000001')
            return response(watch('v0000000001', now), 200);
          return response('', 503);
        }));
    addTearDown(service.dispose);
    await service.refresh();
    refresh = true;
    final result = await service.refresh();
    expect(result['channels'][0]['status'], 'partial');
    expect(result['channels'][0]['videos'].single['id'], 'v0000000001');
  });

  test('複数配信元を球団別に統合し新着順30件・重複なし・配信元名を保持する', () {
    final team = videoChannels.firstWhere((c) => c.tabLabel == 'ソフトバンク');
    final related = videoChannels.firstWhere((c) => c.name == '鷹BAKA軍団');
    final expert = videoChannels.firstWhere((c) => c.tabLabel == '古田敦也');
    Map<String, dynamic> value(
            VideoChannel c, List<Map<String, dynamic>> videos) =>
        {...c.toJson(), 'status': 'ok', 'videos': videos};
    final result = groupVideoChannels([
      team,
      related,
      expert
    ], [
      value(team, [
        for (var i = 0; i < 30; i++)
          {
            'id': 'v$i',
            'title': '練習',
            'published_at': '2026-10-01T00:${i.toString().padLeft(2, '0')}:00Z'
          }
      ]),
      value(related, [
        {'id': 'r', 'title': '密着', 'published_at': '2026-10-02T00:00:00Z'},
        {'id': 'v9', 'title': '重複'}
      ]),
      value(expert, [
        {'id': 'e', 'title': 'ホークスの分析', 'published_at': '2026-10-03T00:00:00Z'},
        {
          'id': 'other',
          'title': 'MLBの分析',
          'published_at': '2026-10-04T00:00:00Z'
        }
      ]),
    ]);
    expect(result, hasLength(2));
    final videos = result.first['videos'] as List;
    expect(videos, hasLength(30));
    expect(videos.map((v) => v['id']).toSet(), hasLength(30));
    expect(videos.first['id'], 'e');
    expect(videos[1]['source_name'], '鷹BAKA軍団');
    expect(videos.any((v) => v['id'] == 'other'), isFalse);
    expect(
        videoChannels
            .where((c) => ['五十嵐亮太', '古田敦也', '宮本慎也'].contains(c.tabLabel)),
        hasLength(3));
  });
  test('古い動画が混在するページでも続きの前日動画を取得する', () async {
    const daily = VideoChannel('UC1234567890123456789012', '日次', 'league', 'x',
        daily: true);
    final now = DateTime.utc(2026, 10, 18, 3);
    var pages = 0;
    final service = VideoFeedService(
        channels: [daily],
        now: () => now,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/videos'))
            return response(
                regularPage([item(1), item(2, label: '3 日前')], token: 'next'),
                200);
          if (r.method == 'POST') {
            pages++;
            return response(
                jsonEncode({
                  'items': [item(3)]
                }),
                200);
          }
          if (r.url.path == '/watch')
            return response(watch(r.url.queryParameters['v']!, now), 200);
          return response('', 503);
        }));
    addTearDown(service.dispose);
    final result = await service.refresh();
    expect(pages, 1);
    expect(result['channels'][0]['videos'].map((v) => v['id']),
        containsAll(['v0000000001', 'v0000000003']));
  });
  test('ライブアーカイブも日本時間の前日境界で含め範囲外は除く', () async {
    const daily = VideoChannel(
        'UC1234567890123456789012', 'パテレ相当', 'league', 'x',
        daily: true, includeStreams: true);
    final now = DateTime.utc(2026, 10, 18, 3);
    final service = VideoFeedService(
        channels: [daily],
        now: () => now,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/videos'))
            return response(regularPage([item(1)]), 200);
          if (r.url.path.endsWith('/streams'))
            return response(
                regularPage([item(2), item(3)])
                    .replaceAll('"title":"動画"', '"title":"ライブ"'),
                200);
          if (r.url.path == '/watch')
            return response(
                watch(
                    r.url.queryParameters['v']!,
                    r.url.queryParameters['v'] == 'v0000000003'
                        ? videoWindowStart(now)
                            .subtract(const Duration(seconds: 1))
                        : videoWindowStart(now)),
                200);
          return response('', 503);
        }));
    addTearDown(service.dispose);
    final result = await service.refresh();
    expect(result['channels'][0]['status'], 'ok');
    expect(result['channels'][0]['videos'].map((v) => v['id']),
        ['v0000000001', 'v0000000002']);
  });

  test('ショート専用表示とshortsリンクを除外し短い通常動画は残す', () {
    final shorts = item(2);
    (shorts['videoRenderer'] as Map)['navigationEndpoint'] = {
      'commandMetadata': {
        'webCommandMetadata': {'url': '/shorts/v0000000002'}
      }
    };
    final result = parseVideoChannelPage(
        regularPage([
          item(1),
          shorts,
          {
            'reelItemRenderer': {
              'videoId': 'v0000000003',
              'title': {'simpleText': 'ショート'}
            }
          },
          {
            'shortsLockupViewModel': {'videoRenderer': item(4)['videoRenderer']}
          },
          item(5),
        ]),
        channel.id);
    expect(result.map((v) => v['id']), ['v0000000001', 'v0000000005']);
  });
  test('通常のキャッシュ読み取りは通信せず明示更新はTTL内でも再取得する', () async {
    var calls = 0;
    final service = VideoFeedService(
        channels: [channel],
        client: MockClient((_) async {
          calls++;
          return response(page(), 200);
        }));
    addTearDown(service.dispose);
    expect(service.cached()['channels'][0]['status'], 'loading');
    expect(calls, 0);
    await service.refresh();
    for (var i = 0; i < 10; i++) {
      expect(service.cached()['channels'][0]['videos'], hasLength(2));
    }
    expect(calls, 1);
    await service.refresh();
    expect(calls, 2);
  });
  test('サーバーのタイマーだけで定期取得する', () async {
    final second = Completer<void>();
    var calls = 0;
    final service = VideoFeedService(
        channels: [channel],
        client: MockClient((_) async {
          if (++calls == 2) second.complete();
          return response(page(), 200);
        }));
    addTearDown(service.dispose);
    await service.start(interval: const Duration(milliseconds: 20));
    await second.future.timeout(const Duration(seconds: 2));
    await service.refresh();
    expect(service.cached()['channels'][0]['videos'], hasLength(2));
  });
  test('保存済み動画を再起動時に復元して取得失敗時も保持する', () async {
    final directory = await Directory.systemTemp.createTemp('video-cache-test');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/snapshot.json';
    final first = VideoFeedService(
        channels: [channel],
        client: MockClient((_) async => response(page(), 200)));
    await first.start(snapshotPath: path);
    await first.refresh();
    first.dispose();
    expect(jsonDecode(await File(path).readAsString())['version'], 2);
    final gate = Completer<http.Response>();
    final second = VideoFeedService(
        channels: [channel], client: MockClient((_) => gate.future));
    addTearDown(second.dispose);
    await second.start(snapshotPath: path);
    expect(second.cached()['channels'][0]['videos'], hasLength(2));
    gate.complete(response('', 503));
    await second.refresh();
    expect(second.cached()['channels'][0]['status'], 'stale');
    expect(second.cached()['channels'][0]['videos'], hasLength(2));
  });
  test('MLB registry includes league sources and separately filtered MNsports',
      () {
    expect(
        mlbVideoChannels.where((c) => c.category == 'league').map((c) => c.id),
        ['UCJ-l-sMQFHogSy8KXRyMIRA', 'UCoLrcjPV5PbUrUyXq5mjc_A']);
    final shared =
        mlbVideoChannels.where((c) => videoChannels.any((n) => n.id == c.id));
    expect(shared.where((c) => c.category == 'ob'), hasLength(16));
    expect(shared.every((c) => c.videoOrg == 'mlb'), isTrue);
    expect(shared.where((c) => c.category == 'media').map((c) => c.name), containsAll(['MNsports', '熱闘ベースボールレコード', '4タコ【野球解説チャンネル】']));
  });
  test(
      'video league classification respects context and does not default to NPB',
      () {
    expect(videoOrganizations('ドジャース完敗！バウアーズのMVPに噛み付く兄！'), {'mlb'});
    expect(videoOrganizations('ゲレーロJr.が５億ドル契約を語り炎上！'), {'mlb'});
    expect(videoOrganizations('阪神と巨人の優勝争い'), {'npb'});
    expect(videoOrganizations('NPB時代の大谷翔平の記録'), {'npb'});
    expect(videoOrganizations('大谷の投球を解説'), {'mlb'});
    expect(videoOrganizations('佐々木朗希の投球を解説'), {'mlb'});
    expect(videoOrganizations('ロッテ時代の佐々木朗希'), {'npb'});
    expect(videoOrganizations('MLBジャイアンツの補強'), {'mlb'});
    expect(videoOrganizations('NPBとMLBの違い'), {'npb', 'mlb'});
    expect(videoOrganizations('ドジャースと阪神の対戦'), {'npb', 'mlb'});
    expect(videoOrganizations('混乱！ホームラン級の大飛球が屋根直撃！'), isEmpty);
  });
  test('MNsports mixed cache is filtered for media and NPB team aggregation',
      () {
    final npb = videoChannels.singleWhere((c) => c.name == 'MNsports');
    final mlb = mlbVideoChannels.singleWhere((c) => c.name == 'MNsports');
    final giants = videoChannels.singleWhere((c) => c.tabLabel == '巨人');
    final clips = [
      {
        'id': 'mlb',
        'title': 'MLBへ 元巨人投手の挑戦',
        'published_at': '2026-10-18T10:00:00Z'
      },
      {'id': 'npb', 'title': '巨人の優勝争い', 'published_at': '2026-10-18T09:00:00Z'},
      {
        'id': 'both',
        'title': 'NPBとMLBの違い',
        'published_at': '2026-10-18T08:00:00Z'
      },
      {'id': 'unknown', 'title': '最新ニュース'},
    ];
    final cached = {...npb.toJson(), 'status': 'stale', 'videos': clips};
    final npbResult = groupVideoChannels([
      npb,
      giants
    ], [
      cached,
      {...giants.toJson(), 'status': 'ok', 'videos': <Map<String, dynamic>>[]}
    ]);
    expect(
        (npbResult[0]['videos'] as List).map((v) => v['id']), ['npb', 'both']);
    expect((npbResult[1]['videos'] as List).map((v) => v['id']), ['npb']);
    final mlbResult = groupVideoChannels([mlb], [cached]);
    expect((mlbResult.single['videos'] as List).map((v) => v['id']),
        ['mlb', 'both']);
    expect(
        selectChannelVideos(npb, clips, DateTime.utc(2026, 10, 19))
            .map((v) => v['id']),
        ['npb', 'both']);
  });
  test('broadcast videos match baseball teams, not city or railway news', () {
    final ntv = videoChannels.singleWhere((c) => c.name == '日テレスポーツ【公式】');
    final asahi = videoChannels.singleWhere((c) => c.name == 'テレビ朝日スポーツ【公式】');
    final giants = videoChannels.singleWhere((c) => c.tabLabel == '巨人').id;
    final tigers = videoChannels.singleWhere((c) => c.tabLabel == '阪神').id;
    final lions = videoChannels.singleWhere((c) => c.tabLabel == '西武').id;
    for (final source in [ntv, asahi]) {
      expect(broadcastVideoTeams(source, 'プロ野球 巨人対阪神 ハイライト'), {giants, tigers});
      expect(broadcastVideoTeams(source, '【巨人】若手が躍動'), {giants});
      expect(broadcastVideoTeams(source, '広島でサッカー大会'), isEmpty);
      expect(broadcastVideoTeams(source, '楽天の新サービス'), isEmpty);
      expect(broadcastVideoTeams(source, '西武鉄道 新型車両'), isEmpty);
      expect(broadcastVideoTeams(source, 'バレーボール日本代表'), isEmpty);
    }
    for (final source
        in videoChannels.where((c) => ['テレ玉', 'テレ玉NEWS'].contains(c.name))) {
      expect(broadcastVideoTeams(source, '埼玉西武ライオンズ キャンプ'), {lions});
      expect(broadcastVideoTeams(source, 'LIONS CHANNEL 最新回'), {lions});
      expect(broadcastVideoTeams(source, '西武鉄道 ダイヤ改正'), isEmpty);
      expect(broadcastVideoTeams(source, '巨人 阪神 プロ野球'), isEmpty);
    }
  });
  test('broadcasters scan past unrelated news and cache only baseball uploads',
      () async {
    final directory = await Directory.systemTemp.createTemp('broadcast-test');
    addTearDown(() => directory.delete(recursive: true));
    const source =
        VideoChannel('UC1234567890123456789012', '放送局', 'broadcast', 'x');
    var continuations = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        continuations++;
        final video = item(2);
        video['videoRenderer']['title'] = {'simpleText': '巨人対阪神 ハイライト'};
        return response(
            jsonEncode({
              'contents': [video]
            }),
            200);
      }
      if (request.url.path.endsWith('/videos')) {
        return response(regularPage([item(1)], token: 'next'), 200);
      }
      if (request.url.path == '/watch') {
        return response(
            watch(
                request.url.queryParameters['v']!, DateTime.utc(2026, 10, 18)),
            200);
      }
      return response('', 404);
    });
    final service = VideoFeedService(client: client, channels: [source]);
    addTearDown(service.dispose);
    final path = '${directory.path}/snapshot.json';
    await service.start(snapshotPath: path);
    await service.read();
    final saved = jsonDecode(await File(path).readAsString());
    final videos = saved['channels'][0]['videos'] as List;
    expect(continuations, 1);
    expect(videos.map((v) => v['id']), ['v0000000002']);
    service.cached();
    expect(continuations, 1);
  });
  test('broadcast pagination failure retains already fetched baseball videos',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('broadcast-partial');
    addTearDown(() => directory.delete(recursive: true));
    const source =
        VideoChannel('UC1234567890123456789012', '放送局', 'broadcast', 'x');
    final client = MockClient((request) async {
      if (request.method == 'POST') return response('', 503);
      if (request.url.path.endsWith('/videos')) {
        final video = item(1);
        video['videoRenderer']['title'] = {'simpleText': '巨人対阪神 ハイライト'};
        return response(regularPage([video], token: 'next'), 200);
      }
      if (request.url.path == '/watch') {
        return response(
            watch(
                request.url.queryParameters['v']!, DateTime.utc(2026, 10, 18)),
            200);
      }
      return response('', 404);
    });
    final service = VideoFeedService(client: client, channels: [source]);
    addTearDown(service.dispose);
    final path = '${directory.path}/snapshot.json';
    await service.start(snapshotPath: path);
    await service.read();
    final cached = jsonDecode(await File(path).readAsString())['channels'][0];
    expect(cached['status'], 'partial');
    expect((cached['videos'] as List).single['id'], 'v0000000001');
  });
  test(
      'broadcast sources stay hidden and matching games appear in both teams chronologically',
      () {
    final teams = videoChannels
        .where((c) => ['巨人', '阪神', '西武'].contains(c.tabLabel))
        .toList();
    final sources =
        videoChannels.where((c) => c.category == 'broadcast').toList();
    final definitions = [...teams, ...sources];
    final result = groupVideoChannels(definitions, [
      for (final channel in definitions)
        {
          ...channel.toJson(),
          'status': 'ok',
          'videos': [
            if (channel == sources[0])
              {
                'id': 'game',
                'title': '巨人対阪神 プロ野球',
                'published_at': '2026-10-18T03:00:00Z'
              },
            if (channel == sources[1])
              {
                'id': 'older',
                'title': '【巨人】練習',
                'published_at': '2026-10-17T03:00:00Z'
              },
            if (channel == sources[2]) ...[
              {
                'id': 'lions',
                'title': 'LIONS CHANNEL',
                'published_at': '2026-10-18T02:00:00Z'
              },
              {'id': 'news', 'title': '西武鉄道のニュース'},
            ],
            if (channel == sources[3])
              {
                'id': 'local',
                'title': 'ライオンズの始球式',
                'published_at': '2026-10-18T04:00:00Z'
              },
          ],
        }
    ]);
    expect(result, hasLength(3));
    expect(
        (result[0]['videos'] as List).map((v) => v['id']), ['game', 'older']);
    expect((result[1]['videos'] as List).map((v) => v['id']), ['game']);
    expect(
        (result[2]['videos'] as List).map((v) => v['id']), ['local', 'lions']);
  });
  test('48チャンネルに指定先と12球団が重複なく含まれる', () {
    expect(videoChannels, hasLength(48));
    expect(videoChannels.map((c) => c.id).toSet(), hasLength(48));
    expect(videoChannels.where((c) => c.category == 'teams'), hasLength(12));
    for (final label in [
      '近藤健介',
      '落合博満',
      '杉谷拳士',
      '大久保博元',
      '片岡篤史',
      '江川卓',
      '谷繁元信'
    ]) {
      final expert = videoChannels.singleWhere((c) => c.tabLabel == label);
      expect(expert.category, 'ob');
    }

    for (final name in [
      '上原浩治の雑談魂',
      'Satozaki Channel',
      '和田毅ラボ',
      'Baseball inc. / ベースボールインク',
      'MNsports'
    ]) {
      expect(videoChannels.any((c) => c.name == name), isTrue);
    }
  });
  test('球団は30件、不定期有識者は4件、解説チャンネルは10件、日次は日本時間の当日と前日だけ', () {
    final now = DateTime.utc(2026, 10, 18, 3);
    final boundary = DateTime.utc(2026, 10, 16, 15);
    expect(videoWindowStart(now), boundary);
    final videos = [
      for (var i = 0; i < 40; i++)
        {
          'id': '$i',
          'published_at': boundary.add(Duration(minutes: i)).toIso8601String()
        },
      {
        'id': 'old',
        'published_at':
            boundary.subtract(const Duration(seconds: 1)).toIso8601String()
      },
      {
        'id': 'future',
        'published_at': now.add(const Duration(seconds: 1)).toIso8601String()
      },
    ];
    expect(selectChannelVideos(channel, videos, now), hasLength(30));
    const sparse = VideoChannel('x', 'x', 'ob', 'x');
    const media = VideoChannel('x', 'x', 'media', 'x');
    const daily = VideoChannel('x', 'x', 'league', 'x', daily: true);
    expect(selectChannelVideos(sparse, videos, now), hasLength(4));
    expect(selectChannelVideos(media, videos, now), hasLength(10));
    expect(selectChannelVideos(daily, videos, now), hasLength(40));
    expect(selectChannelVideos(daily, videos, now).any((v) => v['id'] == 'old'),
        isFalse);
  });
  test('公開動画一覧が100件を超えても続きの当日・前日分を取得する', () async {
    const daily = VideoChannel('UC1234567890123456789012', '日次', 'league', 'x',
        daily: true);
    var continuations = 0, watchCalls = 0;
    final now = DateTime.utc(2026, 10, 18, 3);
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/videos'))
        return response(
            regularPage([for (var i = 0; i < 100; i++) item(i)],
                token: 'next-page'),
            200);
      if (r.url.path == '/youtubei/v1/browse') {
        expect(jsonDecode(r.body)['continuation'], 'next-page');
        continuations++;
        return response(
            jsonEncode({
              'onResponseReceivedActions': [
                {
                  'appendContinuationItemsAction': {
                    'continuationItems': [
                      item(99),
                      for (var i = 100; i < 120; i++) item(i),
                      item(121, label: '2 日前'),
                    ]
                  }
                },
              ]
            }),
            200);
      }
      if (r.url.path.contains('/feeds/')) return response('', 503);
      watchCalls++;
      final id = r.url.queryParameters['v']!;
      final index = int.parse(id.substring(1));
      return response(
          watch(
              id,
              index < 115
                  ? now.subtract(const Duration(hours: 2))
                  : videoWindowStart(now).subtract(const Duration(seconds: 1))),
          200);
    });
    final service =
        VideoFeedService(client: client, channels: [daily], now: () => now);
    final result = await service.read();
    expect(result['channels'][0]['status'], 'ok');
    expect(result['channels'][0]['videos'], hasLength(115));
    expect(continuations, 1);
    expect(watchCalls, 120);
  });
  test('日次動画はAtomの正確な日時を使い個別ページ取得が失敗しても表示する', () async {
    const daily = VideoChannel('UC1234567890123456789012', '里崎相当', 'ob', 'x',
        daily: true);
    var watchCalls = 0;
    final service = VideoFeedService(
        channels: [daily],
        now: () => DateTime.utc(2026, 10, 2, 12),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/videos'))
            return response(
                page().replaceAll('2 日前', '1 時間前').replaceAll('3 日前', '1 日前'),
                200);
          if (r.url.path.contains('/feeds/')) return response(feed(), 200);
          watchCalls++;
          return response('', 503);
        }));
    addTearDown(service.dispose);
    final result = await service.refresh();
    expect(result['channels'][0]['videos'], hasLength(2));
    expect(watchCalls, 0);
    expect(result['channels'][0]['status'], 'ok');
  });
  test('公開日時が取得できない動画は推測で混ぜず一部取得失敗を示す', () async {
    const daily = VideoChannel('UC1234567890123456789012', '日次', 'league', 'x',
        daily: true);
    final now = DateTime.utc(2026, 10, 18, 3);
    final service = VideoFeedService(
        channels: [daily],
        now: () => now,
        client: MockClient((r) async => r.url.path.endsWith('/videos')
            ? response(regularPage([item(1), item(2)]), 200)
            : r.url.queryParameters['v'] == 'v0000000001'
                ? response(watch('v0000000001', now), 200)
                : response('error', 503)));
    final result = await service.read();
    expect(result['channels'][0]['status'], 'partial');
    expect(result['channels'][0]['videos'], hasLength(1));
  });
  test('Atomは新着順、重複と公開前を除外し文字参照を復元する', () {
    final videos =
        parseVideoFeed(feed(), channel.id, now: DateTime.utc(2026, 10, 18));
    expect(videos.map((v) => v['id']), ['newVideo002', 'oldVideo001']);
    expect(videos.last['title'], '練習 & インタビュー');
    expect(videos.first['thumbnail_url'],
        'https://i.ytimg.com/vi/newVideo002/hqdefault.jpg');
    expect(() => parseVideoFeed(feed(), 'other'), throwsFormatException);
  });
  test('チャンネルページの新旧形式を読み、配信予定と別タブを除外する', () {
    final videos = parseVideoChannelPage(page(), channel.id);
    expect(videos.map((v) => v['id']), ['newVideo002', 'oldVideo001']);
    expect(videos.first['title'], '日本語の"引用"と {括弧}');
    expect(videos.first['published_label'], '2 日前');
    expect(() => parseVideoChannelPage(page(id: 'other'), channel.id),
        throwsFormatException);
    expect(() => parseVideoChannelPage(page(title: 'ホーム'), channel.id),
        throwsFormatException);
    expect(() => parseVideoChannelPage('<html>error</html>', channel.id),
        throwsFormatException);
  });
  test('通常動画タブのみを取得してキャッシュする', () async {
    final calls = <Uri>[];
    final client = MockClient((r) async {
      calls.add(r.url);
      return r.url.path.contains('/feeds/')
          ? response('', 500)
          : response(regularPage([item(1), item(2)]), 200);
    });
    final service = VideoFeedService(client: client, channels: [channel]);
    final result = await service.read();
    expect(calls, hasLength(1));
    expect(result['channels'][0]['status'], 'ok');
    expect(result['channels'][0]['videos'], hasLength(2));
    await service.read();
    expect(calls, hasLength(1));
  });
  test('同時リクエストを共有しTTL後の失敗は前回分と取得日時を維持する', () async {
    var now = DateTime.utc(2026, 10, 18);
    var fail = false, calls = 0;
    final client = MockClient((r) async {
      calls++;
      return fail ? response('', 503) : response(page(), 200);
    });
    final service =
        VideoFeedService(client: client, channels: [channel], now: () => now);
    await Future.wait([service.read(), service.read()]);
    expect(calls, 1);
    fail = true;
    now = now.add(const Duration(minutes: 11));
    final result = await service.read();
    expect(result['channels'][0]['status'], 'stale');
    expect(result['channels'][0]['videos'], hasLength(2));
    expect(result['channels'][0]['fetched_at'],
        DateTime.utc(2026, 10, 18).toIso8601String());
    expect(calls, 2);
    await service.read();
    expect(calls, 2);
  });
  test('一部の取得失敗で他のチャンネルの動画を消さない', () async {
    const other = VideoChannel(
        'UCabcdefghijklmnopqrstuv', '別球団', 'teams', 'https://example.com');
    final client = MockClient((r) async =>
        r.url.path == '/channel/${channel.id}/videos'
            ? response(page(), 200)
            : response('', 503));
    final result = await VideoFeedService(
        client: client,
        channels: [channel, other],
        now: () => DateTime.utc(2026, 10, 18)).read();
    expect(result['channels'][0]['status'], 'ok');
    expect(result['channels'][1]['status'], 'unavailable');
    expect(result['channels'][1]['videos'], isEmpty);
  });
}
