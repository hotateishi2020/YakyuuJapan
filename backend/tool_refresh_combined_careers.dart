import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/CombinedCareerRecords.dart';
import 'app/StrengthUsage.dart';

/// Run offline, never while serving a browser request. Official regular seasons only.
Future<void> main() async {
  final client=http.Client();
  final ids=usageMaps(usageMap(jsonDecode(File('data/npb_mlb_player_ids.json').readAsStringSync()))['players']);
  final cache=Directory('/tmp/koko_combined_career_cache')..createSync(recursive:true);
  final results=<Map<String,dynamic>>[], errors=<String>[];
  Future<String> get(String url) async {
    final response=await client.get(Uri.parse(url)).timeout(const Duration(seconds:30));
    if(response.statusCode!=200) throw HttpException('HTTP ${response.statusCode}');
    return utf8.decode(response.bodyBytes);
  }
  try {
    for(var offset=0;offset<ids.length;offset+=6) {
      await Future.wait(ids.skip(offset).take(6).map((id) async {
        final cached=File('${cache.path}/${id['npb_id']}.json');
        try {
          if(cached.existsSync() && DateTime.now().difference(cached.lastModifiedSync()).inHours < 24) {
            final old=usageMap(jsonDecode(cached.readAsStringSync()));
            if(old['mlb_id']==id['mlb_id']) {results.add(old);return;}
          }
          final npbUrl='https://npb.jp/bis/players/${id['npb_id']}.html';
          final mlbUrl='https://statsapi.mlb.com/api/v1/people/${id['mlb_id']}?hydrate=stats(group=[hitting,pitching],type=[career],sportIds=[1])';
          final j=parseNpbCareer(await get(npbUrl));
          final person=usageMaps(usageMap(jsonDecode(await get(mlbUrl)))['people']).single;
          if(j['birth_date']!=person['birthDate']) throw StateError('Birth dates differ');
          final mlb=<String,dynamic>{};
          for(final group in usageMaps(person['stats'])) {
            final splits=usageMaps(group['splits']);
            if(splits.length!=1) continue;
            mlb['${usageMap(group['group'])['displayName']}']=usageMap(splits.single['stat']);
          }
          if(mlb.isEmpty) throw StateError('No MLB career stats');
          final row={...id,'name':j['name'],'name_en':person['fullName'],'birth_country':person['birthCountry'],'active':j['active']==true || person['active']==true,
            'checked_at':DateTime.now().toUtc().toIso8601String(),'npb':j,'mlb':mlb,'sources':[npbUrl,mlbUrl]};
          cached.writeAsStringSync(jsonEncode(row)); results.add(row);
        } catch(e) {errors.add('${id['npb_id']} ${id['name_en']}: $e');}
      }));
      print('${offset+6>ids.length?ids.length:offset+6}/${ids.length}; verified ${results.length}; errors ${errors.length}');
    }
    final unique = <int,Map<String,dynamic>>{};
    for(final row in results) {
      final id=usageInt(row['mlb_id']);
      if(unique.containsKey(id) && unique[id]!['npb_id']!=row['npb_id']) throw StateError('Ambiguous NPB identity for MLB $id');
      unique[id]=row;
    }
    final verified=unique.values.toList();
    final baseline=usageMap(jsonDecode(File('data/records.json').readAsStringSync()));
    final careers={for(final org in ['npb','mlb']) org:mergeCombinedCareer(usageMaps(usageMap(baseline[org])['career']),verified,npb:org=='npb')};
    final output=File('data/combined_career_records.json');
    final temp=File('${output.path}.tmp');
    temp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'checked_at':DateTime.now().toUtc().toIso8601String(),'players':verified,'career':careers,'unresolved':errors}));
    temp.renameSync(output.path);
    for(final e in errors) {stderr.writeln(e);}
  } finally {client.close();}
}
