import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/logic/favorite_team.dart';

void main() {
  tearDown(() {AuthSession.instance.user = null; AuthSession.instance.token = null;});
  void login() {
    AuthSession.instance.user = AuthUser.fromJson({'id': 1, 'id_team_fav': 7, 'name_team_fav': '福岡ソフトバンクホークス'});
    AuthSession.instance.token = 'test';
  }
  test('favorite ID wins and no matching option remains unselected', () {
    login();
    final rows = [{'id_team': 1, 'name_team': '巨人'}, {'id_team': 7, 'name_team': 'ソフトバンク'}];
    expect(favoriteTeamRow(rows), rows.last);
    expect(favoriteTeamRow([rows.first]), isNull);
  });
  test('historic names and video labels match the favorite franchise', () {
    login();
    expect(favoriteTeamOption(['巨人', '南海'], name: (s) => s), '南海');
    expect(favoriteTeamRow([{'id': 'channel', 'tab_label': 'ソフトバンク'}])?['id'], 'channel');
    expect(sameFavoriteTeamName('横浜DeNAベイスターズ', '大洋'), true);
    expect(sameFavoriteTeamName('サンフランシスコ・ジャイアンツ', '巨人'), false);
    expect(sameFavoriteTeamName('阪神タイガース', 'デトロイト・タイガース'), false);
    expect(sameFavoriteTeamName('ロサンゼルス・ドジャース', 'ドジャース'), true);
  });
  test('guest does not use a leftover user preference', () {
    login(); AuthSession.instance.token = null;
    expect(favoriteTeamOption(['ソフトバンク'], name: (s) => s), isNull);
  });
}
