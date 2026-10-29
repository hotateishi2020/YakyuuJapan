import '../tools/open_youtube.dart';
import '../logic/favorite_team.dart';
import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../tools/Env.dart';
import '../config/org_config.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';
import '../tools/video_order.dart';

class VideosBoard extends StatefulWidget {
  const VideosBoard(
      {super.key,
      this.color = const Color(0xFF173C64),
      this.org = OrgKind.npb,
      this.embedded = false});
  final OrgKind org;
  final bool embedded;
  final Color color;

  @override
  State<VideosBoard> createState() => _VideosBoardState();
}

class _VideosBoardState extends State<VideosBoard> {
  final _client = http.Client();
  List<Map<String, dynamic>> _channels = [];
  final _selectedChannels = <String, String>{};
  String? _error;
  bool _loading = false;
  bool _serverLoading = false;
  double? _progress;
  int _request = 0;
  Timer? _timer;
  Timer? _pendingTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => _load());
  }

  @override
  void didUpdateWidget(VideosBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.org != widget.org) {
      _pendingTimer?.cancel();
      _channels = [];
      _selectedChannels.clear();
      _loading = false;
      _serverLoading = false;
      _progress = null;
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pendingTimer?.cancel();
    _client.close();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (refresh) _progress = 0;
    });
    try {
      final response = await _client
          .get(Env.api(
              '/videos?org=${widget.org.name}${refresh ? '&refresh=1&background=1' : ''}'))
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) {
        throw const FormatException('動画を取得できませんでした');
      }
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map || value['channels'] is! List) {
        throw const FormatException('動画データが不正です');
      }
      final channels = listMapFromJson(value['channels']);
      if (!mounted || request != _request) return;
      _pendingTimer?.cancel();
      final progress = value['progress'];
      final pending = (progress is Map && progress['active'] == true) ||
          channels.any((c) => c['status'] == 'loading');
      if (pending) {
        _pendingTimer = Timer(const Duration(seconds: 1), () => _load());
      }
      if (mounted) {
        setState(() {
          _channels = channels;
          _serverLoading = pending;
          final percent = progress is Map ? progress['percent'] : null;
          _progress = percent is num ? percent.toDouble() / 100 : null;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _serverLoading = false;
          _error = '動画を取得できませんでした。時間をおいて再読み込みしてください。';
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _openTver(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'tver.jp' ||
        !(uri.path.startsWith('/episodes/ep') ||
            uri.path.startsWith('/search/'))) {
      return;
    }
    try {
      if (await launchUrl(uri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank')) {
        return;
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('TVerを開けませんでした。')));
    }
  }

  Future<void> _open(String id, {bool channel = false}) async {
    if (!(channel
            ? RegExp(r'^UC[A-Za-z0-9_-]{22}$')
            : RegExp(r'^[A-Za-z0-9_-]{11}$'))
        .hasMatch(id)) {
      return;
    }
    if (await openYoutube(id, channel: channel)) return;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('YouTubeを開けませんでした。')));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Row(children: [
            const Expanded(
                child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('約10分間隔で更新。ショート動画は対象外。日付は日本時間。',
                        style:
                            TextStyle(fontSize: 11, color: Colors.black54)))),
            IconButton(
                tooltip: '動画を再読み込み',
                onPressed: _loading || _serverLoading
                    ? null
                    : () => _load(refresh: true),
                icon: const Icon(Icons.refresh)),
          ]),
          if ((_loading || _serverLoading) && _channels.isNotEmpty)
            Center(child: BaseballLoading(progress: _progress, compact: true)),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.all(8),
                child:
                    Text(_error!, style: const TextStyle(color: Colors.red))),
          if (widget.embedded) _content() else Expanded(child: _content()),
        ],
      );

  Widget _content() {
    if (_channels.isEmpty) {
      return Center(child: _loading
          ? BaseballLoading(progress: _progress, compact: widget.embedded)
          : TextButton.icon(onPressed: () => _load(refresh: true),
              icon: const Icon(Icons.refresh), label: const Text('再読み込み')));
    }
    final sections = <Widget>[
      for (final channel in _channels.where((c) => c['category'] == 'league'))
        _channelSection(channel),
      _switchingSection('ob', '有識者'),
      if (widget.org == OrgKind.npb) _switchingSection('teams', '12球団の動画'),
      if (widget.org == OrgKind.mlb) _switchingSection('mlb_teams', '球団関連動画'),
      _switchingSection('program', '野球番組・対談'),
      _switchingSection('media', '野球系解説チャンネル'),
      _switchingSection('fan', '球団ファン系動画'),
    ];
    if (widget.embedded) {
      return Padding(padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections));
    }
    return ListView(key: const PageStorageKey('video-channel-list'),
      padding: const EdgeInsets.all(8), children: sections);
  }

  double _expertTabWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = math.max(36.0, painter.width + 12);
    painter.dispose();
    return width;
  }

  Widget _switchingSection(String category, String title) {
    final channels = _channels.where((c) => c['category'] == category || category == 'program' && c['category'] == 'tver').toList();
    if (channels.isEmpty) return const SizedBox.shrink();
    if (['ob', 'media', 'program', 'fan'].contains(category)) {
      final merged = <String, Map<String, dynamic>>{};
      for (final channel in channels) {
        for (final video in _visibleVideos(channel)) {
          merged.putIfAbsent(
              '${video['id']}',
              () => {
                    ...video,
                    'source_name': channel['name'],
                    'source_channel_id': channel['id'],
                  });
        }
      }
      final videos = _sortVideos(merged.values.toList());
      channels.insert(0, {
        'id': '$category-all',
        'name': category == 'ob' ? '有識者の動画一覧' : title,
        'tab_label': 'ALL',
        'category': category,
        'display_mode': 'all',
        'status': channels.any((c) => c['status'] == 'loading')
            ? 'loading'
            : channels.any((c) => c['status'] != 'ok')
                ? 'partial'
                : 'ok',
        'videos': videos,
      });
    }
    if (['media', 'program', 'fan'].contains(category)) {
      return Column(
        key: ValueKey('videos-section-$category'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_channelSection(channels.first)],
      );
    }
    final selected = channels
            .where((c) => c['id'] == _selectedChannels[category])
            .firstOrNull ??
        (['teams', 'mlb_teams'].contains(category)
            ? favoriteTeamRow(channels)
            : null) ??
        channels.first;
    return Column(
        key: ValueKey('videos-section-$category'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold))),
          LayoutBuilder(builder: (context, constraints) {
            Widget tabs(List<Map<String, dynamic>> items, {String? league}) {
              final columns =
                  category == 'teams' ? 6 : math.min(items.length, 3);
              final availableWidth =
                  constraints.maxWidth - (league == null ? 0 : 20);
              final width = (availableWidth - (columns - 1) * 4) / columns;
              final buttons = <Widget>[
                for (final channel in items)
                  Builder(builder: (context) {
                    final active = channel['id'] == selected['id'];
                    final color = category == 'teams'
                        ? parseColorName(
                            '${channel['color'] ?? ''}', widget.color)
                        : widget.color;
                    return SizedBox(
                        width: category == 'ob'
                            ? _expertTabWidth(
                                context, '${channel['tab_label'] ?? channel['name']}')
                            : width,
                        child: Semantics(
                            button: true,
                            selected: active,
                            child: Material(
                                color: active
                                    ? color
                                    : category == 'teams'
                                        ? Color.lerp(color, Colors.white, .88)!
                                        : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                                child: InkWell(
                                    key:
                                        ValueKey('videos-tab-${channel['id']}'),
                                    onTap: () => setState(() => _selectedChannels[category] =
                                        '${channel['id']}'),
                                    child: SizedBox(
                                        height: 34,
                                        child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 2),
                                            child: Center(
                                                child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text('${channel['tab_label'] ?? channel['name']}',
                                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active && color.computeLuminance() <= .179 ? Colors.white : Colors.black87))))))))));
                  }),
              ];
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (league != null)
                      SizedBox(
                          width: 20,
                          height: 34,
                          child: Center(
                              child: Text(league,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)))),
                    Expanded(
                      child: category == 'ob'
                          ? ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(dragDevices: {
                                ...ScrollConfiguration.of(context).dragDevices,
                                PointerDeviceKind.mouse,
                              }),
                              child: SingleChildScrollView(
                                key: const PageStorageKey('expert-segment-row'),
                                scrollDirection: Axis.horizontal,
                                child: Row(children: [
                                  for (final button in buttons)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(right: 2),
                                        child: button)
                                ]),
                              ),
                            )
                          : Wrap(spacing: 4, runSpacing: 4, children: buttons),
                    ),
                  ]);
            }

            if (category != 'teams') return tabs(channels);
            return Column(children: [
              tabs(
                  channels
                      .where((c) =>
                          c['league'] == 'central' ||
                          (c['league'] == null && channels.indexOf(c) < 6))
                      .toList(),
                  league: 'セ'),
              const SizedBox(height: 4),
              tabs(
                  channels
                      .where((c) =>
                          c['league'] == 'pacific' ||
                          (c['league'] == null && channels.indexOf(c) >= 6))
                      .toList(),
                  league: 'パ'),
            ]);
          }),
          _channelSection(selected),
        ]);
  }

  List<Map<String, dynamic>> _sortVideos(List<Map<String, dynamic>> videos) {
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

  List<Map<String, dynamic>> _visibleVideos(Map<String, dynamic> channel) {
    final regular = _sortVideos(listMapFromJson(channel['videos'])
        .map((v) => withVideoSortTime(
            v, DateTime.tryParse('${channel['fetched_at']}') ?? DateTime.now()))
        .where(
            (v) => v['is_short'] != true && !'${v['url']}'.contains('/shorts/'))
        .toList());
    if (['media', 'program', 'tver', 'fan'].contains(channel['category'])) {
      return regular;
    }
    if (channel['display_mode'] == 'recent' ||
        channel['display_mode'] == 'all') {
      return regular;
    }
    return regular.take(channel['category'] == 'teams' ? 30 : 4).toList();
  }

  Widget _channelSection(Map<String, dynamic> channel) {
    final tver = channel['platform'] == 'tver';
    final platform = tver ? 'TVer' : 'YouTube';
    final recent = channel['display_mode'] == 'recent';
    final combined = channel['display_mode'] == 'all';
    final limit = channel['category'] == 'teams' ? 30 : 4;
    final videos = _visibleVideos(channel);
    final stale = channel['status'] == 'stale';
    return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
                width: 4,
                height: 22,
                margin: const EdgeInsets.only(right: 8),
                color: widget.color),
            Expanded(
                child: Text('${channel['name']}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold))),
            if (!combined || tver)
              IconButton(
                  tooltip: '${channel['name']}を$platformで開く',
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: () => tver
                      ? _openTver('${channel['url']}')
                      : _open('${channel['id']}', channel: true)),
          ]),
          Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                  tver
                      ? '配信中の野球番組（放送日順・${videos.length}件）'
                      : combined
                          ? ['teams', 'mlb_teams'].contains(channel['category'])
                              ? '球団関連動画（新しい順・${videos.length}件）'
                              : channel['category'] == 'ob'
                                  ? '各有識者の動画をすべて表示（新しい順・${videos.length}件）'
                                  : '各チャンネルの最新動画（新しい順・${videos.length}件）'
                          : recent
                              ? channel['lookback_days'] == 2
                                  ? '当日〜2日前の動画（10件未満の場合は最新10件）'
                                  : '当日・前日の動画'
                              : channel['category'] == 'teams'
                                  ? '各配信元の最新動画を含む$limit件（新しい順）'
                                  : '新しい順に$limit件',
                  style: const TextStyle(fontSize: 11, color: Colors.black54))),
          if (channel['status'] == 'partial')
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('一部の動画を取得できませんでした。再読み込みするか、$platformでご確認ください。',
                    style: const TextStyle(fontSize: 11, color: Colors.brown))),
          if (stale)
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                    '更新できなかったため前回取得分を表示しています（${_date(channel['fetched_at'])}取得）。',
                    style: const TextStyle(fontSize: 11, color: Colors.brown))),
          if (videos.isEmpty && channel['status'] == 'loading')
            const SizedBox.shrink(),
          if (videos.isEmpty && channel['status'] != 'loading')
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                    tver
                        ? channel['status'] == 'ok'
                            ? '現在配信中の野球番組はありません。'
                            : 'TVerの番組を取得できませんでした。右上のアイコンからTVerを開けます。'
                        : combined
                            ? '表示できる動画はありません。'
                            : channel['status'] == 'ok' && recent
                                ? channel['lookback_days'] == 2
                                    ? '表示できる動画はありません。'
                                    : '当日・前日に公開された動画はありません。'
                                : '動画を取得できませんでした。右上のアイコンからチャンネルを開けます。',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)))
          else
            LayoutBuilder(builder: (context, constraints) {
              final width = math.min(280.0, constraints.maxWidth * .72);
              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      ...ScrollConfiguration.of(context).dragDevices,
                      PointerDeviceKind.mouse
                    }),
                child: SizedBox(
                  height: _videoRowHeight(context, width, videos),
                  child: ListView.builder(
                    key: PageStorageKey('video-row-${channel['id']}'),
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    itemExtent: width + 10,
                    itemCount: videos.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _videoCard(videos[index]),
                    ),
                  ),
                ),
              );
            }),
        ]));
  }

  // Reserve text space before thumbnails load so the row never changes height
  // during scrolling. Respect accessibility text scaling as well.
  double _videoRowHeight(BuildContext context, double width,
      List<Map<String, dynamic>> videos) {
    double textHeight(String text, TextStyle style, int lines) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: lines,
        ellipsis: '…',
      )..layout(maxWidth: math.max(1, width - 12));
      final height = painter.height.ceilToDouble();
      painter.dispose();
      return height;
    }

    double maximum = 0;
    for (final video in videos) {
      final label = video['published_at'] != null
          ? _date(video['published_at']) : '${video['published_label'] ?? ''}';
      final height = width * 9 / 16 + 20 +
          textHeight('${video['title']}', const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), 2) +
          textHeight(label, const TextStyle(fontSize: 10, color: Colors.black54), 1) +
          (video['source_name'] == null ? 0 : 6 + textHeight('${video['source_name']}', const TextStyle(fontSize: 10, color: Colors.black54), 1));
      maximum = math.max(maximum, height);
    }
    return maximum.ceilToDouble() + 2;
  }

  String _date(dynamic raw) {
    final date =
        DateTime.tryParse('$raw')?.toUtc().add(const Duration(hours: 9));
    return date == null
        ? ''
        : '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  Widget _videoCard(Map<String, dynamic> video) {
    final label = video['published_at'] != null
        ? _date(video['published_at'])
        : '${video['published_label'] ?? ''}';
    return Semantics(
        button: true,
        label:
            '${video['title']}を${video['platform'] == 'tver' ? 'TVer' : 'YouTube'}で開く',
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('video-${video['id']}'),
            onTap: () => video['platform'] == 'tver'
                ? _openTver('${video['url']}')
                : _open('${video['id']}'),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(fit: StackFit.expand, children: [
                        Image.network('${video['thumbnail_url']}',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Color(0xFFE9EDF1),
                                child: Icon(Icons.video_library_outlined,
                                    color: Colors.black38))),
                        const Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.play_circle_fill,
                                    color: Colors.white,
                                    shadows: [Shadow(blurRadius: 5)]))),
                      ])),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                      child: Text('${video['title']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600))),
                  if (video['source_name'] != null)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                        child: Text('${video['source_name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.black54))),
                  Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black54))),
                ]),
          ),
        ));
  }
}
