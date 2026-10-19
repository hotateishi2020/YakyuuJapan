import 'package:test/test.dart';
import '../app/NpbRosterTransactions.dart';
void main(){
 test('現役ドラフトと人的補償を通常トレードから区別する',(){
  String page(String note)=>'<div><table><tr><th class="trdate">2026/7/30</th><td class="trname"><a href="/bis/players/123.html">選手</a></td><td class="trpos">投　手</td><td class="trteam">読売</td><td class="trteam">中日</td></tr></table><p class="note">$note</p></div>';
  for(final entry in {'現役ドラフトに伴う契約譲渡':'現役ドラフト','FA移籍に伴う契約譲渡':'人的補償','':'トレード'}.entries){
   final rows=parseNpbTransactions(page(entry.key),'pn_traded',2026);
   expect(rows,hasLength(2));expect(rows.last['move_method'],entry.value);expect(rows.last['previous_team_name'],'巨人');expect(rows.first['departure_type'],'transfer');
  }
 });
 test('FA宣言と契約締結と宣言残留を混同しない',(){
  String page(String team,String date)=>'<table><tr><td class="pnteam">中日</td><td class="pnname"><a href="/bis/players/123.html">選手</a></td><td class="pnpos">投手</td><td class="pndate">$date</td><td class="pnteam">$team</td></tr></table>';
  final y=DateTime.now().year;
  expect(parseNpbTransactions(page('',''),'fa_filed',y).single['move_status'],'FA宣言（移籍先未定）');
  expect(parseNpbTransactions(page('巨人','$y/11/20'),'fa_filed',y).last['move_method'],'FA移籍');
  expect(parseNpbTransactions(page('中日','$y/11/20'),'fa_filed',y).single['move_status'],'FA残留');
 });
}
