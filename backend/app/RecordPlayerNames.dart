import 'dart:convert';
import 'dart:io';
import 'PlayerIdentityName.dart';

/// Historical award feeds can lack player IDs. Only unambiguous, sourced full
/// English names are fallbacks; the player master's Japanese names win first.
dynamic localizeRecordTitleNames(dynamic titles) {
  final file=File('${Directory('backend/assets').existsSync() ? 'backend/' : ''}assets/data/mlb_record_names.json');
  if(!file.existsSync())return titles;
  final data=jsonDecode(file.readAsStringSync()) as Map;
  final aliases=<String,String>{};
  final ambiguous=<String>{};
  for(final row in data['names'] as List) {
    final key=playerIdentityKey('${row['name_en']}');
    final name='${row['name_ja']}';
    if(aliases.containsKey(key)&&aliases[key]!=name)ambiguous.add(key);
    aliases[key]=name;
  }
  aliases.removeWhere((key,_)=>ambiguous.contains(key));
  return localizePlayerPayload(titles, {}, aliases);
}
