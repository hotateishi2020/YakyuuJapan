import 'package:test/test.dart';

import '../app/PlayerDisplay.dart';

Map<String, dynamic> stat({
  int player = 10,
  int rank = 1,
  int league = 1,
  int title = 5,
  String name = '山田太郎',
}) =>
    {
      'id_player': player,
      'id_team': 100,
      'id_league': league,
      'id_stats': title,
      'int_rank': rank,
      'name_player': name,
      'player_name': name,
      'league_name': 'セ・リーグ',
      'title': '防御率',
      'int_index': 2,
      'flg_pitcher': true,
      'color_back': 'navy',
      'color_font': 'white',
      'id_users': '/99/',
      'colors_user': '/old/',
    };

Map<String, dynamic> prediction({
  int player = 10,
  int user = 1,
  int league = 1,
  int title = 5,
  String name = '山田 太郎',
  String color = 'blue',
}) =>
    {
      'id_user': user,
      'username': '予想者$user',
      'id_player': player,
      'id_team': 100,
      'id_league': league,
      'id_stats': title,
      'league_name': 'セ・リーグ',
      'title': '防御率',
      'player_name': name.replaceAll(' ', ''),
      'full_name': name,
      'int_index': 2,
      'flg_pitcher': true,
      'code_color': color,
      'color_today': color,
      'color_back': 'navy',
      'color_font': 'white',
    };

void main() {
  test('新しい登録データでも成績セルの規定到達率を維持する', () {
    final result = buildPlayerDisplay([
      {
        'id_league': 1, 'id_stats': 1, 'id_player': 42,
        'int_rank': 1001, 'name_player': '山田太郎(80.0%)',
        'prediction_name': '山田太郎', 'flg_pitcher': true,
        'league_name': 'セ',
      },
    ], []);
    expect(result.stats.single['name_player'], '山田太郎(80.0%)');
    expect(result.stats.single.containsKey('player_name'), isFalse);
    expect(result.stats.single.containsKey('prediction_name'), isFalse);
  });

  test('登録済みの首位から現在行を作り、予想的中と表示色を保持する', () {
    final result = buildPlayerDisplay([stat()], [prediction()]);
    expect(result.predictions.map((row) => row['id_user']), [0, 1]);
    final current = result.predictions.first;
    expect(current, containsPair('username', '現在'));
    expect(current, containsPair('player_name', '山田太郎'));
    expect(current, containsPair('color_back', 'navy'));
    expect(current, containsPair('flg_pitcher', true));
    expect(current, containsPair('flg_atari', false));
    expect(current, containsPair('color_today', ''));
    expect(result.predictions.last, containsPair('flg_atari', true));
    expect(result.predictions.last, containsPair('color_today', 'blue'));
  });

  test('同率首位の全員を表示してそれぞれの予想を的中にする', () {
    final result = buildPlayerDisplay(
      [stat(), stat(player: 20, name: '鈴木一郎'), stat()],
      [prediction(), prediction(player: 20, user: 2, name: '鈴木 一郎')],
    );
    final current = result.predictions.where((row) => row['id_user'] == 0);
    expect(current.map((row) => row['id_player']), [10, 20]);
    expect(
      result.predictions
          .where((row) => row['id_user'] != 0)
          .every((row) => row['flg_atari'] == true),
      isTrue,
    );
  });

  test('非首位選手を複数人が予想しても的中にしない', () {
    final result = buildPlayerDisplay(
      [stat(), stat(player: 20, rank: 2)],
      [prediction(player: 20), prediction(player: 20, user: 2)],
    );
    expect(
      result.predictions
          .where((row) => row['id_user'] != 0)
          .every((row) => row['flg_atari'] == false),
      isTrue,
    );
  });

  test('別リーグ・別種目の首位と同じ選手でも的中にしない', () {
    final result = buildPlayerDisplay(
      [stat()],
      [prediction(league: 2), prediction(title: 6, user: 2)],
    );
    expect(result.predictions.skip(1).map((row) => row['flg_atari']),
        [false, false]);
    expect(result.stats.single['id_users'], '');
  });

  test('ID付きスナップショットは氏名でなくIDを使う', () {
    final result = buildPlayerDisplay(
      [stat()],
      [prediction(name: '変更後の氏名'), prediction(player: 20, user: 2)],
    );
    expect(result.predictions.skip(1).map((row) => row['flg_atari']),
        [true, false]);
    expect(result.stats.single['id_users'], '/1/');
  });

  test('旧payloadは氏名を厳密照合し、同姓を誤って一致させない', () {
    final legacy = stat(name: '山田　太郎 (88.1%)')
      ..remove('id_player')
      ..remove('player_name')
      ..remove('flg_pitcher')
      ..remove('league_name');
    final result = buildPlayerDisplay(
      [legacy],
      [prediction(), prediction(player: 20, user: 2, name: '山田 次郎')],
    );
    expect(result.predictions.first['player_name'], '山田太郎');
    expect(result.predictions.first['flg_pitcher'], true);
    expect(result.predictions.first['league_name'], 'セ・リーグ');
    expect(result.predictions.skip(1).map((row) => row['flg_atari']),
        [true, false]);
    expect(result.stats.single['id_users'], '/1/');
  });

  test('予想を変更した時は保存済みの古いユーザーと色を更新する', () {
    final original = stat();
    final second = stat(player: 20, rank: 2);
    final pick = prediction(user: 2, color: 'red');
    final result = buildPlayerDisplay(
      [original, second],
      [pick, prediction(user: 3, color: 'blue'), pick],
    );
    expect(result.stats.first['id_users'], '/2/3/');
    expect(result.stats.first['colors_user'], '/blue/red/');
    expect(result.stats.last['id_users'], '');
    expect(result.stats.last['colors_user'], '');
    expect(original['id_users'], '/99/');
    expect(original['colors_user'], '/old/');
    expect(pick.containsKey('flg_atari'), isFalse);
    expect(identical(result.stats.first, original), isFalse);
    expect(identical(result.predictions.last, pick), isFalse);
  });

  test('空の成績は現在行を作らず予想のみを非的中で返す', () {
    final result = buildPlayerDisplay([], [prediction()]);
    expect(result.stats, isEmpty);
    expect(result.predictions, hasLength(1));
    expect(result.predictions.single['id_user'], 1);
    expect(result.predictions.single['flg_atari'], false);
    expect(buildPlayerDisplay([], []).predictions, isEmpty);
  });

  test('予想がなくても登録済みの首位と投打情報は表示する', () {
    final result = buildPlayerDisplay([stat()], []);
    expect(result.predictions, hasLength(1));
    expect(result.predictions.single['id_user'], 0);
    expect(result.predictions.single['flg_pitcher'], true);
    expect(result.stats.single['colors_user'], '');
  });
}
