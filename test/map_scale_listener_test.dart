import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/widgets/map_scale_listener.dart';

void main() {
  testWidgets('narrow map fits games in Japan and the United States', (tester) async {
    final controller = MapController();
    const japan = LatLng(33.594341,130.362411);
    const usa = LatLng(27.767778,-82.6525);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width:350,height:420,
      child:FlutterMap(mapController:controller,
        options:const MapOptions(initialZoom:4,minZoom:0,maxZoom:18),children:const [])))));
    controller.fitCamera(CameraFit.bounds(bounds:LatLngBounds.fromPoints([japan,usa]),
      padding:const EdgeInsets.all(90),maxZoom:8));
    await tester.pump();
    expect(controller.camera.visibleBounds.contains(japan),isTrue);
    expect(controller.camera.visibleBounds.contains(usa),isTrue);
    expect(controller.camera.zoom,lessThan(2));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('trackpad scale and two-finger pinch change map zoom', (tester) async {
    final controller = MapController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width:400,height:400,
      child: MapScaleListener(controller:controller,child:FlutterMap(mapController:controller,
        options:const MapOptions(initialZoom:5,minZoom:2,maxZoom:18),children:const []))))));
    await tester.sendEventToBinding(const PointerScaleEvent(position:Offset(200,200),scale:2));
    await tester.pump();
    expect(controller.camera.zoom,closeTo(6,.001));
    await tester.sendEventToBinding(const PointerScaleEvent(position:Offset(200,200),scale:.5));
    await tester.pump();
    expect(controller.camera.zoom,closeTo(5,.001));
    final a=await tester.startGesture(const Offset(160,200),pointer:1);
    final b=await tester.startGesture(const Offset(240,200),pointer:2);
    await a.moveTo(const Offset(120,200)); await b.moveTo(const Offset(280,200));
    await tester.pump();
    await a.moveTo(const Offset(80,200)); await b.moveTo(const Offset(320,200));
    await tester.pump();
    expect(controller.camera.zoom,greaterThan(5));
    await a.up(); await b.up();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
