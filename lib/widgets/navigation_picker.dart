import '../View/LeagueLogo.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A page's nested selectors publish their state here, while retaining ownership
/// of their callbacks and tab controllers in the page that uses them.
class NavigationPickerScope extends StatefulWidget {
  const NavigationPickerScope({super.key, required this.child});
  final Widget child;
  static bool enabled(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PickerScope>() != null;
  @override
  State<NavigationPickerScope> createState() => _NavigationPickerScopeState();
}

class _NavigationPickerScopeState extends State<NavigationPickerScope> {
  final model = _PickerModel();
  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _PickerScope(model: model, child: widget.child);
}

class _PickerScope extends InheritedWidget {
  const _PickerScope({required this.model, required super.child});
  final _PickerModel model;
  @override
  bool updateShouldNotify(_PickerScope old) => model != old.model;
}

class NavigationPickerLevel extends InheritedWidget {
  const NavigationPickerLevel(
      {super.key, required this.level, required super.child});
  final int level;
  static int of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NavigationPickerLevel>()
          ?.level ??
      2;
  @override
  bool updateShouldNotify(NavigationPickerLevel old) => level != old.level;
}

class _PickerEntry {
  const _PickerEntry(this.level, this.labels, this.value, this.onChanged,
      this.color, this.foreground, this.pickerKey, this.itemColors, this.logoAssets, this.alwaysPicker, this.alwaysTabs);
  final int level, value;
  final bool alwaysPicker;
  final bool alwaysTabs;
  final Map<int, String> labels;
  final ValueChanged<int> onChanged;
  final Color color, foreground;
  final Key? pickerKey;
  final Map<int, Color> itemColors;
  final Map<int, String> logoAssets;
  bool sameDisplay(_PickerEntry other) =>
      alwaysPicker == other.alwaysPicker &&
      alwaysTabs == other.alwaysTabs &&
      level == other.level &&
      value == other.value &&
      mapEquals(labels, other.labels) &&
      mapEquals(itemColors, other.itemColors) &&
      mapEquals(logoAssets, other.logoAssets) &&
      color == other.color &&
      foreground == other.foreground &&
      pickerKey == other.pickerKey;
}

class _PickerModel extends ChangeNotifier {
  final entries = <Object, _PickerEntry>{};
  bool _disposed = false;
  void update(Object owner, _PickerEntry? entry) {
    if (_disposed) return;
    final previous = entries[owner];
    if (entry == null) {
      if (entries.remove(owner) != null) notifyListeners();
    } else {
      entries[owner] = entry;
      if (previous == null || !entry.sameDisplay(previous)) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Invisible at its original position; the actual picker is in the top row.
class NavigationPicker extends StatefulWidget {
  const NavigationPicker(
      {super.key,
      required this.labels,
      required this.value,
      required this.onChanged,
      required this.color,
      required this.foreground,
      this.alwaysPicker = false,
      this.alwaysTabs = false,
      this.level,
      this.pickerKey,
      this.itemColors = const {},
      this.logoAssets = const {}});
  final Map<int, String> labels;
  final int value;
  final ValueChanged<int> onChanged;
  final Color color, foreground;
  final int? level;
  final bool alwaysPicker;
  final bool alwaysTabs;
  final Key? pickerKey;
  final Map<int, Color> itemColors;
  final Map<int, String> logoAssets;
  @override
  State<NavigationPicker> createState() => _NavigationPickerState();
}

class _NavigationPickerState extends State<NavigationPicker> {
  _PickerModel? model;
  int revision = 0;
  @override
  Widget build(BuildContext context) {
    final current =
        context.dependOnInheritedWidgetOfExactType<_PickerScope>()!.model;
    model = current;
    final active = TickerMode.valuesOf(context).enabled;
    final level = widget.level ?? NavigationPickerLevel.of(context);
    final version = ++revision;
    final entry =
        _PickerEntry(level, Map.of(widget.labels), widget.value, (value) {
      if (mounted && TickerMode.valuesOf(context).enabled) widget.onChanged(value);
    }, widget.color, widget.foreground, widget.pickerKey, Map.of(widget.itemColors), Map.of(widget.logoAssets), widget.alwaysPicker, widget.alwaysTabs);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && revision == version) {
        current.update(this, active && widget.labels.isNotEmpty ? entry : null);
      }
    });
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    final current = model;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => current?.update(this, null));
    super.dispose();
  }
}

/// Stays on one line. Narrow screens scroll horizontally rather than wrapping
/// or shrinking labels and hit targets to unreadable sizes.
class NavigationPickerBar extends StatelessWidget {
  const NavigationPickerBar({super.key});
  @override
  Widget build(BuildContext context) {
    final model =
        context.dependOnInheritedWidgetOfExactType<_PickerScope>()!.model;
    return AnimatedBuilder(
        animation: Listenable.merge([model, PaintingBinding.instance.systemFonts]),
        builder: (context, _) {
          final entries = model.entries.values.toList()
            ..sort((a, b) => a.level.compareTo(b.level));
          if (entries.isEmpty) return const SizedBox.shrink();
          return LayoutBuilder(builder: (context, constraints) {
            final pickerWidths = [for (final entry in entries) _pickerWidth(context, entry)];
            final last = entries.last;
            if (entries.length == 1 && last.level == 0 && last.alwaysTabs && constraints.maxWidth.isFinite) {
              return SizedBox(height: 40, width: constraints.maxWidth,
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                  child: _options(last, [for (final value in last.labels.keys) _optionWidth(context, last, value)])));
            }

            final separatorWidth = _textWidth(context, '>') + 12;
            var usedWidth = pickerWidths.fold<double>(0, (a, b) => a + b) +
                separatorWidth * (entries.length - 1);
            final expandedIndices = <int>{};
            // Prefer the rightmost group, but even tab-preferred groups must fit
            // alongside all of the other controls in this row.
            for (var i = entries.length - 1; i >= 0; i--) {
              final entry = entries[i];
              if (entry.alwaysPicker || (!entry.alwaysTabs && i != entries.length - 1)) continue;
              final tabsWidth = entry.labels.keys.fold<double>(0,
                  (sum, value) => sum + _optionWidth(context, entry, value)) +
                  (entry.labels.length - 1) * 4;
              final nextWidth = usedWidth - pickerWidths[i] + tabsWidth;
              if (constraints.maxWidth.isFinite && nextWidth <= constraints.maxWidth) {
                expandedIndices.add(i);
                usedWidth = nextWidth;
              }
            }
            return SizedBox(
              height: 40,
              child: SingleChildScrollView(
                key: const ValueKey('navigation-picker-row'),
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final indexed in entries.indexed) ...[
                    if (indexed.$1 > 0)
                      SizedBox(width: separatorWidth, child: const Center(child: Text('>', style: _textStyle))),
                    if (expandedIndices.contains(indexed.$1))
                      _options(indexed.$2, [for (final value in indexed.$2.labels.keys) _optionWidth(context, indexed.$2, value)])
                    else
                      SizedBox(width: pickerWidths[indexed.$1], child: _picker(indexed.$2)),
                  ],
                ]),
              ));
          });
        });
  }

  static const _controlHeight = 34.0;
  static const _textStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 13);

  double _textWidth(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(_textStyle)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  double _labelWidth(BuildContext context, _PickerEntry entry, int value) =>
      _textWidth(context, entry.labels[value]!) + (entry.logoAssets.containsKey(value) ? 30 : 0);

  double _pickerWidth(BuildContext context, _PickerEntry entry) =>
      (entry.labels.keys.map((value) => _labelWidth(context, entry, value)).fold<double>(0, (a, b) => a > b ? a : b) + 56).clamp(110, 220);

  double _optionWidth(BuildContext context, _PickerEntry entry, int value) =>
      (_labelWidth(context, entry, value) + 28).clamp(48, double.infinity);

  Widget _options(_PickerEntry entry, List<double> widths) => Row(
    key: entry.pickerKey ?? ValueKey('navigation-picker-${entry.level}'),
    mainAxisSize: MainAxisSize.min,
    children: [for (final indexed in entry.labels.keys.indexed) ...[
      if (indexed.$1 > 0) const SizedBox(width: 4),
      Semantics(
        selected: indexed.$2 == entry.value,
        button: true,
        child: SizedBox(width: widths[indexed.$1], height: _controlHeight,
          child: Material(
            color: indexed.$2 == entry.value
                ? _color(entry, indexed.$2)
                : Color.lerp(Colors.white, _color(entry, indexed.$2), .14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
            child: InkWell(
              key: ValueKey('navigation-option-${entry.level}-${indexed.$2}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () { if (indexed.$2 != entry.value) entry.onChanged(indexed.$2); },
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(child: DefaultTextStyle.merge(style: _textStyle, child: _label(entry, indexed.$2, foreground: indexed.$2 == entry.value ? null : Colors.black87)))),
            ),
          ),
        ),
      ),
    ]],
  );

  Color _color(_PickerEntry entry, int value) => entry.itemColors[value] ?? entry.color;
  Color _foreground(_PickerEntry entry, int value) => entry.itemColors.containsKey(value)
      ? (_color(entry, value).computeLuminance() > .65 ? Colors.black87 : Colors.white)
      : entry.foreground;

  Widget _label(_PickerEntry entry, int value, {Color? foreground}) => Row(mainAxisSize: MainAxisSize.min, children: [
    if (entry.logoAssets[value] case final String asset) ...[
      SizedBox(width: 24, height: 24, child: ClipRect(child: LeagueLogo(asset: asset, height: 24))),
      const SizedBox(width: 6),
    ],
    Flexible(child: Text(entry.labels[value]!, maxLines: 1, overflow: TextOverflow.ellipsis,
      style: TextStyle(color: foreground ?? _foreground(entry, value)))),
  ]);

  Widget _picker(_PickerEntry entry) => Container(
        constraints: const BoxConstraints(minWidth: 110, maxWidth: 220),
        height: _controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            color: _color(entry, entry.value), borderRadius: BorderRadius.circular(8)),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
          key: entry.pickerKey ?? ValueKey('navigation-picker-${entry.level}'),
          value: entry.labels.containsKey(entry.value)
              ? entry.value
              : entry.labels.keys.first,
          isDense: true,
          isExpanded: true,
          dropdownColor: entry.color,
          iconEnabledColor: _foreground(entry, entry.value),
          style: TextStyle(
              color: entry.foreground,
              fontWeight: FontWeight.bold,
              fontSize: 13),
          selectedItemBuilder: (_) => [
            for (final value in entry.labels.keys)
              Align(
                  alignment: Alignment.centerLeft,
                  child:
                      _label(entry, value))
          ],
          items: [
            for (final item in entry.labels.entries)
              DropdownMenuItem(
                  value: item.key,
                  child: Container(
                    color: _color(entry, item.key),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: _label(entry, item.key)))
          ],
          onChanged: (value) {
            if (value != null && value != entry.value) entry.onChanged(value);
          },
        )),
      );
}
