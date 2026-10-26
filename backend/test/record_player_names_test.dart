import 'package:test/test.dart';
import '../app/RecordPlayerNames.dart';
import '../app/PlayerIdentityName.dart';
void main() {
 test('歴代タイトルの英語名は空白差・アクセント差を吸収し日本語名にする',(){
  final input=[{'year':2021,'categories':[{'label':'首位打者','players':[
   {'name':'YuliGurriel','value':'.319','team':'Astros'},
   {'name':'JoseAbreu','value':60},
   {'name':'大谷翔平','value':54},
  ]}]}];
  final result=localizeRecordTitleNames(input) as List;
  final players=result.single['categories'].single['players'] as List;
  expect(hasJapanesePlayerName(players[0]['name']),true);
  expect(hasJapanesePlayerName(players[1]['name']),true);
  expect(players[0]['value'],'.319');
  expect(players[0]['team'],'Astros');
  expect(players[2]['name'],'大谷翔平');
  expect(input.single['categories'],isNotNull);
 });
}
