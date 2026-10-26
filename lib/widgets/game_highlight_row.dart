import 'package:flutter/material.dart';
import '../tools/open_youtube.dart';

class GameHighlightRow extends StatelessWidget {
  const GameHighlightRow({super.key, required this.videos});
  final List<Map<String, dynamic>> videos;
  static const rowHeight = 132.0;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: SizedBox(
    height: rowHeight,
    child: DecoratedBox(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black26))),
      child: Row(children: [
        const SizedBox(width: 42, child: Center(child: Text('動画', style: TextStyle(fontWeight: FontWeight.bold)))),
        Expanded(child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(5),
          itemCount: videos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final video = videos[i];
            return SizedBox(width: 160, child: InkWell(
              onTap: () async {
                if (!await openYoutube('${video['id']}') && context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('動画を開けませんでした。')));
                }
              },
              child: Tooltip(message: '${video['title']}', child: Column(children: [
                SizedBox(height: 90, width: 160, child: Stack(fit: StackFit.expand, children: [
                  Image.network('${video['thumbnail_url']}', fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12)),
                  const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 32)),
                ])),
                Text('${video['title']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling, style: const TextStyle(fontSize: 10, height: 1.3)),
              ])),
            ));
          },
        )),
      ]),
    ),
  ));
}
