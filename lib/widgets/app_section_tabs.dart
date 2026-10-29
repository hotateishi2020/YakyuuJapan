import 'dart:async';
import '../logic/auth_session.dart';
import 'navigation_picker.dart';
import '../tools/tab_preferences.dart';
import 'package:flutter/material.dart';
import '../config/app_design.dart';
import '../View/LeagueLogo.dart';

/// Shared navigation used by the main board and Other's nested sections.
class AppSectionTabs extends StatelessWidget {
  const AppSectionTabs(
      {super.key,
      required this.tabs,
      required this.selectedIndex,
      required this.onSelected,
      this.selectedColor,
      this.selectedForeground,
      this.leadingAssets,
      this.highlightGames = false,
      this.alwaysPicker = false,
      this.alwaysTabs = false,
      this.height = TAB_BAR_H,
      this.specialLabel});
  final List<(String, int)> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Color? selectedColor, selectedForeground;
  final Map<int, String>? leadingAssets;
  final bool highlightGames;
  final bool alwaysPicker;
  final bool alwaysTabs;
  final double height;
  final Widget Function(TextStyle?)? specialLabel;
  @override
  Widget build(BuildContext context) {
    if (NavigationPickerScope.enabled(context)) {
      return NavigationPicker(alwaysTabs: alwaysTabs, alwaysPicker: alwaysPicker, labels: {for (final tab in tabs) tab.$2: highlightGames && tab.$2 == 0 ? '🔴 ${tab.$1}' : tab.$1}, value: selectedIndex,
        onChanged: onSelected, color: selectedColor ?? ALL_COLOR_APP,
        foreground: selectedForeground ?? TAB_COLOR_FONT);
    }
    void select(int value) {
      unawaited(AuthSession.instance.reportAction('タブ選択: ${tabs.firstWhere((tab) => tab.$2 == value).$1}'));
      onSelected(value);
    }
    Widget tabLabel((String, int) tab, [TextStyle? style]) =>
        tab.$2 == 0 && highlightGames && specialLabel != null
            ? specialLabel!(style)
            : Text(tab.$1,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                style: style);
    final assets = leadingAssets ?? const <int, String>{};
    final Color active = selectedColor ?? ALL_COLOR_APP;
    final Color activeFg = selectedForeground ?? TAB_COLOR_FONT;
    return LayoutBuilder(builder: (context, bounds) {
      final cellWidth =
          (bounds.maxWidth - (tabs.length - 1) * ALL_SPACE_BLOCK) / tabs.length;
      final fits = tabs.every((tab) {
        final painter = TextPainter(
            text: TextSpan(
                text: tab.$1,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1)
          ..layout();
        final needed = painter.width +
            4 +
            (highlightGames && tab.$2 == 0 ? 12 : 0) +
            (assets.containsKey(tab.$2) ? height * .72 + 6 : 0);
        painter.dispose();
        return needed <= cellWidth;
      });
      if (!alwaysTabs && (alwaysPicker || !fits)) {
        return Container(
            height: height,
            margin: const EdgeInsets.only(top: ALL_SPACE_BLOCK),
            decoration: BoxDecoration(
                color: active, borderRadius: BorderRadius.circular(height / 2)),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                    value: selectedIndex,
                    isExpanded: true,
                    isDense: true,
                    dropdownColor: active,
                    iconEnabledColor: activeFg,
                    style: TextStyle(
                        color: activeFg,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                    selectedItemBuilder: (_) =>
                        [for (final tab in tabs) Center(child: tabLabel(tab))],
                    items: [
                      for (final tab in tabs)
                        DropdownMenuItem(value: tab.$2, child: tabLabel(tab))
                    ],
                    onChanged: (i) {
                      if (i != null) select(i);
                    })));
      }
      return Padding(
          padding: const EdgeInsets.only(top: ALL_SPACE_BLOCK),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                for (int i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: ALL_SPACE_BLOCK),
                  Expanded(
                    child: Material(
                      color: selectedIndex == tabs[i].$2
                          ? active
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(TAB_RADIUS),
                      child: InkWell(
                        onTap: () => select(tabs[i].$2),
                        borderRadius: BorderRadius.circular(TAB_RADIUS),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (assets[tabs[i].$2] case final asset?) ...[
                                    LeagueLogo(
                                        asset: asset, height: height * 0.72),
                                    const SizedBox(width: 6),
                                  ],
                                  tabLabel(
                                    tabs[i],
                                    TextStyle(
                                      fontSize: 12,
                                      height: 1.0,
                                      leadingDistribution:
                                          TextLeadingDistribution.even,
                                      fontWeight: selectedIndex == tabs[i].$2
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: selectedIndex == tabs[i].$2
                                          ? activeFg
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ));
    });
  }
}

class ControlledSectionTabs extends StatelessWidget {
  const ControlledSectionTabs({super.key, required this.labels, this.preferenceScope});
  final String? preferenceScope;
  final List<String> labels;
  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => AppSectionTabs(
              tabs: [for (var i = 0; i < labels.length; i++) (labels[i], i)],
              selectedIndex: controller.index,
              onSelected: (i) {
                if (preferenceScope != null) saveTab(preferenceScope!,i);
                controller.animateTo(i, duration: Duration.zero);
              },
              selectedColor: Colors.black,
              selectedForeground: Colors.white,
            ));
  }
}
