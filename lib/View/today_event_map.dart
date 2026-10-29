import 'dart:math' as math;
import 'dart:convert';
import '../tools/home_data_cache.dart';
import '../logic/date_line_world_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../tools/Env.dart';
import '../logic/today_event_map.dart';

final homeMapInteractionOptions = InteractionOptions(
  flags: InteractiveFlag.drag,
  cursorKeyboardRotationOptions: CursorKeyboardRotationOptions.disabled(),
);

class TodayEventMap extends StatefulWidget {
  const TodayEventMap({super.key});
  @override
  State<TodayEventMap> createState() => _TodayEventMapState();
}
class _TodayEventMapState extends State<TodayEventMap> with AutomaticKeepAliveClientMixin {
  final controller = MapController();
  List<Map<String,dynamic>> entries = [];
  String date = '';
  String? error;
  bool loading = true;
  bool mapReady = false;
  bool _fetching = false;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  Future<void> _load({bool refresh = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final day = DateTime.now().toUtc().add(const Duration(hours: 9)).toIso8601String().substring(0,10);
      final data = await HomeDataCache.read('today-map:$day', () async {
        final response = await http.get(Env.api('/today-map')).timeout(const Duration(seconds:30));
        if (response.statusCode!=200) throw const FormatException();
        return Map<String,dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map);
      }, refresh: refresh);
      final nextEntries = todayMapEntries(data);
      final refit = date != '${data['date']}' ||
          (points.isEmpty && nextEntries.any((e) => e['located'] == true));
      if(mounted) setState(() { date='${data['date']}'; entries=nextEntries; loading=false; error=null; });
      if(mounted && mapReady && refit) WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted) fit(); });
    } catch (_) { if(mounted) setState(() { loading=false; error='開催情報を取得できませんでした'; }); }
    finally { _fetching = false; }
  }
  List<LatLng> get points => entries.where((e)=>e['located']==true).map((e)=>LatLng((e['latitude'] as num).toDouble(),(e['longitude'] as num).toDouble())).toList();
  void fit() {
    controller.move(const LatLng(20,180), singleWorldMinZoom(controller.camera.size.width, controller.camera.size.height));
  }
  Color color(String kind) => switch(kind) {'試合'=>Colors.red.shade700,'キャンプ'=>Colors.green.shade700,'自主トレ'=>Colors.teal,'トークショー'=>Colors.purple,'式典'=>Colors.orange.shade800,_=>Colors.blue.shade700};
  void details(List<Map<String,dynamic>> rows) => showDialog<void>(context:context,builder:(context)=>AlertDialog(
    title:Text('${rows.first['venue']}'),
    content:SizedBox(width:400,child:ListView(shrinkWrap:true,children:[for(final e in rows) Padding(
      padding:const EdgeInsets.only(bottom:12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${e['header'] ?? e['kind']} ${e['time']}',style:const TextStyle(fontWeight:FontWeight.bold)),
        Text('${e['title']}'), if('${e['detail'] ?? ''}'.isNotEmpty) Text('${e['detail']}'),
        if(Uri.tryParse('${e['source_url']}')?.scheme=='https') TextButton(
          onPressed:()=>launchUrl(Uri.parse('${e['source_url']}'),mode:LaunchMode.externalApplication),child:const Text('開催情報を見る')),
      ])),])),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('閉じる'))]));
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final groups=<String,List<Map<String,dynamic>>>{};
    for(final e in entries.where((e)=>e['located']==true)) {
      groups.putIfAbsent('${e['latitude']}:${e['longitude']}',()=>[]).add(e);
    }
    final unknown=entries.where((e)=>e['located']!=true).toList();
    return Card(margin:const EdgeInsets.only(top:12),child:Padding(padding:const EdgeInsets.all(8),child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[Expanded(child:Text('今日の開催マップ${date.isEmpty ? '' : '（$date・日本時間）'}',style:const TextStyle(fontWeight:FontWeight.bold))),
          IconButton(tooltip:'開催情報を更新',onPressed:()=>_load(refresh:true),icon:const Icon(Icons.refresh))]),
        if(loading) const LinearProgressIndicator(),
        if(error!=null) Text(error!,style:const TextStyle(color:Colors.red)),
        if(!loading && entries.isEmpty && error==null) const Text('今日の開催情報はありません。'),
        SizedBox(height:420,child:LayoutBuilder(builder:(context, constraints) {
          final minZoom=singleWorldMinZoom(constraints.maxWidth, constraints.maxHeight);
          return ClipRRect(borderRadius:BorderRadius.circular(6),child:Stack(children:[
          FlutterMap(mapController:controller,
            options:MapOptions(backgroundColor:const Color(0xFFAAD3DF),initialCenter:const LatLng(20,180),initialZoom:minZoom,minZoom:0,maxZoom:18,
              cameraConstraint:const DateLineWorldConstraint(),
              interactionOptions: homeMapInteractionOptions,
              onMapReady:() { mapReady=true; fit(); }),children:[
              TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'jp.yakyuu.japan'),
              Builder(builder: (context) {
                final camera = MapCamera.of(context);
                final occupied = <Rect>[];
                final callouts = <Widget>[];
                for (final rows in groups.values) {
                    final longitude = (rows.first['longitude'] as num).toDouble();
                    final anchor = camera.latLngToScreenOffset(LatLng(
                      (rows.first['latitude'] as num).toDouble(), longitude < 0 ? longitude + 360 : longitude));
                    if (!(Offset.zero & camera.size).contains(anchor)) continue;
                    final rect = eventMapBubbleRect(rows, camera.size, anchor,
                        MediaQuery.textScalerOf(context), Directionality.of(context), occupied);
                    occupied.add(rect);
                    callouts.add(EventMapCallout(rows: rows, accent: color('${rows.first['kind']}'),
                        anchor: anchor, bubbleRect: rect, onTap: () => details(rows)));
                }
                return Stack(children: callouts);
              }),
            ]),
          Positioned(right:0,bottom:0,child:ColoredBox(color:Colors.white,child:InkWell(
            onTap:()=>launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
            child:const Padding(padding:EdgeInsets.all(3),child:Text('© OpenStreetMap contributors',style:TextStyle(fontSize:10)))))),
        ]));
        })),
        if(unknown.isNotEmpty) ExpansionTile(title:Text('会場の位置未確認（${unknown.length}件）'),children:[
          for(final e in unknown) ListTile(dense:true,title:Text('${e['title']}'),subtitle:Text('${e['venue'] ?? ''}'),onTap:()=>details([e]))]),
      ])));
  }
}

List<({String text, TextStyle style})> _calloutLines(List<Map<String, dynamic>> rows, Color accent) {
  final first = rows.first;
  return [
    (text: '${first['header'] ?? first['kind']} ${first['time'] ?? ''}'.trim(),
      style: TextStyle(inherit: false, fontSize: 11, height: 1.2, fontWeight: FontWeight.bold, color: accent)),
    (text: '${first['title']}', style: const TextStyle(inherit: false, fontSize: 11, height: 1.2, color: Colors.black87)),
    (text: '${first['venue']}${rows.length > 1 ? ' ほか${rows.length - 1}件' : ''}', style: const TextStyle(inherit: false, fontSize: 10, height: 1.2, color: Colors.black87)),
  ];
}

/// Measure the complete text, then keep the label inside the map and away from
/// labels already placed. The geographic anchor never moves with the label.
Rect eventMapBubbleRect(List<Map<String, dynamic>> rows, Size viewport, Offset anchor,
    TextScaler scaler, TextDirection direction, [List<Rect> occupied = const []]) {
  final painters = [for (final line in _calloutLines(rows, Colors.black))
    TextPainter(text: TextSpan(text: line.text, style: line.style), textDirection: direction, textScaler: scaler)..layout()];
  final maxWidth = math.max(32.0, viewport.width - 16);
  var width = math.min(math.min(176.0, maxWidth), painters.fold<double>(0, (w, p) => math.max(w, p.width)) + 16);
  double height() {
    for (final painter in painters) { painter.layout(maxWidth: math.max(1, width - 16)); }
    return painters.fold<double>(16, (h, p) => h + p.height).ceilToDouble();
  }
  var h = height();
  if (h > viewport.height - 40) { width = maxWidth; h = height(); }
  final maxY = math.max(8.0, viewport.height - 24 - h);
  Rect at(double x, double y) => Rect.fromLTWH(
      x.clamp(8.0, math.max(8.0, viewport.width - width - 8)), y.clamp(8.0, maxY), width, h);
  final preferred = at(anchor.dx - width / 2, anchor.dy - h - 24);
  final candidates = [preferred,
    at(anchor.dx + 24, anchor.dy - h / 2),
    at(anchor.dx - width - 24, anchor.dy - h / 2),
    at(anchor.dx - width / 2, anchor.dy + 24),
    for (double y = 8; y <= maxY; y += h + 8)
      for (double x = 8; x <= viewport.width - width - 8; x += width + 8) at(x, y),
  ];
  final available = candidates.where((r) => !occupied.any((other) => other.inflate(4).overlaps(r))).toList();
  available.sort((a, b) => (a.center - preferred.center).distanceSquared.compareTo((b.center - preferred.center).distanceSquared));
  return available.isEmpty ? preferred : available.first;
}

class EventMapCallout extends StatelessWidget {
  const EventMapCallout({super.key, required this.rows, required this.accent,
    required this.onTap, required this.anchor, this.bubbleRect});
  final List<Map<String, dynamic>> rows;
  final Color accent;
  final VoidCallback onTap;
  final Offset anchor;
  final Rect? bubbleRect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final rect = bubbleRect ?? eventMapBubbleRect(rows, constraints.biggest, anchor,
        MediaQuery.textScalerOf(context), Directionality.of(context));
    final end = Offset(anchor.dx.clamp(rect.left, rect.right), anchor.dy.clamp(rect.top, rect.bottom));
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: CustomPaint(
        key: const ValueKey('map-callout-line'), painter: _CalloutLine(anchor, end)))),
      Positioned.fromRect(rect: rect, child: GestureDetector(onTap: onTap,
        child: Container(key: const ValueKey('map-callout-bubble'),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: accent, width: 2),
            borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final line in _calloutLines(rows, accent)) Text(line.text, style: line.style)]),
        ),
      )),
      Positioned(left: anchor.dx - 5, top: anchor.dy - 5, child: GestureDetector(onTap: onTap,
        child: Container(key: const ValueKey('map-venue-dot'), width: 10, height: 10,
          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
      )),
    ]);
  });
}

class _CalloutLine extends CustomPainter {
  const _CalloutLine(this.start, this.end);
  final Offset start;
  final Offset end;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawLine(start, end, Paint()..color = Colors.red..strokeWidth = 1.5);
  @override
  bool shouldRepaint(_CalloutLine oldDelegate) => start != oldDelegate.start || end != oldDelegate.end;
}
