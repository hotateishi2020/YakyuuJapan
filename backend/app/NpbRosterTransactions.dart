import 'package:html/parser.dart' as html;

String? npbMoveTeam(String value) {
  const teams={'読売':'巨人','巨人':'巨人','阪神':'阪神','中日':'中日','ヤクルト':'ヤクルト','DeNA':'DeNA','広島':'広島','ソフトバンク':'ソフトバンク','西武':'西武','日本ハム':'日本ハム','オリックス':'オリックス','楽天':'楽天','ロッテ':'ロッテ'};
  for(final e in teams.entries) { if(value.contains(e.key))return e.value; }
  return null;
}
String? _id(String? href)=>RegExp(r'/players/(\d+)\.html').firstMatch(href??'')?[1];
String _date(String text)=>text.trim().split('/').map((s)=>s.padLeft(2,'0')).join('-');

List<Map<String,dynamic>> parseNpbTransactions(String source,String url,int year) {
 final doc=html.parse(source); final result=<Map<String,dynamic>>[];
 if(url.contains('pn_traded')) {
  for(final table in doc.querySelectorAll('table')) {
   String? date; final note=table.parent?.querySelector('.note')?.text ?? '';
   final method=note.contains('現役ドラフト')?'現役ドラフト':note.contains('FA移籍')?'人的補償':'トレード';
   for(final row in table.querySelectorAll('tr')) {
    final dateCell=row.querySelector('.trdate'); if(dateCell!=null) date=_date(dateCell.text);
    final person=row.querySelector('.trname a'); final sides=row.querySelectorAll('.trteam');
    if(person==null||sides.length!=2||date==null)continue;
    final from=npbMoveTeam(sides[0].text),to=npbMoveTeam(sides[1].text);
    if(from==null||to==null||from==to)continue;
    final base=<String,dynamic>{'name':person.text.trim(),'player_key':'npb:${_id(person.attributes['href'])}','position_group':row.querySelector('.trpos')?.text.replaceAll(RegExp(r'\s|　'),''),'status_as_of':date,'status_source':url,'move_method':method};
    result.add({...base,'team':from,'kind':'departure','departure_type':'transfer','departure_reason':method,'destination_team_name':to});
    result.add({...base,'team':to,'kind':'arrival','previous_team_name':from});
   }
  }
 }else if(url.contains('fa_filed')) {
  for(final row in doc.querySelectorAll('tr')) {
   final person=row.querySelector('.pnname a'), sides=row.querySelectorAll('.pnteam');
   if(person==null||sides.isEmpty)continue;
   final from=npbMoveTeam(sides.first.text); if(from==null)continue;
   final to=sides.length>1?npbMoveTeam(sides.last.text):null;
   final signed=row.querySelector('.pndate')?.text.trim()??'';
   final base=<String,dynamic>{'name':person.text.trim(),'player_key':'npb:${_id(person.attributes['href'])}','position_group':row.querySelector('.pnpos')?.text.replaceAll(RegExp(r'\s|　'),''),'status_source':url,'status_as_of':signed.isNotEmpty?_date(signed):DateTime.now().toIso8601String().substring(0,10)};
   if(to!=null && signed.isNotEmpty) {
    if(from==to) {result.add({...base,'team':from,'kind':'status','move_status':'FA残留','status_year':DateTime.parse(_date(signed)).year});}
    else {
     result.add({...base,'team':from,'kind':'departure','departure_type':'transfer','departure_reason':'FA移籍','move_method':'FA移籍','destination_team_name':to});
     result.add({...base,'team':to,'kind':'arrival','move_method':'FA移籍','previous_team_name':from});
    }
   } else if(year==DateTime.now().year) {
    result.add({...base,'team':from,'kind':'status','move_status':'FA宣言（移籍先未定）','status_year':year});
   }
  }
 }else if(url.contains('fa_qualified')) {
  for(final row in doc.querySelectorAll('tr')) {
   final teamCell=row.querySelector('.fateam'); if(teamCell==null)continue;
   final team=npbMoveTeam(teamCell.text);if(team==null)continue;
   final cells=row.children.where((e)=>e.localName=='td').toList();
   for(var i=0;i<cells.length;i++) {
    for(final p in cells[i].querySelectorAll('a[href*="/players/"]')) {
     result.add({'team':team,'name':p.text.trim(),'player_key':'npb:${_id(p.attributes['href'])}','kind':'status','move_status':i<2?'国内FA権保有':'海外FA権保有','status_year':year,'status_as_of':DateTime.now().toIso8601String().substring(0,10),'status_source':url});
    }
   }
  }
 }
 return result;
}
