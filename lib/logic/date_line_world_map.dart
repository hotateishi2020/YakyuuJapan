import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// A viewport may never span more than one circumference of the earth.
double singleWorldMinZoom(double width, double height) =>
    math.max(0, math.log(math.max(width, height) / 256) / math.ln2) + .001;

/// Keep the visible longitude range within the single world centered on the date line.
/// Tile wrapping remains enabled so the Americas appear east of Japan.
/// Fix latitude so dragging and zooming cannot scroll the HOME map vertically.
class DateLineWorldConstraint extends CameraConstraint {
  const DateLineWorldConstraint();
  @override
  MapCamera? constrain(MapCamera camera) {
    if (camera.size.width <= 0 || camera.size.height <= 0) return camera;
    final zoom = math.max(camera.zoom,
        singleWorldMinZoom(camera.size.width, camera.size.height));
    final worldWidth = 256 * math.pow(2, zoom);
    final halfLongitude = camera.size.width / worldWidth * 180;
    if (halfLongitude > 180) return null;
    return camera.withPosition(zoom: zoom, center: LatLng(
      20,
      camera.center.longitude.clamp(halfLongitude, 360 - halfLongitude),
    ));
  }
}
