import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Place each card below the shortest column using its actual rendered height.
class CompactCardLayout extends MultiChildRenderObjectWidget {
  const CompactCardLayout({super.key, required this.columns, super.children});
  final int columns;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderCompactCards(columns);

  @override
  void updateRenderObject(BuildContext context, covariant RenderCompactCards renderObject) {
    renderObject.columns = columns;
  }
}

class _CardParentData extends ContainerBoxParentData<RenderBox> {}

class RenderCompactCards extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _CardParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CardParentData> {
  RenderCompactCards(this._columns);
  int _columns;
  set columns(int value) {
    if (_columns == value) return;
    _columns = value;
    markNeedsLayout();
  }
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardParentData) {
      child.parentData = _CardParentData();
    }
  }

  Size _arrange(BoxConstraints constraints, {required bool dry}) {
    const gap = 8.0;
    final width = math.max(0.0, (constraints.maxWidth - (_columns - 1) * gap) / _columns);
    final heights = List<double>.filled(_columns, 0);
    var child = firstChild;
    while (child != null) {
      var column = 0;
      for (var i = 1; i < _columns; i++) {
        if (heights[i] < heights[column]) column = i;
      }
      final childConstraints = BoxConstraints.tightFor(width: width);
      final parentData = child.parentData! as _CardParentData;
      final double height;
      if (dry) {
        height = child.getDryLayout(childConstraints).height;
      } else {
        child.layout(childConstraints, parentUsesSize: true);
        parentData.offset = Offset(column * (width + gap), heights[column]);
        height = child.size.height;
      }
      heights[column] += height + gap;
      child = parentData.nextSibling;
    }
    return constraints.constrain(Size(constraints.maxWidth,
        math.max(0.0, heights.reduce(math.max) - gap)));
  }

  @override
  void performLayout() => size = _arrange(constraints, dry: false);
  @override
  Size computeDryLayout(BoxConstraints constraints) => _arrange(constraints, dry: true);
  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
