import 'package:flutter/material.dart';

/// Builds tabs on first use and preserves their State while another tab is open.
/// Hidden tabs keep their last widget and do not rebuild on polling updates.
class RetainedTabBody extends StatefulWidget {
  const RetainedTabBody(
      {super.key, required this.selected, required this.builder});
  final Object selected;
  final WidgetBuilder builder;

  @override
  State<RetainedTabBody> createState() => _RetainedTabBodyState();
}

class _RetainedTabBodyState extends State<RetainedTabBody> {
  final _tabs = <Object, Widget>{};

  @override
  Widget build(BuildContext context) {
    _tabs[widget.selected] = widget.builder(context);
    return Stack(fit: StackFit.expand, children: [
      for (final entry in _tabs.entries)
        Offstage(
          key: ValueKey(entry.key),
          offstage: entry.key != widget.selected,
          child: TickerMode(
            enabled: entry.key == widget.selected,
            child: entry.value,
          ),
        ),
    ]);
  }
}
