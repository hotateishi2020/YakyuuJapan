import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Browsers send trackpad pinches as PointerScaleEvent. flutter_map handles
/// touch pinches, native pan/zoom and scroll wheels itself, but not this signal.
class MapScaleListener extends StatelessWidget {
  const MapScaleListener({super.key, required this.controller, required this.child});
  final MapController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) {
      if (event is! PointerScaleEvent || !event.scale.isFinite || event.scale <= 0) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        final camera = controller.camera;
        final zoom = (camera.zoom + math.log(event.scale) / math.ln2).clamp(camera.minZoom ?? 0.0, camera.maxZoom ?? 18.0);
        controller.move(camera.focusedZoomCenter(event.localPosition, zoom), zoom);
      });
    },
    child: child,
  );
}
