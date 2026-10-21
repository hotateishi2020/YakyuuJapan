import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../tools/open_youtube.dart';
import '../tools/video_order.dart';

List<Map<String, dynamic>> relatedPlayerVideos(
    List<Map<String, dynamic>> channels, String name, DateTime reference) {
  String normalize(String value) => value.toLowerCase().replaceAll(RegExp(r'[\s　・･.]'), '');
  final key = normalize(name.replaceAll(RegExp(r'\(.*\)$'), ''));
  if (key.length < 2) return [];
  final videos = <String, Map<String, dynamic>>{};
  for (final channel in channels) {
    for (final video in listMapFromJson(channel['videos'])) {
      final id = '${video['id'] ?? ''}';
      if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ||
          video['platform'] == 'tver' ||
          !normalize('${video['title'] ?? ''}').contains(key)) {
        continue;
      }
      final candidate = withVideoSortTime({
        ...video, 'source_name': video['source_name'] ?? channel['name'],
      }, reference);
      if (!videos.containsKey(id) ||
          (videos[id]!['view_count'] == null && candidate['view_count'] != null)) {
        videos[id] = candidate;
      }
    }
  }
  return videos.values.toList();
}

class PlayerRelatedVideos extends StatefulWidget {
  const PlayerRelatedVideos({super.key, required this.name, required this.org});
  final String name;
  final String org;
  @override
  State<PlayerRelatedVideos> createState() => _PlayerRelatedVideosState();
}

class _PlayerRelatedVideosState extends State<PlayerRelatedVideos> {
  late Future<List<Map<String, dynamic>>> _videos;
  @override
  void initState() {
    super.initState();
    _videos = _load();
  }
  @override
  void didUpdateWidget(covariant PlayerRelatedVideos oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name || oldWidget.org != widget.org) _videos = _load();
  }
  Future<List<Map<String, dynamic>>> _load() async {
    final response = await http.get(Env.api('/videos').replace(
        queryParameters: {'org': widget.org})).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw const FormatException('動画取得失敗');
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return relatedPlayerVideos(listMapFromJson(data['channels']), widget.name, DateTime.now());
  }
  DateTime? date(Map<String, dynamic> video) =>
      DateTime.tryParse('${video['published_at']}') ?? DateTime.tryParse('${video['published_sort_at']}');
  int? views(Map<String, dynamic> video) => int.tryParse('${video['view_count']}');

  Widget section(String title, List<Map<String, dynamic>> videos) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
      if (videos.isEmpty) const Text('表示できる動画はありません。'),
      for (final video in videos.take(5))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: SizedBox(width: 88, height: 50,
            child: Image.network('${video['thumbnail_url']}', fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_outline))),
          title: Text('${video['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text([
            if (video['source_name'] != null) '${video['source_name']}',
            if (video['published_at'] != null) '${video['published_at']}'.split('T').first
            else if (video['published_label'] != null) '${video['published_label']}',
            if (views(video) != null) '${views(video)}回再生',
          ].join(' ・ '), maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () async {
            if (!await openYoutube('${video['id']}') && mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('動画を開けませんでした。')));
            }
          },
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(padding: EdgeInsets.only(top: 20, bottom: 8),
          child: Text('関連動画', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      const Text('取得済み動画から選手名で抽出しています。', style: TextStyle(fontSize: 12, color: Colors.black54)),
      FutureBuilder<List<Map<String, dynamic>>>(future: _videos, builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(12), child: Text('関連動画を読み込み中…'));
        }
        if (snapshot.hasError) {
          return Row(children: [
          const Expanded(child: Text('関連動画を取得できませんでした。')),
          TextButton(onPressed: () => setState(() => _videos = _load()), child: const Text('再読み込み')),
          ]);
        }
        final videos = snapshot.data ?? [];
        final recent = videos.where((v) => date(v) != null).toList()
          ..sort((a, b) => date(b)!.compareTo(date(a)!));
        final popular = videos.where((v) => views(v) != null).toList()
          ..sort((a, b) => views(b)!.compareTo(views(a)!));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          section('最近の動画', recent),
          section('再生数の多い動画', popular),
        ]);
      }),
    ],
  );
}
