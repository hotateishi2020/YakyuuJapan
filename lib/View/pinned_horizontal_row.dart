import 'package:flutter/material.dart';

/// Shares vertical layout with the row while keeping its leading cells visible.
class PinnedHorizontalRow extends StatelessWidget {
  const PinnedHorizontalRow(
      {super.key,
      required this.controller,
      required this.pinnedWidth,
      required this.children,
      this.minHeight = 48});
  final ScrollController controller;
  final double pinnedWidth, minHeight;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(children: [
        ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  SizedBox(width: pinnedWidth),
                  ...children.skip(1)
                ]))),
        Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: AnimatedBuilder(
                animation: controller,
                builder: (context, child) => Transform.translate(
                    offset: Offset(
                        controller.hasClients ? controller.offset : 0, 0),
                    child: child),
                child: SizedBox(width: pinnedWidth, child: children.first))),
      ]);
}
