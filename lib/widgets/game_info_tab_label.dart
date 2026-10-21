import 'package:flutter/material.dart';
import '../View/BlinkBg.dart';

/// Keep the text readable while the background signals a live game.
class GameInfoTabLabel extends StatelessWidget {
  const GameInfoTabLabel({super.key, this.style});
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text('試合情報', maxLines: 1, softWrap: false,
          style: (style ?? DefaultTextStyle.of(context).style).copyWith(
              color: const Color(0xff542900), fontWeight: FontWeight.bold)),
    );
    const base = BoxDecoration(color: Color(0xffffedc2),
        borderRadius: BorderRadius.all(Radius.circular(6)));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('💥', style: style),
      if (MediaQuery.disableAnimationsOf(context))
        DecoratedBox(decoration: base, child: text)
      else
        BlinkBg(base: base, color: const Color(0xffffb300), radius: 6,
            duration: const Duration(milliseconds: 900),
            fillMin: .1, fillMax: .8, borderWidth: 0, child: text),
    ]);
  }
}
