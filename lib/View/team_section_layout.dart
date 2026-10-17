import 'package:flutter/material.dart';

/// 球団ページでは各項目を自然な高さで展開し、スクロールを親に任せる。
class TeamSectionLayout extends InheritedWidget {
  const TeamSectionLayout({super.key, required super.child});
  static bool embedded(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TeamSectionLayout>() != null;
  @override
  bool updateShouldNotify(TeamSectionLayout oldWidget) => false;
}

class SectionExpanded extends StatelessWidget {
  const SectionExpanded({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TeamSectionLayout.embedded(context) ? child : Expanded(child: child);
}

Widget sectionScrollView(BuildContext context, {Key? key, required Widget child, ScrollController? controller, Axis scrollDirection = Axis.vertical, ScrollPhysics? physics, EdgeInsetsGeometry? padding}) => TeamSectionLayout.embedded(context)
    ? Padding(key: key, padding: padding ?? EdgeInsets.zero, child: child)
    : SingleChildScrollView(key: key, controller: controller, scrollDirection: scrollDirection, physics: physics, padding: padding, child: child);

class SectionList extends StatelessWidget {
  const SectionList({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) => TeamSectionLayout.embedded(context)
      ? Padding(padding: padding ?? EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))
      : ListView(padding: padding, children: children);
}

class SectionScrollbar extends StatelessWidget {
  const SectionScrollbar({super.key, required this.child, this.controller, this.thumbVisibility, this.notificationPredicate, this.scrollbarOrientation});
  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;
  final ScrollNotificationPredicate? notificationPredicate;
  final ScrollbarOrientation? scrollbarOrientation;
  @override
  Widget build(BuildContext context) => TeamSectionLayout.embedded(context) ? child : Scrollbar(controller: controller, thumbVisibility: thumbVisibility, notificationPredicate: notificationPredicate, scrollbarOrientation: scrollbarOrientation, child: child);
}
