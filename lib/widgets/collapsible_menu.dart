import 'navigation_picker.dart';
import 'package:flutter/material.dart';
import '../config/app_design.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';

class _MenuModel extends ChangeNotifier {
  bool visible = true;
  RenderBox? bar;
  Color color = const Color(0xffe8edf2);
  Color foreground = const Color(0xff44566b);
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  final bands = <Object, int>{};
  int get bottom => bands.values.fold(0, (a, b) => a > b ? a : b);
  void update(Object id, int? level) {
    if (disposed || bands[id] == level) return;
    if (level == null) {
      bands.remove(id);
    } else {
      bands[id] = level;
    }
    notifyListeners();
  }

  void toggle() {
    visible = !visible;
    notifyListeners();
  }
}

class MenuScope extends StatefulWidget {
  const MenuScope({super.key, required this.child, this.color = const Color(0xffe8edf2), this.foreground = const Color(0xff44566b)});
  final Widget child;
  final Color color;
  final Color foreground;
  @override
  State<MenuScope> createState() => _MenuScopeState();
}

class _MenuScopeState extends State<MenuScope> {
  final model = _MenuModel();
  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    model.color = widget.color;
    model.foreground = widget.foreground;
    return _MenuBackdrop(model: model, color: Color.lerp(Colors.white, widget.color, .18)!,
      child: _MenuScope(model: model, child: widget.child));
  }
}

class _MenuScope extends InheritedNotifier<_MenuModel> {
  _MenuScope({required _MenuModel model, required super.child})
      : color = model.color, foreground = model.foreground, super(notifier: model);
  final Color color, foreground;
  @override
  bool updateShouldNotify(covariant _MenuScope oldWidget) =>
      color != oldWidget.color || foreground != oldWidget.foreground || super.updateShouldNotify(oldWidget);
}

/// Each visible page registers its deepest navigation band. Only that band
/// retains a toggle when all navigation is collapsed; page state stays mounted.
class MenuBand extends StatefulWidget {
  const MenuBand(
      {super.key, required this.child, this.level = 0, this.toggle = true});
  final Widget child;
  final int level;
  final bool toggle;
  @override
  State<MenuBand> createState() => _MenuBandState();
}

class _MenuBandState extends State<MenuBand> {
  _MenuModel? model;
  bool active = true;
  bool collapsed = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    model = context.dependOnInheritedWidgetOfExactType<_MenuScope>()?.notifier;
    active = TickerMode.of(context);
    if (model?.visible != false) collapsed = false;
    final current = model;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        current?.update(this, widget.toggle && active ? widget.level : null);
      }
    });
  }

  @override
  void dispose() {
    final current = model;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      current?.update(this, null);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (NavigationPickerScope.enabled(context)) {
      return NavigationPickerLevel(level: widget.level, child: widget.child);
    }
    final state = model;
    if (state == null) return widget.child;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Keep page constraints stable during the fade. Changing the height
          // each frame also lays out every large table below the navigation.
          ClipRect(
            child: Align(
              heightFactor: (reduced ? !state.visible : collapsed) ? 0 : 1,
              alignment: Alignment.topCenter,
              child: IgnorePointer(
                ignoring: !state.visible,
                child: ExcludeSemantics(
                  excluding: !state.visible,
                  child: RepaintBoundary(
                    child: AnimatedSlide(
                      offset: state.visible ? Offset.zero : const Offset(0, -.12),
                      duration: reduced ? Duration.zero : const Duration(milliseconds: 320),
                      curve: Curves.easeInOutCubic,
                      child: AnimatedOpacity(
                        opacity: state.visible ? 1 : 0,
                        duration: reduced ? Duration.zero : const Duration(milliseconds: 320),
                        curve: Curves.easeInOutCubic,
                        onEnd: () {
                          if (mounted && model?.visible == false && !collapsed) {
                            setState(() => collapsed = true);
                          }
                        },
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.toggle && active && state.bottom == widget.level)
            Builder(builder: (barContext) {
              return _MenuBarAnchor(model: state, child: Padding(
                padding: EdgeInsets.only(top: state.visible ? ALL_SPACE_BLOCK : 0),
                child: Material(
                color: state.color,
                child: InkWell(
                    key: const ValueKey('menu-visibility-toggle'),
                    onTap: state.toggle,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(state.visible ? '▲ メニューを非表示 ▲' : '▼ メニュー表示 ▼',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: state.foreground)))))));
            }),
        ]);
  }
}

// Track the attached render box rather than a context that may be inactive
// while switching between navigation levels.
class _MenuBarAnchor extends SingleChildRenderObjectWidget {
  const _MenuBarAnchor({required this.model, required super.child});
  final _MenuModel model;
  @override
  RenderObject createRenderObject(BuildContext context) => _MenuBarRender(model);
}

class _MenuBarRender extends RenderProxyBox {
  _MenuBarRender(this.model);
  final _MenuModel model;
  @override
  void performLayout() {
    super.performLayout();
    model.bar = this;
  }
  @override
  void detach() {
    if (identical(model.bar, this)) model.bar = null;
    super.detach();
  }
}

/// Paint only the navigation area, including gaps between nested menu bands.
class _MenuBackdrop extends SingleChildRenderObjectWidget {
  const _MenuBackdrop({required this.model, required this.color, required super.child});
  final _MenuModel model;
  final Color color;
  @override
  RenderObject createRenderObject(BuildContext context) => _MenuBackdropRender(model, color);
  @override
  void updateRenderObject(BuildContext context, covariant _MenuBackdropRender renderObject) {
    renderObject.model = model;
    renderObject.color = color;
    renderObject.markNeedsPaint();
  }
}
class _MenuBackdropRender extends RenderProxyBox {
  _MenuBackdropRender(this.model, this.color);
  _MenuModel model;
  Color color;
  late final TapGestureRecognizer _edgeTap = TapGestureRecognizer()
    ..onTap = () => model.toggle();

  @override
  bool hitTestSelf(Offset position) {
    final bar = model.bar;
    if (bar is! RenderBox || !bar.attached || !bar.hasSize) return false;
    final origin = bar.localToGlobal(Offset.zero, ancestor: this);
    return position.dy >= origin.dy + (model.visible ? ALL_SPACE_BLOCK : 0) &&
        position.dy < origin.dy + bar.size.height;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is! PointerDownEvent || !hitTestSelf(entry.localPosition)) return;
    final bar = model.bar;
    if (bar is! RenderBox) return;
    final left = bar.localToGlobal(Offset.zero, ancestor: this).dx;
    if (entry.localPosition.dx < left || entry.localPosition.dx >= left + bar.size.width) {
      _edgeTap.addPointer(event);
    }
  }

  @override
  void dispose() {
    _edgeTap.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final bar = model.bar;
    if (bar is RenderBox && bar.attached && bar.hasSize) {
      final bottom = bar.localToGlobal(Offset(0, bar.size.height), ancestor: this).dy;
      context.canvas.drawRect(offset & Size(size.width, bottom.clamp(0, size.height)), Paint()..color = color);
    }
    super.paint(context, offset);
    // Nested tab groups keep their padding; only the toggle bar extends to
    // both edges of the page, including when the navigation is collapsed.
    if (bar is RenderBox && bar.attached && bar.hasSize) {
      final origin = bar.localToGlobal(Offset.zero, ancestor: this);
      final top = origin.dy + (model.visible ? ALL_SPACE_BLOCK : 0);
      final bottom = origin.dy + bar.size.height;
      final paint = Paint()..color = model.color;
      if (origin.dx > 0) {
        context.canvas.drawRect(Rect.fromLTRB(offset.dx, offset.dy + top,
            offset.dx + origin.dx, offset.dy + bottom), paint);
      }
      final right = origin.dx + bar.size.width;
      if (right < size.width) {
        context.canvas.drawRect(Rect.fromLTRB(offset.dx + right, offset.dy + top,
            offset.dx + size.width, offset.dy + bottom), paint);
      }
    }
  }
}

/// Navigation spacing collapses together with the menu itself.
class MenuGap extends StatelessWidget {
  const MenuGap({super.key, required this.height});
  final double height;
  @override
  Widget build(BuildContext context) => NavigationPickerScope.enabled(context) ? const SizedBox.shrink() : MenuBand(toggle: false, child: SizedBox(height: height));
}
