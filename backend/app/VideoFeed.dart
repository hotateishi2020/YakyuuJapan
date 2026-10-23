import 'TverFeed.dart';
import 'VideoContentFilter.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:collection';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'VideoChannels.dart';
import 'VideoClassification.dart';
import 'VideoTeamRouting.dart';

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

Map<String, dynamic> _video(String id, String title,
        {String? publishedAt, String? publishedLabel, int? viewCount}) =>
    {
      'id': id,
      if (viewCount != null) 'view_count': viewCount,
      'title': title,
      'url': 'https://www.youtube.com/watch?v=$id',
      'thumbnail_url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      if (publishedAt != null) 'published_at': publishedAt,
      if (publishedLabel != null) 'published_label': publishedLabel,
    };

int? parseVideoViewCount(String label) {
  final match = RegExp(r'([0-9][0-9,.]*)\s*(万|億|[KMB])?\s*(?:回|views)', caseSensitive: false).firstMatch(label);
  if (match == null) return null;
  final value = double.tryParse(match[1]!.replaceAll(',', ''));
  final scale = switch (match[2]?.toUpperCase()) {
    '万' => 10000, '億' => 100000000, 'K' => 1000,
    'M' => 1000000, 'B' => 1000000000, _ => 1,
  };
  return value == null ? null : (value * scale).round();
}

/// Read only entries belonging to the configured channel, never related videos.
List<Map<String, dynamic>> parseVideoFeed(String body, String channelId,
    {DateTime? now}) {
  final root = XmlDocument.parse(body).rootElement;
  if (root.name.local != 'feed') {
    throw const FormatException('Not an Atom feed');
  }
  String text(XmlElement node, String local) =>
      node.childElements
          .where((e) => e.name.local == local)
          .map((e) => e.innerText.trim())
          .firstOrNull ??
      '';
  if (text(root, 'channelId') != channelId) {
    throw const FormatException('Wrong channel');
  }
  final seen = <String>{};
  final videos = <Map<String, dynamic>>[];
  for (final entry
      in root.childElements.where((e) => e.name.local == 'entry')) {
    final id = text(entry, 'videoId');
    final title = text(entry, 'title');
    final published = DateTime.tryParse(text(entry, 'published'));
    if (!_videoId.hasMatch(id) ||
        title.isEmpty ||
        published == null ||
        published.isAfter(now ?? DateTime.now()) ||
        !seen.add(id)) {
      continue;
    }
    videos.add(
        _video(id, title, publishedAt: published.toUtc().toIso8601String(),
          viewCount: int.tryParse(entry.descendants.whereType<XmlElement>()
              .where((e) => e.name.local == 'statistics')
              .firstOrNull?.getAttribute('views') ?? '')));
  }
  videos
      .sort((a, b) => '${b['published_at']}'.compareTo('${a['published_at']}'));
  return videos;
}

/// Public channel pages provide a fallback when YouTube's Atom endpoint fails.
Map<String, dynamic> _initialData(String html,
    {String variable = 'ytInitialData'}) {
  final match = RegExp('(?:var\\s+)?$variable\\s*=\\s*').firstMatch(html);
  if (match == null) throw const FormatException('Missing channel data');
  final start = html.indexOf('{', match.end);
  if (start < 0) throw const FormatException('Missing channel object');
  var depth = 0, quoted = false, escaped = false;
  for (var i = start; i < html.length; i++) {
    final char = html[i];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == '{') {
      depth++;
    } else if (char == '}' && --depth == 0) {
      return jsonDecode(html.substring(start, i + 1)) as Map<String, dynamic>;
    }
  }
  throw const FormatException('Incomplete channel data');
}

String _text(dynamic value) {
  if (value is! Map) return '';
  if (value['content'] is String) return value['content'];
  if (value['simpleText'] is String) return value['simpleText'];
  final runs = value['runs'];
  return runs is List
      ? runs.whereType<Map>().map((r) => r['text'] ?? '').join()
      : '';
}

dynamic _channelContent(String html, String channelId,
    {String tab = 'videos'}) {
  final data = _initialData(html);
  if (data['metadata']?['channelMetadataRenderer']?['externalId'] !=
      channelId) {
    throw const FormatException('Wrong channel');
  }
  final tabs = data['contents']?['twoColumnBrowseResultsRenderer']?['tabs'];
  if (tabs is! List) throw const FormatException('Missing video tab');
  final selected = tabs
      .whereType<Map>()
      .map((t) =>
          tab == 'search' ? t['expandableTabRenderer'] : t['tabRenderer'])
      .whereType<Map>()
      .where((t) => t['selected'] == true)
      .firstOrNull;
  if (selected == null ||
      !(tab == 'search'
              ? ['検索', 'Search']
              : tab == 'streams'
                  ? ['ライブ', 'Live']
                  : ['動画', 'Videos'])
          .contains(selected['title'])) {
    throw const FormatException('Not the videos tab');
  }
  return selected['content'];
}

List<Map<String, dynamic>> parseVideoSearchPage(String html) =>
    _parseVideos(_initialData(html)['contents']?['twoColumnSearchResultsRenderer']);

List<Map<String, dynamic>> parseVideoChannelPage(
        String html, String channelId) =>
    _parseVideos(_channelContent(html, channelId));

({List<Map<String, dynamic>> videos, String? token, String? version})
    parseRegularVideosPage(String html, String channelId,
        {String tab = 'videos'}) {
  final content = _channelContent(html, channelId, tab: tab);
  return (
    videos: _parseVideos(content),
    token: _continuation(content),
    version: RegExp(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"')
        .firstMatch(html)
        ?.group(1)
  );
}

bool _isShort(Map value) {
  final encoded = jsonEncode(value);
  return encoded.contains('/shorts/') ||
      encoded.contains('"reelWatchEndpoint"') ||
      encoded.contains('"style":"SHORTS"');
}

List<Map<String, dynamic>> _parseVideos(dynamic content) {
  final videos = <Map<String, dynamic>>[];
  final seen = <String>{};
  void visit(dynamic node) {
    if (node is List) {
      for (final item in node) {
        visit(item);
      }
    }
    if (node is! Map) return;
    if (node.containsKey('shortsLockupViewModel') ||
        node.containsKey('reelItemRenderer') ||
        node.containsKey('reelShelfRenderer')) {
      return;
    }
    final modern = node['lockupViewModel'];
    final legacy = node['videoRenderer'] ?? node['playlistVideoRenderer'];
    if (modern is Map && modern['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
      if (_isShort(modern)) return;
      final meta = modern['metadata']?['lockupMetadataViewModel'];
      final id = '${modern['contentId'] ?? ''}';
      final title = _text(meta?['title']);
      final rows =
          meta?['metadata']?['contentMetadataViewModel']?['metadataRows'];
      final labels = <String>[];
      if (rows is List) {
        for (final row in rows.whereType<Map>()) {
          for (final part
              in (row['metadataParts'] as List? ?? []).whereType<Map>()) {
            labels.add(_text(part['text']));
          }
        }
      }
      final label = labels
          .where((s) => RegExp(r'前|公開|配信|ago|Streamed|Premiered').hasMatch(s))
          .lastOrNull;
      final upcoming = jsonEncode(modern['contentImage']).contains('配信予定') ||
          jsonEncode(modern['contentImage']).contains('UPCOMING') ||
          labels.any((s) =>
              s.contains('にプレミア公開') ||
              s.contains('公開予定') ||
              s.contains('Premieres '));
      if (!upcoming &&
          _videoId.hasMatch(id) &&
          title.isNotEmpty &&
          seen.add(id)) {
        videos.add(_video(id, title, publishedLabel: label,
            viewCount: labels.map(parseVideoViewCount).whereType<int>().firstOrNull));
      }
      return;
    }
    if (legacy is Map) {
      if (_isShort(legacy)) return;
      final id = '${legacy['videoId'] ?? ''}';
      final title = _text(legacy['title']);
      if (legacy['upcomingEventData'] == null &&
          _videoId.hasMatch(id) &&
          title.isNotEmpty &&
          seen.add(id)) {
        videos.add(_video(id, title,
            viewCount: parseVideoViewCount(_text(legacy['viewCountText'] ?? legacy['shortViewCountText'])),
            publishedLabel:
                _text(legacy['publishedTimeText'] ?? legacy['videoInfo'])));
      }
      return;
    }
    for (final value in node.values) {
      visit(value);
    }
  }

  visit(content);
  return videos;
}

DateTime videoWindowStart(DateTime now, {int lookbackDays = 1}) {
  final japan = now.toUtc().add(const Duration(hours: 9));
  return DateTime.utc(japan.year, japan.month, japan.day - lookbackDays)
      .subtract(const Duration(hours: 9));
}

// Relative labels provide an approximate ordering only, never a publication date.
DateTime? estimateVideoPublishedAt(String label, DateTime reference) {
  final compact = label.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final match = RegExp(
          r'(\d+)(秒|分|時間|日|週間|か月|ヶ月|年|seconds?|minutes?|hours?|days?|weeks?|months?|years?)(?:前|ago)')
      .firstMatch(compact);
  if (match == null) return null;
  final unit = match[2]!;
  final seconds = switch (unit) {
    '秒' || 'second' || 'seconds' => 1,
    '分' || 'minute' || 'minutes' => 60,
    '時間' || 'hour' || 'hours' => 3600,
    '日' || 'day' || 'days' => 86400,
    '週間' || 'week' || 'weeks' => 604800,
    'か月' || 'ヶ月' || 'month' || 'months' => 2592000,
    '年' || 'year' || 'years' => 31536000,
    _ => 0,
  };
  return reference
      .toUtc()
      .subtract(Duration(seconds: int.parse(match[1]!) * seconds));
}

Map<String, dynamic> withVideoSortTime(
    Map<String, dynamic> video, DateTime reference) {
  if (DateTime.tryParse('${video['published_at']}') != null ||
      DateTime.tryParse('${video['published_sort_at']}') != null) {
    return video;
  }
  final estimated =
      estimateVideoPublishedAt('${video['published_label'] ?? ''}', reference);
  return estimated == null
      ? video
      : {
          ...video,
          'published_sort_at': estimated.toIso8601String(),
        };
}

List<Map<String, dynamic>> sortVideosByPublishedAt(
    List<Map<String, dynamic>> videos) {
  final indexed = videos.indexed.toList()
    ..sort((a, b) {
      final left = DateTime.tryParse('${a.$2['published_at']}') ??
          DateTime.tryParse('${a.$2['published_sort_at']}');
      final right = DateTime.tryParse('${b.$2['published_at']}') ??
          DateTime.tryParse('${b.$2['published_sort_at']}');
      final order = left == null
          ? (right == null ? 0 : 1)
          : right == null
              ? -1
              : right.compareTo(left);
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
  return indexed.map((entry) => entry.$2).toList();
}

List<Map<String, dynamic>> selectChannelVideos(
    VideoChannel channel, List<Map<String, dynamic>> videos, DateTime now) {
  videos = filterVideoOrganization(channel, videos).where((v) {
    final expires = DateTime.tryParse('${v['expires_at']}');
    return expires == null || expires.isAfter(now);
  }).toList();
  if (channel.category == 'tver') return sortVideosByPublishedAt(videos);
  if (!channel.daily) {
    return sortVideosByPublishedAt(videos).take(channel.limit).toList();
  }
  final start = videoWindowStart(now, lookbackDays: channel.lookbackDays);
  DateTime? published(Map<String, dynamic> video) =>
      DateTime.tryParse('${video['published_at']}') ??
      (channel.minimumVideos > 0 ? DateTime.tryParse('${video['published_sort_at']}') : null);
  final dated = videos.where((v) {
    final date = published(v);
    return date != null && !date.isAfter(now);
  }).toList()..sort((a, b) => published(b)!.compareTo(published(a)!));
  final recent = dated.where((v) => !published(v)!.isBefore(start)).toList();
  return recent.length < channel.minimumVideos
      ? dated.take(channel.minimumVideos).toList()
      : recent;
}

// Relative labels also preserve a minimum feed when exact dates are unavailable.
// Estimated sort times remain separate from confirmed publication dates.
bool _olderThanWindow(Map<String, dynamic> video, {int lookbackDays = 1}) {
  final label = '${video['published_label'] ?? ''}';
  if (RegExp(r'週間前|か月前|ヶ月前|年前|weeks? ago|months? ago|years? ago')
      .hasMatch(label)) {
    return true;
  }
  final days = RegExp(r'(\d+)\s*(?:日前|days? ago)').firstMatch(label);
  return days != null && int.parse(days[1]!) > lookbackDays;
}

String? _continuation(dynamic value) {
  if (value is Map) {
    final command = value['continuationCommand'];
    if (command is Map && command['token'] is String) return command['token'];
    for (final child in value.values) {
      final token = _continuation(child);
      if (token != null) return token;
    }
  } else if (value is List) {
    for (final child in value) {
      final token = _continuation(child);
      if (token != null) return token;
    }
  }
  return null;
}

DateTime parseVideoPublishedAt(String html, String videoId, String channelId) {
  final data = _initialData(html, variable: 'ytInitialPlayerResponse');
  final details = data['videoDetails'];
  if (details?['videoId'] != videoId || details?['channelId'] != channelId) {
    throw const FormatException('Wrong video');
  }
  final microformat = data['microformat']?['playerMicroformatRenderer'];
  final date = DateTime.tryParse('${microformat?['publishDate']}');
  if (date == null) throw const FormatException('Missing publication date');
  return date.toUtc();
}

List<Map<String, dynamic>> filterVideoOrganization(
    VideoChannel channel, List<Map<String, dynamic>> videos) {
  final scope = channel.videoOrg ?? (channel.category == 'ob' ? 'npb' : null);
  if (scope == null) return videos;
  return videos.where((video) {
    if (channel.category == 'tver') {
      return tverVideoOrganization('${video['title'] ?? ''}') == scope;
    }
    final organizations = videoOrganizations('${video['title'] ?? ''}');
    if (organizations.isEmpty &&
        (channel.category == 'ob' || channel.unknownToNpb)) {
      return scope == 'npb';
    }
    return organizations.contains(scope);
  }).toList();
}

/// Merge cached sources without making network requests or creating extra team tabs.
List<Map<String, dynamic>> groupVideoChannels(
    List<VideoChannel> definitions, List<Map<String, dynamic>> values) {
  final specs = {for (final channel in definitions) channel.id: channel};
  final byId = {
    for (final value in values)
      value['id']: {
        ...value,
        if (specs[value['id']] case final VideoChannel channel)
          'videos': filterVideoOrganization(
              channel, (value['videos'] as List).cast<Map<String, dynamic>>()),
      }
  };
  final moved = <String, Map<String, Map<String, dynamic>>>{};
  final movedIds = <String, Set<String>>{};
  final movedIncomplete = <String>{};
  for (final source in definitions.where((c) => c.category == 'ob' || c.category == 'tver')) {
    final cached = byId[source.id];
    if (cached == null) continue;
    for (final video
        in (cached['videos'] as List).cast<Map<String, dynamic>>()) {
      final target = expertVideoTeam('${video['title'] ?? ''}');
      if (target == null) continue;
      final mlb = target.startsWith('mlb-team-');
      if (mlb
          ? source.videoOrg != 'mlb'
          : !definitions.any((c) => c.id == target && c.category == 'teams')) {
        continue;
      }
      if (cached['status'] != 'ok') movedIncomplete.add(target);
      moved.putIfAbsent(target, () => {}).putIfAbsent(
          '${video['id']}',
          () => {
                ...withVideoSortTime(
                    video,
                    DateTime.tryParse('${cached['fetched_at']}') ??
                        DateTime.now()),
                'source_name': source.name,
                'source_channel_id': source.id,
              });
      movedIds.putIfAbsent(source.id, () => {}).add('${video['id']}');
    }
  }
  return [
    for (final team in definitions
        .where((c) => !['related', 'broadcast'].contains(c.category)))
      if (byId[team.id] case final Map<String, dynamic> value)
        if (team.category != 'teams')
          {
            ...value,
            if (team.category == 'tver') 'category': 'program',
            if (team.category == 'ob' || team.category == 'tver')
              'videos': (value['videos'] as List)
                  .where((v) =>
                      !(movedIds[team.id]?.contains('${v['id']}') ?? false))
                  .toList(),
          }
        else
          (() {
            final videos = <String, Map<String, dynamic>>{};
            final requiredVideos = <String, String>{};
            var incomplete = false;
            var fresh = false;
            var loading = false;
            for (final source in definitions) {
              final own = source.id == team.id;
              final dedicated = source.teamIds.contains(team.id);
              final shared = ['league', 'ob', 'media', 'program', 'broadcast', 'tver']
                  .contains(source.category);
              if (!own && !dedicated && !shared) continue;
              final cached = byId[source.id];
              if (cached == null) continue;
              if (cached['status'] == 'ok' &&
                  (cached['videos'] as List).isNotEmpty) {
                fresh = true;
              }
              if (own || dedicated) {
                incomplete |= cached['status'] != 'ok';
                loading |= cached['status'] == 'loading';
              }
              for (final video
                  in (cached['videos'] as List).cast<Map<String, dynamic>>()) {
                final title = '${video['title']}'.toLowerCase();
                if (source.category == 'broadcast' &&
                    !broadcastVideoTeams(source, title).contains(team.id)) {
                  continue;
                }
                if (!own &&
                    !dedicated &&
                    !(teamVideoKeywords[team.id] ?? [])
                        .any((word) => title.contains(word.toLowerCase()))) {
                  continue;
                }
                if (own || dedicated) {
                  requiredVideos.putIfAbsent(source.id, () => '${video['id']}');
                }
                videos.putIfAbsent(
                    '${video['id']}',
                    () => {
                          ...withVideoSortTime(
                              video,
                              DateTime.tryParse('${cached['fetched_at']}') ??
                                  DateTime.now()),
                          'source_name': source.name,
                          'source_channel_id': source.id,
                        });
              }
            }
            videos.addAll(moved[team.id] ?? {});
            final sorted = sortVideosByPublishedAt(videos.values.toList());
            // Keep the latest item from each team-specific source even when
            // official uploads dominate, or a source's exact dates are unavailable.
            final selected = <String, Map<String, dynamic>>{};
            for (final id in requiredVideos.values) {
              selected[id] = videos[id]!;
            }
            for (final video in sorted) {
              if (selected.length >= team.limit) break;
              selected.putIfAbsent('${video['id']}', () => video);
            }
            selected.addAll(moved[team.id] ?? {});
            final visible = sorted
                .where((v) => selected.containsKey('${v['id']}'))
                .toList();
            return {
              ...value,
              'name': '${team.tabLabel ?? team.name}の動画',
              'display_limit': team.limit,
              if (moved.containsKey(team.id)) 'display_mode': 'all',
              'status': loading
                  ? 'loading'
                  : incomplete &&
                          sorted.isNotEmpty &&
                          (fresh || value['status'] != 'stale')
                      ? 'partial'
                      : value['status'],
              'videos': visible,
            };
          })(),
    for (final entry
        in moved.entries.where((e) => e.key.startsWith('mlb-team-')))
      {
        'id': entry.key,
        'name': '${mlbVideoTeams[entry.key.substring(9)]!.first}の関連動画',
        'tab_label': mlbVideoTeams[entry.key.substring(9)]!.first,
        'category': 'mlb_teams',
        'display_mode': 'all',
        'status': movedIncomplete.contains(entry.key) ? 'partial' : 'ok',
        'videos': sortVideosByPublishedAt(entry.value.values.toList()),
      },
  ];
}

class VideoFeedService {
  VideoFeedService(
      {http.Client? client,
      this.channels = videoChannels,
      DateTime Function()? now})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;
  final http.Client _client;
  final List<VideoChannel> channels;
  final DateTime Function() _now;
  final _cache = <String, Map<String, dynamic>>{};
  final _attempted = <String, DateTime>{};
  final _published = <String, DateTime>{};
  Future<Map<String, dynamic>>? _inflight;
  static const _headers = {
    'user-agent': 'Mozilla/5.0',
    'accept-language': 'ja'
  };

  Timer? _refreshTimer;
  File? _snapshotFile;
  int _completedChannels = 0;
  bool _refreshing = false;
  Map<String, dynamic> get _progress => {
        'active': _refreshing,
        'completed': _completedChannels,
        'total': channels.length,
        'percent': channels.isEmpty
            ? (_refreshing ? 99 : 100)
            : (_completedChannels * 100 / channels.length)
                .floor()
                .clamp(0, _refreshing ? 99 : 100),
      };

  Map<String, dynamic> cached() => {
        'progress': _progress,
        'channels': groupVideoChannels(channels, [
          for (final channel in channels)
            _cache.containsKey(channel.id)
                ? _visible(channel, _cache[channel.id]!)
                : {
                    ...channel.toJson(),
                    'status': 'loading',
                    'videos': <Map<String, dynamic>>[]
                  }
        ])
      };

  Future<void> start(
      {String? snapshotPath,
      Duration interval = const Duration(minutes: 10)}) async {
    if (_refreshTimer != null) return;
    if (snapshotPath != null) {
      _snapshotFile = File(snapshotPath);
      try {
        final saved = jsonDecode(await _snapshotFile!.readAsString());
        // Version 2 contains regular videos only; never restore old Shorts.
        if (saved['version'] == 2) {
          for (final value in saved['channels'] as List) {
            if (channels.any((c) => c.id == value['id'])) {
              _cache[value['id']] = Map<String, dynamic>.from(value)
                ..['status'] = 'stale';
              for (final video in value['videos'] as List) {
                final date = DateTime.tryParse('${video['published_at']}');
                if (date != null) _published['${video['id']}'] = date;
              }
            }
          }
        }
      } catch (_) {
        /* Missing/corrupt snapshots are rebuilt in the background. */
      }
    }
    unawaited(refresh());
    _refreshTimer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  Future<Map<String, dynamic>> refresh() {
    if (_inflight != null) return _inflight!;
    _attempted.clear();
    return read();
  }

  void dispose() {
    _refreshTimer?.cancel();
    _client.close();
  }

  Future<Map<String, dynamic>> read() => _inflight ??= _read().whenComplete(() {
        _inflight = null;
        _refreshing = false;
      });

  Future<Map<String, dynamic>> _read() async {
    _refreshing = true;
    _completedChannels = 0;
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; offset < channels.length; offset += 6) {
      result.addAll(
          await Future.wait(channels.skip(offset).take(6).map((channel) async {
        final value = await _channel(channel);
        _completedChannels++;
        return value;
      })));
    }
    if (_snapshotFile != null) {
      try {
        await _snapshotFile!.parent.create(recursive: true);
        final temporary = File('${_snapshotFile!.path}.tmp');
        await temporary
            .writeAsString(jsonEncode({'version': 2, 'channels': result}));
        await temporary.rename(_snapshotFile!.path);
      } catch (error) {
        stderr.writeln('Video snapshot save failed: $error');
      }
    }
    return {
      'channels': groupVideoChannels(channels, result),
      'progress': {..._progress, 'active': false, 'percent': 100}
    };
  }

  // The channel workers share a small request pool; without it six channels
  // each resolving six dates can burst into 36 simultaneous YouTube requests.
  int _activeRequests = 0;
  final _requestQueue = Queue<Completer<void>>();

  Future<String> _get(Uri uri) async {
    if (_activeRequests >= 3) {
      final ready = Completer<void>();
      _requestQueue.add(ready);
      await ready.future;
    } else {
      _activeRequests++;
    }
    try {
      return await _getResponse(uri);
    } finally {
      if (_requestQueue.isNotEmpty) {
        _requestQueue.removeFirst().complete();
      } else {
        _activeRequests--;
      }
    }
  }

  Future<String> _getResponse(Uri uri) async {
    final response = await _client.get(uri, headers: {
      ..._headers,
      if (uri.host == 'service-api.tver.jp') 'x-tver-platform-type': 'web'
    }).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw const FormatException('YouTube unavailable');
    }
    return utf8.decode(response.bodyBytes);
  }

  Future<void> _loadDates(VideoChannel channel) async {
    try {
      final entries = parseVideoFeed(
          await _get(Uri.https('www.youtube.com', '/feeds/videos.xml',
              {'channel_id': channel.id})),
          channel.id,
          now: _now());
      for (final entry in entries) {
        _published['${entry['id']}'] =
            DateTime.parse('${entry['published_at']}');
      }
    } catch (_) {/* Watch pages are the fallback for exact dates. */}
  }

  Future<Map<String, dynamic>> _dated(
      VideoChannel channel, Map<String, dynamic> video) async {
    final id = '${video['id']}';
    final date = _published[id] ??
        parseVideoPublishedAt(
            await _get(
                Uri.https('www.youtube.com', '/watch', {'v': id, 'hl': 'ja'})),
            id,
            channel.id);
    _published[id] = date;
    if (_published.length > 4000) _published.remove(_published.keys.first);
    return {...video, 'published_at': date.toUtc().toIso8601String()};
  }

  Future<({List<Map<String, dynamic>> videos, bool complete})> _recent(
      VideoChannel channel,
      {String tab = 'videos'}) async {
    final html = await _get(Uri.https(
        'www.youtube.com', '/channel/${channel.id}/$tab', {'hl': 'ja'}));
    final first = parseRegularVideosPage(html, channel.id, tab: tab);
    if (first.videos.isEmpty) throw const FormatException('Empty uploads');
    await _loadDates(channel);
    bool older(Map<String, dynamic> video) {
      final date = _published['${video['id']}'];
      return date != null
          ? date.isBefore(
              videoWindowStart(_now(), lookbackDays: channel.lookbackDays))
          : _olderThanWindow(video, lookbackDays: channel.lookbackDays);
    }

    var batch = first.videos;
    var token = first.token;
    var complete = true;
    final videos = <Map<String, dynamic>>[];
    final seen = <String>{};
    final tokens = <String>{};
    // Continue beyond the first page when a busy day fills the regular-video tab.
    for (var page = 0;; page++) {
      var needed = channel.minimumVideos - videos.length;
      final candidates = <Map<String, dynamic>>[];
      for (final video in batch) {
        if (seen.contains('${video['id']}')) continue;
        if (!older(video) || needed > 0) {
          seen.add('${video['id']}');
          candidates.add(video);
          needed--;
        }
      }
      for (var offset = 0; offset < candidates.length; offset += 6) {
        final dated =
            await Future.wait(candidates.skip(offset).take(6).map((v) async {
          try {
            return await _dated(channel, v);
          } catch (_) {
            complete = false;
            return channel.minimumVideos > 0 ? withVideoSortTime(v, _now()) : null;
          }
        }));
        videos.addAll(dated.whereType<Map<String, dynamic>>());
      }
      if ((batch.every(older) && videos.length >= channel.minimumVideos) ||
          token == null) {
        break;
      }
      if (page >= 9 || !tokens.add(token) || first.version == null) {
        complete = false;
        break;
      }
      try {
        final response = await _client
            .post(Uri.https('www.youtube.com', '/youtubei/v1/browse'),
                headers: {..._headers, 'content-type': 'application/json'},
                body: jsonEncode({
                  'context': {
                    'client': {
                      'clientName': 'WEB',
                      'clientVersion': first.version,
                      'hl': 'ja'
                    }
                  },
                  'continuation': token
                }))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw const FormatException('Continuation unavailable');
        }
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        batch = _parseVideos(data);
        token = _continuation(data);
        if (batch.isEmpty) {
          complete = false;
          break;
        }
      } catch (_) {
        complete = false;
        break;
      }
    }
    return (
      videos: selectChannelVideos(channel, videos, _now()),
      complete: complete
    );
  }

  Map<String, dynamic> _visible(
          VideoChannel channel, Map<String, dynamic> value) =>
      {
        ...value,
        ...channel.toJson(),
        'videos': selectChannelVideos(
            channel,
            (value['videos'] as List)
                .cast<Map<String, dynamic>>()
                .map((v) => withVideoSortTime(
                    v, DateTime.tryParse('${value['fetched_at']}') ?? _now()))
                .toList(),
            _now()),
      };

  final _contentMatches = <String, bool>{};
  Future<bool> _matchesContent(
      VideoChannel channel, Map<String, dynamic> video) async {
    final key = '${channel.id}:${video['id']}';
    if (_contentMatches.containsKey(key)) return _contentMatches[key]!;
    final title = '${video['title']}';
    if (matchesVideoContent(channel.contentFilter, title)) {
      return _contentMatches[key] = true;
    }
    if (channel.contentFilter == 'baseball') {
      return _contentMatches[key] = false;
    }
    if (!RegExp(r'里崎|satozaki', caseSensitive: false).hasMatch(title)) {
      return _contentMatches[key] = false;
    }
    // Mixed channels require the description to identify the guest/topic.
    final page = await _get(Uri.https(
        'www.youtube.com', '/watch', {'v': '${video['id']}', 'hl': 'ja'}));
    final player = _initialData(page, variable: 'ytInitialPlayerResponse');
    final description = '${player['videoDetails']?['shortDescription'] ?? ''}';
    return _contentMatches[key] = matchesVideoContent(
        channel.contentFilter, title,
        description: description);
  }

  // Scan several regular-video pages: news can bury baseball uploads quickly.
  Future<({List<Map<String, dynamic>> videos, bool complete})> _broadcastVideos(
      VideoChannel channel) async {
    final html = await _get(Uri.https(
        'www.youtube.com', '/channel/${channel.id}/videos', {'hl': 'ja'}));
    final first = parseRegularVideosPage(html, channel.id);
    if (first.videos.isEmpty) throw const FormatException('Empty uploads');
    var batch = first.videos;
    var token = first.token;
    final videos = <String, Map<String, dynamic>>{};
    final tokens = <String>{};
    var complete = true;
    for (var page = 0; page < 5; page++) {
      for (final video in batch) {
        try {
          if (channel.contentFilter != null
              ? await _matchesContent(channel, video)
              : broadcastVideoTeams(channel, '${video['title']}').isNotEmpty) {
            videos.putIfAbsent('${video['id']}', () => video);
          }
        } catch (_) {
          complete = false;
        }
      }
      if (videos.length >= channel.limit ||
          token == null ||
          first.version == null ||
          page == 4 ||
          !tokens.add(token)) {
        break;
      }
      try {
        final response = await _client
            .post(
              Uri.https('www.youtube.com', '/youtubei/v1/browse'),
              headers: {..._headers, 'content-type': 'application/json'},
              body: jsonEncode({
                'context': {
                  'client': {
                    'clientName': 'WEB',
                    'clientVersion': first.version,
                    'hl': 'ja'
                  }
                },
                'continuation': token,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw const FormatException('Continuation unavailable');
        }
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        batch = _parseVideos(data);
        token = _continuation(data);
        if (batch.isEmpty) break;
      } catch (_) {
        complete = false;
        break;
      }
    }
    if (channel.contentFilter != null && videos.length < channel.limit) {
      try {
        final query = channel.contentFilter == 'baseball' ? '野球' : '里崎 野球';
        final search = await _get(Uri.https('www.youtube.com',
            '/channel/${channel.id}/search', {'query': query, 'hl': 'ja'}));
        final candidates =
            parseRegularVideosPage(search, channel.id, tab: 'search').videos;
        for (final video in candidates) {
          if (await _matchesContent(channel, video)) {
            videos.putIfAbsent('${video['id']}', () => video);
          }
        }
      } catch (_) {
        complete = false;
      }
    }
    return (
      videos: channel.contentFilter != null
          ? videos.values.toList()
          : videos.values.take(channel.limit).toList(),
      complete: complete
    );
  }

  Future<Map<String, dynamic>> _channel(VideoChannel channel) async {
    final previous = _cache[channel.id];
    final attempted = _attempted[channel.id];
    final ttl = previous?['status'] == 'ok'
        ? const Duration(minutes: 10)
        : const Duration(minutes: 1);
    if (previous != null &&
        attempted != null &&
        _now().difference(attempted) < ttl) {
      return _visible(channel, previous);
    }
    _attempted[channel.id] = _now();
    try {
      List<Map<String, dynamic>> videos;
      var complete = true;
      if (channel.category == 'tver') {
        final body = await _get(Uri.https('service-api.tver.jp',
            '/api/v2/callKeywordSearch', {'keyword': '野球'}));
        videos = parseTverSearch(
            Map<String, dynamic>.from(jsonDecode(body)), _now());
      } else if (channel.daily) {
        videos = [];
        var readAnyTab = false;
        try {
          final recent = await _recent(channel);
          videos = recent.videos;
          complete = recent.complete;
          readAnyTab = true;
        } catch (_) {
          complete = false;
        }
        if (channel.includeStreams) {
          try {
            final streams = await _recent(channel, tab: 'streams');
            readAnyTab = true;
            final merged = {
              for (final v in [...videos, ...streams.videos]) '${v['id']}': v
            };
            videos = merged.values.toList();
            complete = complete && streams.complete;
          } catch (_) {
            complete = false;
          }
        }
        if (!readAnyTab) throw const FormatException('Video tabs unavailable');
      } else {
        if (channel.category == 'broadcast' || channel.contentFilter != null) {
          final result = await _broadcastVideos(channel);
          videos = result.videos;
          complete = result.complete;
        } else {
          videos = parseVideoChannelPage(
              await _get(Uri.https('www.youtube.com',
                  '/channel/${channel.id}/videos', {'hl': 'ja'})),
              channel.id);
        }
        if (videos.isEmpty &&
            channel.category != 'broadcast' &&
            channel.contentFilter == null) {
          throw const FormatException('Empty regular videos');
        }
        if (channel.keywords.isNotEmpty) {
          videos = videos
              .where((v) => channel.keywords.any((word) =>
                  '${v['title']}'.toLowerCase().contains(word.toLowerCase())))
              .toList();
        }
        videos = filterVideoOrganization(channel, videos)
            .take(channel.limit)
            .toList();
        if (channel.league != null ||
            ['related', 'ob', 'media', 'program', 'broadcast']
                .contains(channel.category)) {
          await _loadDates(channel);
          final dated = <Map<String, dynamic>>[];
          for (var offset = 0; offset < videos.length; offset += 6) {
            dated.addAll(
                await Future.wait(videos.skip(offset).take(6).map((v) async {
              try {
                return await _dated(channel, v);
              } catch (_) {
                complete = false;
                return withVideoSortTime(v, _now());
              }
            })));
          }
          videos = dated;
        }
      }
      if (!complete &&
          (channel.daily ||
              channel.category == 'broadcast' ||
              channel.contentFilter != null) &&
          previous != null) {
        final merged = {
          for (final v
              in (previous['videos'] as List).cast<Map<String, dynamic>>())
            '${v['id']}': v
        };
        for (final v in videos) {
          merged['${v['id']}'] = v;
        }
        videos = merged.values.toList();
      }
      return _cache[channel.id] = {
        ...channel.toJson(),
        'status': complete ? 'ok' : 'partial',
        'fetched_at': _now().toUtc().toIso8601String(),
        'videos': selectChannelVideos(channel, videos, _now())
      };
    } catch (_) {
      final value = {
        ...channel.toJson(),
        'status': previous?['fetched_at'] != null ? 'stale' : 'unavailable',
        if (previous?['fetched_at'] != null)
          'fetched_at': previous!['fetched_at'],
        'videos': previous?['videos'] ?? <Map<String, dynamic>>[]
      };
      _cache[channel.id] = value;
      return _visible(channel, value);
    }
  }
}
