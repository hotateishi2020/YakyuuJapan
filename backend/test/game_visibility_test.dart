import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import '../app/GameVisibility.dart';

void main() {
  test('prediction-only cached responses are private for guests on every route and method', () async {
    final cached = jsonEncode({
      'predict_team': [{'username': '立石', 'id_team': 1}],
      'predict_player': [{'username': '江島', 'id_player': 2}],
      'stats_player': [{'stats': 16, 'id_users': '/1/', 'colors_user': 'blue'}],
      'stats_team': [{'wins': 80, 'team_name_tateishi': '阪神', 'flg_atari_ejima': true}],
    });
    int? identity;
    final handler = gameVisibility((_) async => identity)((_) => Response.ok(cached,
      headers: {'content-type': 'application/json'}));
    for (final path in ['/predictions', '/predictions/part?part=players', '/predictions/part?part=standings', '/home-dashboard', '/player-detail']) {
      for (final method in ['GET', 'POST']) {
        for (final id in [1, 2, 3, null]) {
          identity = id;
          final response = await handler(Request(method, Uri.parse('http://localhost$path')));
          final data = jsonDecode(await response.readAsString());
          expect(data['predict_team'] != null, id != null);
          expect(data['stats_player'][0]['colors_user'] != null, id != null);
          expect(data['stats_team'][0]['team_name_tateishi'] != null, id != null);
          expect(data['stats_player'][0]['stats'], 16);
          expect(data['stats_team'][0]['wins'], 80);
          expect(response.headers['cache-control'], 'private, no-store');
          expect(response.headers['vary'], contains('Authorization'));
        }
      }
    }
  });

  test('group responses are private and never return a cached group to guests', () async {
    int? identity = 1;
    final handler = gameVisibility((_) async => identity)((_) => Response.ok(
      jsonEncode({'groups': [{'users': [{'name': '立石', 'pick': '選手'}]}], 'title_catalog': ['打率']}),
      headers: {'content-type': 'application/json'}));
    for (final id in [1, null]) {
      identity = id;
      final response = await handler(Request('GET', Uri.parse('http://localhost/predict-groups?userid=1')));
      final data = jsonDecode(await response.readAsString());
      expect(data['groups'], id == null ? isEmpty : isNotEmpty);
      expect(data['title_catalog'], ['打率']);
      expect(response.headers['cache-control'], 'private, no-store');
    }
  });

  test('same cached body is filtered by authenticated identity on every response', () async {
    final cached = jsonEncode({'games': [
      {'id_game': 1, 'state': '8回表', 'score_home': 3, 'score_away': 7,
       'lineup': [{'plays': '左飛|out'}]},
      {'id_game': 2, 'state': '試合終了', 'score_home': 2, 'score_away': 1, 'txt_plays': '左飛|out'},
    ]});
    int? identity;
    final handler = gameVisibility((_) async => identity)((_) => Response.ok(cached,
      headers: {'content-type': 'application/json'}));
    for (final id in [1, null, 3, 2, 999]) {
      identity = id;
      final response = await handler(Request('GET', Uri.parse('http://localhost/predictions/part?part=games&userid=1')));
      final body = await response.readAsString();
      final games = jsonDecode(body)['games'];
      final allowed = id == 1 || id == 2;
      expect(games[0]['score_home'], allowed ? 3 : -1);
      expect(body.contains('左飛'), allowed);
      expect(games[1]['score_home'], 2);
      expect(response.headers['cache-control'], 'private, no-store');
    }
  });
}
