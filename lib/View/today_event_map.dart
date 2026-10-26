import 'dart:async';
import 'dart:convert';
import '../widgets/map_scale_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../tools/Env.dart';
import '../logic/today_event_map.dart';

class TodayEventMap extends StatefulWidget {
  const TodayEventMap({super.key});
  @override
  State<TodayEventMap> createState() => _TodayEventMapState();
}
class _TodayEventMapState extends State<TodayEventMap> {
  final controller = MapController();
  List<Map<String,dynamic>> entries = [];
  String date = '';
  String? error;
  bool loading = true;
  bool mapReady = false;
  Timer? timer;
  @override
  void initState() { super.initState(); _load(); timer = Timer.periodic(const Duration(minutes:5), (_) => _load()); }
  @override
  void dispose() { timer?.cancel(); controller.dispose(); super.dispose(); }
  Future<void> _load() async {
    try {
      final response = await http.get(Env.api('/today-map')).timeout(const Duration(seconds:30));
      if (response.statusCode!=200) throw const FormatException();
      final data = Map<String,dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map);
      final nextEntries = todayMapEntries(data);
      final refit = date != '${data['date']}' ||
          (points.isEmpty && nextEntries.any((e) => e['located'] == true));
      if(mounted) setState(() { date='${data['date']}'; entries=nextEntries; loading=false; error=null; });
      if(mounted && mapReady && refit) WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted) fit(); });
    } catch (_) { if(mounted) setState(() { loading=false; error='開催情報を取得できませんでした'; }); }
  }
  List<LatLng> get points => entries.where((e)=>e['located']==true).map((e)=>LatLng((e['latitude'] as num).toDouble(),(e['longitude'] as num).toDouble())).toList();
  void fit() {
    final p=points;
    if(p.length>1) { controller.fitCamera(CameraFit.bounds(bounds:LatLngBounds.fromPoints(p),padding:const EdgeInsets.all(90),maxZoom:8)); }
    else { controller.move(p.isEmpty ? const LatLng(36,138) : p.first, p.isEmpty ? 4 : 7); }
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
    final groups=<String,List<Map<String,dynamic>>>{};
    for(final e in entries.where((e)=>e['located']==true)) {
      groups.putIfAbsent('${e['latitude']}:${e['longitude']}',()=>[]).add(e);
    }
    final unknown=entries.where((e)=>e['located']!=true).toList();
    return Card(margin:const EdgeInsets.only(top:12),child:Padding(padding:const EdgeInsets.all(8),child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[Expanded(child:Text('今日の開催マップ${date.isEmpty ? '' : '（$date・日本時間）'}',style:const TextStyle(fontWeight:FontWeight.bold))),
          IconButton(tooltip:'開催情報を更新',onPressed:_load,icon:const Icon(Icons.refresh))]),
        if(loading) const LinearProgressIndicator(),
        if(error!=null) Text(error!,style:const TextStyle(color:Colors.red)),
        if(!loading && entries.isEmpty && error==null) const Text('今日の開催情報はありません。'),
        SizedBox(height:420,child:ClipRRect(borderRadius:BorderRadius.circular(6),child:Stack(children:[
          MapScaleListener(controller: controller, child: FlutterMap(mapController:controller,
            options:MapOptions(initialCenter:const LatLng(36,138),initialZoom:4,minZoom:0,maxZoom:18,
              interactionOptions: InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate, cursorKeyboardRotationOptions: CursorKeyboardRotationOptions.disabled()),
              onMapReady:() { mapReady=true; fit(); }),children:[
              TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'jp.yakyuu.japan'),
              MarkerLayer(markers:[for(final rows in groups.values) Marker(
                point:LatLng((rows.first['latitude'] as num).toDouble(),(rows.first['longitude'] as num).toDouble()),
                width:176,height:96,alignment:Alignment.topCenter,
                child:GestureDetector(onTap:()=>details(rows),child:Align(alignment:Alignment.bottomCenter,child:Column(mainAxisSize:MainAxisSize.min,children:[
                  Container(padding:const EdgeInsets.all(6),decoration:BoxDecoration(
                    color:Colors.white,border:Border.all(color:color('${rows.first['kind']}'),width:2),borderRadius:BorderRadius.circular(8),
                    boxShadow:const [BoxShadow(color:Colors.black26,blurRadius:4)]),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                      Text('${rows.first['header'] ?? rows.first['kind']} ${rows.first['time']}',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:11,fontWeight:FontWeight.bold,color:color('${rows.first['kind']}'))),
                      Text('${rows.first['title']}',maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11)),
                      Text('${rows.first['venue']}${rows.length>1 ? ' ほか${rows.length-1}件' : ''}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10)),
                    ])),
                  Icon(Icons.arrow_drop_down,color:color('${rows.first['kind']}'),size:16),
                ]))),
              )]),
            ])),
          Positioned(right:6,top:6,child:Material(elevation:2,borderRadius:BorderRadius.circular(6),child:Column(children:[
            IconButton(tooltip:'拡大',onPressed:()=>controller.move(controller.camera.center,(controller.camera.zoom+1).clamp(0,18).toDouble()),icon:const Icon(Icons.add)),
            IconButton(tooltip:'縮小',onPressed:()=>controller.move(controller.camera.center,(controller.camera.zoom-1).clamp(0,18).toDouble()),icon:const Icon(Icons.remove)),
            IconButton(tooltip:'すべての開催地を表示',onPressed:fit,icon:const Icon(Icons.fit_screen)),
          ]))),
          Positioned(right:0,bottom:0,child:ColoredBox(color:Colors.white,child:InkWell(
            onTap:()=>launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
            child:const Padding(padding:EdgeInsets.all(3),child:Text('© OpenStreetMap contributors',style:TextStyle(fontSize:10)))))),
        ]))),
        const Text('タッチパッド・指のピンチ・ホイール・＋／−で拡大縮小。吹き出しを押すと詳細を表示します。',style:TextStyle(fontSize:11,color:Colors.black54)),
        if(unknown.isNotEmpty) ExpansionTile(title:Text('会場の位置未確認（${unknown.length}件）'),children:[
          for(final e in unknown) ListTile(dense:true,title:Text('${e['title']}'),subtitle:Text('${e['venue'] ?? ''}'),onTap:()=>details([e]))]),
      ])));
  }
}
