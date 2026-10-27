import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:Yakyuu_Japan/logic/date_line_world_map.dart';

void main() {
  testWidgets('wide map shows Japan and US markers once and limits panning', (tester) async {
    tester.view.physicalSize=const Size(1800,700);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller=MapController();
    final zoom=singleWorldMinZoom(1800,420);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(height:420,
      child:FlutterMap(mapController:controller,options:MapOptions(
        initialCenter:const LatLng(20,180),initialZoom:zoom,minZoom:0,
        cameraConstraint:const DateLineWorldConstraint()),children:[MarkerLayer(markers:[
          const Marker(point:LatLng(33,130),child:Text('日本の試合')),
          const Marker(point:LatLng(28,-82),child:Text('米国の試合')),
        ])])))));
    expect(controller.camera.center.longitude,closeTo(180,.01));
    expect(find.text('日本の試合'),findsOneWidget);
    expect(find.text('米国の試合'),findsOneWidget);
    controller.move(const LatLng(20,180),0);
    await tester.pump();
    expect(controller.camera.zoom,closeTo(zoom,.01));
    controller.move(const LatLng(20,-140),zoom);
    await tester.pump();
    expect(controller.camera.center.longitude,closeTo(180,.2));
    expect(find.text('日本の試合'),findsOneWidget);
    expect(find.text('米国の試合'),findsOneWidget);
    controller.move(const LatLng(35,138),zoom+2);
    await tester.pump();
    expect(controller.camera.zoom,closeTo(zoom+2,.01));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
