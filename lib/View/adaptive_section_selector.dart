import 'package:flutter/material.dart';
import '../config/app_design.dart';

/// Uses actual scaled label widths, not a device-size breakpoint.
class AdaptiveSectionSelector extends StatelessWidget {
  const AdaptiveSectionSelector(
      {super.key,
      required this.labels,
      required this.value,
      required this.onChanged,
      required this.background,
      required this.foreground,
      this.pickerKey,
      this.itemKeyPrefix});
  final Map<int, String> labels;
  final int value;
  final ValueChanged<int> onChanged;
  final Color background, foreground;
  final Key? pickerKey;
  final String? itemKeyPrefix;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        const textStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
        final style = textStyle.copyWith(color: foreground);
        final cellWidth =
            (bounds.maxWidth - (labels.length - 1) * ALL_SPACE_BLOCK) /
                labels.length;
        final fits = labels.values.every((label) {
          final painter = TextPainter(
              text: TextSpan(text: label, style: textStyle),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1)
            ..layout();
          final fits = painter.width + 4 <= cellWidth;
          painter.dispose();
          return fits;
        });
        void select(int next) {
          if (next != value) onChanged(next);
        }

        if (fits) {
          return SizedBox(
              height: TAB_BAR_H,
              child: Row(children: [
                for (final entry in labels.entries.indexed) ...[
                  if (entry.$1 > 0) const SizedBox(width: ALL_SPACE_BLOCK),
                  Expanded(
                      child: Semantics(
                          button: true,
                          selected: value == entry.$2.key,
                          child: Material(
                              color: value == entry.$2.key
                                  ? background
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(TAB_RADIUS),
                              child: InkWell(
                                  onTap: () => select(entry.$2.key),
                                  borderRadius:
                                      BorderRadius.circular(TAB_RADIUS),
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      child: Center(
                                          child: Text(entry.$2.value,
                                              key: itemKeyPrefix == null
                                                  ? null
                                                  : ValueKey(
                                                      '$itemKeyPrefix${entry.$2.key}'),
                                              maxLines: 1,
                                              softWrap: false,
                                              style: style.copyWith(
                                                  height: 1,
                                                  leadingDistribution:
                                                      TextLeadingDistribution
                                                          .even,
                                                  fontWeight:
                                                      value == entry.$2.key
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                  color: value == entry.$2.key ? foreground : Colors.black87)))))))),
                ],
              ]));
        }
        return Container(
            height: TAB_BAR_H,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(TAB_RADIUS)),
            clipBehavior: Clip.antiAlias,
            child: DropdownButtonHideUnderline(child: DropdownButton<int>(
                key: pickerKey,
                value: value,
                isExpanded: true,
                isDense: true,
                alignment: Alignment.center,
                style: style.copyWith(
                    height: 1, leadingDistribution: TextLeadingDistribution.even),
                dropdownColor: background,
                iconEnabledColor: foreground,
                selectedItemBuilder: (_) => [
                      for (final label in labels.values)
                        Center(child: Text(label))
                    ],
                items: [
                  for (final e in labels.entries)
                    DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value,
                            key: itemKeyPrefix == null
                                ? null
                                : ValueKey('$itemKeyPrefix${e.key}')))
                ],
                onChanged: (v) {
                  if (v != null) select(v);
                })));
      });
}
