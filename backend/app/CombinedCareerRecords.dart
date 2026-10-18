import 'package:html/parser.dart' as html;
import 'RecordCatalog.dart';
import 'StrengthUsage.dart';

int careerOuts(dynamic innings) {
  final parts = '$innings'.replaceAll(RegExp(r'\s'), '').split('.');
  return (int.tryParse(parts.first) ?? 0) * 3 + (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
}

Map<String, dynamic> parseNpbCareer(String body) {
  final doc = html.parse(body);
  final name = doc.querySelector('li#pc_v_name')?.text.trim();
  if (name == null || name.isEmpty) throw const FormatException('NPB player name missing');
  final result = <String, dynamic>{'name': name.replaceAll(RegExp(r'[\s　]'), '')};
  for (final code in ['b', 'p']) {
    final table = doc.querySelector('#tablefix_$code');
    if (table == null) continue;
    final headers = table.querySelector('thead > tr')?.children ?? [];
    final cells = table.querySelector('tfoot > tr')?.children ?? [];
    if (headers.length != cells.length || cells.isEmpty) throw FormatException('NPB $code totals missing');
    result[code == 'b' ? 'hitting' : 'pitching'] = {
      for (var i = 2; i < headers.length; i++) headers[i].text.trim(): cells[i].text.replaceAll(RegExp(r'[\s　]'), '')
    };
  }
  final birthRow = doc.querySelectorAll('#pc_bio tr').where((r) => r.querySelector('th')?.text.trim() == '生年月日').firstOrNull;
  final numbers = RegExp(r'\d+').allMatches(birthRow?.text ?? '').map((m) => int.parse(m[0]!)).toList();
  if (numbers.length == 3) result['birth_date'] = '${numbers[0]}-${numbers[1].toString().padLeft(2,'0')}-${numbers[2].toString().padLeft(2,'0')}';
  result['active'] = !(doc.querySelector('#pc_v_wrap')?.classes.contains('old') ?? true);
  return result;
}

/// Comparison ranking, not an official NPB/MLB ranking. Never average rates.
List<Map<String, dynamic>> mergeCombinedCareer(List<Map<String, dynamic>> records, List<Map<String, dynamic>> players, {required bool npb}) {
  String normalize(dynamic name) => '$name'.replaceAll(RegExp(r'（.*?）|\(.*?\)'), '').replaceAll(RegExp(r'[\s　]'), '');
  num n(Map<String, dynamic> row, String key) => num.tryParse('${row[key]}') ?? 0;
  return [for (final record in records) (() {
    final metric = recordMetrics.where((m) => m.key == record['key']).firstOrNull;
    if (metric == null || metric.key == 'hp') return record;
    final npbField = {'avg':'打率','slg':'長打率','obp':'出塁率','era':'防御率','hits':'安打','hr':'本塁打','rbi':'打点','sb':'盗塁','wins':'勝利','so':'三振','holds':'H','saves':'セーブ'}[metric.key];
    String shortName(dynamic name) => normalize(name).replaceFirst(RegExp(r'^(?:[A-ZＡ-Ｚ][.．・])+'), '');
    String aliasValue(num? value) => value == null ? 'null' : metric.unit.isEmpty ? value.toStringAsFixed(metric.key == 'era' ? 2 : 3) : '$value';
    final aliases=<String,List<int>>{};
    for(final p in players) {
      final raw=usageMap(usageMap(p['npb'])[metric.group]);
      final value=num.tryParse('${raw[npbField]}');
      if(value!=null) aliases.putIfAbsent('${shortName(p['name'])}:${aliasValue(value)}',()=>[]).add(usageInt(p['mlb_id']));
    }
    final leaders = usageMaps(record['leaders']).map((p) => Map<String,dynamic>.from(p)).toList();
    for (final player in players) {
      final j = usageMap(usageMap(player['npb'])[metric.group]);
      final u = usageMap(usageMap(player['mlb'])[metric.group]);
      if (n(j, metric.group == 'pitching' ? '登板' : '試合') <= 0 || n(u, 'gamesPlayed') <= 0) continue;
      final totalAb = n(j, '打数') + n(u, 'atBats');
      final totalPa = n(j, '打席') + n(u, 'plateAppearances');
      final outs = careerOuts(j['投球回']) + careerOuts(u['inningsPitched']);
      final hits = n(j,'安打') + n(u,'hits');
      num? value;
      switch (metric.key) {
        case 'avg': case 'slg': case 'obp':
          if (npb ? totalAb < 4000 : totalPa < 3000) continue;
          if (metric.key == 'avg') value = hits / totalAb;
          if (metric.key == 'slg') value = (n(j,'塁打') + n(u,'totalBases')) / totalAb;
          if (metric.key == 'obp') {
            final bb = n(j,'四球') + n(u,'baseOnBalls'), hbp = n(j,'死球') + n(u,'hitByPitch');
            final denom = totalAb + bb + hbp + n(j,'犠飛') + n(u,'sacFlies');
            if (denom > 0) value = (hits + bb + hbp) / denom;
          }
        case 'era':
          if (outs < (npb ? 6000 : 3000)) continue;
          value = (n(j,'自責点') + n(u,'earnedRuns')) * 27 / outs;
        default:
          final field = {'hits':'安打','hr':'本塁打','rbi':'打点','sb':'盗塁','wins':'勝利','so':'三振','holds':'H','saves':'セーブ'}[metric.key];
          if (field == null || j[field] == null || u[metric.mlb] == null) continue;
          value = n(j,field) + n(u,metric.mlb);
      }
      if (value == null || !value.isFinite) continue;
      leaders.removeWhere((p) {
        if(!npb) return '${p['player_id']}' == '${player['mlb_id']}';
        if(normalize(p['name'])==normalize(player['name'])) return true;
        // Official leader tables omit foreign-player initials. Match those
        // aliases only when the original NPB value identifies one player.
        final ids=aliases['${shortName(p['name'])}:${aliasValue(num.tryParse('${p['value']}'))}'];
        return ids?.length==1 && ids!.single==usageInt(player['mlb_id']);
      });
      leaders.add({'name':normalize(player['name']), 'player_id':player['mlb_id'], 'value':metric.unit.isEmpty ? value.toStringAsFixed(metric.key == 'era' ? 2 : 3) : value.toInt(),
        'status':player['active'] == true ? 'active' : 'retired', 'combined':true});
    }
    leaders.sort((a,b) {
      final av = num.tryParse('${a['value']}') ?? 0, bv = num.tryParse('${b['value']}') ?? 0;
      final order=metric.lower ? av.compareTo(bv) : bv.compareTo(av);
      return order!=0 ? order : '${a['name']}'.compareTo('${b['name']}');
    });
    int rank=0;
    num? previous;
    for(var i=0;i<leaders.length;i++) {
      final value=num.tryParse('${leaders[i]['value']}');
      if(i==0 || value!=previous) rank=i+1;
      leaders[i]['rank']=rank; previous=value;
    }
    return {...record,'leaders':leaders.where((p)=>usageInt(p['rank'])<=50).toList(),
      'note':'${record['note'] ?? ''} 日米通算はNPB・MLBの公式戦を合算した比較記録。率は分母・分子から再計算（打撃：${npb ? '4000打数' : '3000打席'}以上、防御率：${npb ? '2000' : '1000'}投球回以上）。ホールドポイントは合算対象外。'};
  })()];
}
