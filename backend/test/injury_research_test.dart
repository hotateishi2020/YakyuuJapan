import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../app/InjuryResearch.dart';
import '../app/NpbResearchPolicy.dart';

void main() {
  final event = <String,dynamic>{'team':'阪神','name':'対象選手','injury':'右肩痛',
    'injured_at':'不明','return_at':'不明','source_as_of':'2026-10-01',
    'source_url':'https://hanshintigers.jp/news/test.html',
    'evidence':'対象選手は右肩痛でリハビリを継続している。','estimated':true,'status':'injured'};
  test('禁止サイトと偽装ホスト・未来記事・根拠のない推定は採用しない', () {
    final body='<p>${event['evidence']}</p>';
    final now=DateTime(2026,10,23);
    expect(InjuryResearch.validate(event,body,now),true);
    for(final url in ['https://www.my-favorite-giants.net/npb/IL.htm','https://hanshintigers.jp.evil.example/a','http://hanshintigers.jp/a']) {
      expect(injurySource(url),false);
      expect(InjuryResearch.validate({...event,'source_url':url},body,now),false);
    }
    expect(InjuryResearch.validate({...event,'source_as_of':'2026-12-01'},body,now),false);
    expect(InjuryResearch.validate(event,'別人が右肩痛',now),false);
    expect(InjuryResearch.validate({...event,'status':'recovered'},body,now),false);
  });
  test('記事のリダイレクト先にも禁止サイトを許可しない', () async {
    var calls=0;
    final client=MockClient((r) async {calls++;return http.Response('',302,headers:{'location':'https://www.my-favorite-giants.net/npb/IL.htm'});});
    await expectLater(InjuryResearch.source(client,'https://hanshintigers.jp/a'),throwsFormatException);
    expect(calls,1);
    client.close();
  });
  test('APIは検索とJSON形式を要求し12球団調査の完了を確認する', () async {
    var complete=true;
    final client=MockClient((r) async {
      final request=jsonDecode(r.body) as Map;
      expect(r.url.path,'/v1/responses');
      expect(request['model'],'configured-model');
      expect(request['tool_choice'],'required');
      expect(request['tools'][0]['filters']['allowed_domains'],isNot(contains('my-favorite-giants.net')));
      expect(request['text']['format']['strict'],true);
      return http.Response(jsonEncode({'status':'completed','output':[
        {'type':'web_search_call','status':'completed'},
        {'type':'message','content':[{'type':'output_text','text':jsonEncode({'reviewed_teams':complete?researchTeams:['阪神'],'players':[event]})}]},
      ]}),200,headers:{'content-type':'application/json; charset=utf-8'});
    });
    Future<List<Map<String,dynamic>>> query()=>InjuryResearch.query(client,key:'test',model:'configured-model',day:'2026-10-23',current:[]);
    expect(await query(),hasLength(1));
    complete=false;
    await expectLater(query(),throwsFormatException);
    client.close();
  });
  test('API失敗や未完了応答では空一覧として処理しない', () async {
    for(final response in [http.Response('',500),http.Response('{"status":"incomplete","output":[]}',200)]) {
      final client=MockClient((_) async=>response);
      await expectLater(InjuryResearch.query(client,key:'test',model:'configured-model',day:'2026-10-23',current:[]),throwsA(anyOf(isA<StateError>(), isA<FormatException>())));
      client.close();
    }
  });
}
