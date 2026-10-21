import 'package:test/test.dart';
import '../app/CatcherCounts.dart';
import '../app/ExtendedPlayerMetrics.dart';
import '../app/QualifiedPitchingMetrics.dart';
import '../app/MlbSeasonPositions.dart';
import '../app/PlayerDetail.dart';
import '../app/PostseasonForm.dart';
import '../app/StatcastProfiles.dart';
import '../app/PinchMetrics.dart';
import '../app/RecentPlayerGames.dart';

void main() {
  test('旧投手キャッシュは再取得し失点ゼロの新データは保持する', () {
    final line = <String, dynamic>{'double_inning_pitch': '4.0', 'int_runs_earned': 0};
    final game = {'players': {'1': {'lines': [line]}}};
    expect(needsNpbPitchingRefresh(null), isTrue);
    expect(needsNpbPitchingRefresh(game), isTrue);
    line.addAll({'int_runs': 0, 'int_four': 0, 'int_dead_pitching': 0, 'starter': false});
    expect(needsNpbPitchingRefresh(game), isFalse);
  });
  test('補完スタッツに別スタッツの予想色を引き継がない', () {
    final rows = <Map<String, dynamic>>[{'id_player': 1, 'title': '本塁打', 'colors_user': '/red/', 'id_users': '/1/'}];
    addMissingRequestedMetrics(rows);
    final pinch = rows.firstWhere((r) => r['title'] == '代打起用数');
    expect(pinch['colors_user'], isNull);
    expect(pinch['id_users'], isNull);
  });

  test('捕手の盗塁阻止数は守備記録の当年一軍Cだけから取得する', () {
    String row(int year,String league,String position,String count,String rate) {
      final cells=List.filled(26,'0');
      cells[0]='$year';cells[2]='T';cells[3]=league;cells[4]=position;cells[21]=count;cells[22]=rate;
      return '<tr>${cells.map((v)=>'<td>$v</td>').join()}</tr>';
    }
    expect(parseCatcherCount('<table>${row(2026,'１軍','C','19','.328')}${row(2025,'１軍','C','90','.9')}${row(2026,'２軍','C','99','.9')}</table>',2026),19);
    expect(parseCatcherCount('<table>${row(2026,'１軍','C','0','.000')}</table>',2026),0);
    expect(parseCatcherCount('<table>${row(2026,'１軍','C','-','-')}</table>',2026),isNull);
  });

  test('盗塁阻止数は規定未達・打席不明・ゼロ件の捕手も表示する', () {
    for(final games in [143,162,70]) {
      final minimum = (games * 3.1).round();
      final rows = <Map<String,dynamic>>[
        for(var id=1;id<=4;id++) ...[
          {'id_player':id,'id_team':1,'title':'打席数','numeric_value':id==1 ? minimum-1 : minimum},
          {'id_player':id,'id_team':1,'title':'盗塁阻止数','numeric_value':14,'txt_position':id==3 ? '外野手' : id==4 ? null : '捕手'},
        ],
        {'id_player':5,'id_team':1,'title':'盗塁阻止数','catcher_metric':true,'numeric_value':0},
      ];
      retainCatcherCounts(rows);
      expect(rows.where((r)=>r['title']=='盗塁阻止数').map((r)=>r['id_player']),[1,2,5]);
      addMissingRequestedMetrics(rows);
      expect(rows.where((r)=>r['title']=='盗塁阻止数'),hasLength(3));
    }
  });

  test('NPBとMLBの四球系率は規定到達投手だけを残す', () {
    for (final limit in [143, 162, 70]) {
      final rows = <Map<String, dynamic>>[
        for (final p in [
          (1, limit * 3 - 1),
          (2, limit * 3),
          (3, limit * 3 + 1)
        ]) ...[
          {
            'id_player': p.$1,
            'id_team': 1,
            'title': '投球回数',
            'numeric_value': p.$2 / 3
          },
          {
            'id_player': p.$1,
            'id_team': 1,
            'title': 'BB/9',
            'numeric_value': 1.0
          },
          {
            'id_player': p.$1,
            'id_team': 1,
            'title': '四死球/9',
            'numeric_value': 2.0
          },
          {
            'id_player': p.$1,
            'id_team': 1,
            'title': '登板回数',
            'numeric_value': 30
          },
        ],
        {'id_player': 4, 'id_team': 2, 'title': 'BB/9', 'numeric_value': 0.0},
      ];
      retainQualifiedPitchingRates(rows, {1: limit});
      expect(rows.where((r) => r['title'] == 'BB/9').map((r) => r['id_player']),
          [2, 3]);
      expect(rows.where((r) => r['title'] == '四死球/9'), hasLength(2));
      expect(rows.where((r) => r['title'] == '登板回数'), hasLength(3));
      addMissingRequestedMetrics(rows);
      expect(rows.where((r) => r['title'] == 'BB/9'), hasLength(2));
    }
  });

  test('未取得の追加指標に予想ユーザーを引き継がない', () {
    final rows = <Map<String, dynamic>>[
      {
        'id_player': 1,
        'title': '打率',
        'stats': '.300',
        'id_users': '7',
        'colors': 'red'
      }
    ];
    addMissingRequestedMetrics(rows);
    expect(rows.where((r) => r['title'] == '盗塁阻止数'), isEmpty);
    for (final title in ['ボール球見極め率', '代打打率']) {
      final row = rows.singleWhere((r) => r['title'] == title);
      expect(row['id_users'], isNull);
      expect(row['colors'], isNull);
      expect(row['stats'], '—');
    }
  });
  test('今年の最多守備位置を選びゼロ出場は採用しない', () {
    final positions = seasonPositionLeaders([
      for (final p in [('SS', 10), ('2B', 50), ('1B', 0)])
        {
          'player': {'id': 1},
          'position': {'abbreviation': p.$1},
          'stat': {'games': p.$2}
        }
    ]);
    expect(positions['1']?['position'], '2B');
  });
  test('代打の打点表示を除き、犠飛と敬遠を打数に含めない', () {
    expect(classifyPinchResult('左前安②'), {'ab': 1, 'hit': 1});
    expect(classifyPinchResult('右中本③'), {'ab': 1, 'hit': 1});
    expect(classifyPinchResult('中犠飛①'), {'ab': 0, 'hit': 0});
    expect(classifyPinchResult('敬遠四'), {'ab': 0, 'hit': 0});
    expect(classifyPinchResult('三ゴ失'), {'ab': 1, 'hit': 0});
    expect(classifyPinchResult('未知')['ab'], isNull);
  });
  test('公式試合ログは投打両方の記録を保持する', () {
    final row = parseNpbRecentGame(
        '<p class="game_info">試合終了</p><div id="table_top_b"><table><thead><tr><th class="inn">1</th></tr></thead><tbody><tr><td>9</td><td>投</td><td><a href="/bis/players/1.html">甲</a></td><td>1</td><td>0</td><td>1</td><td>0</td><td>0</td><td>中前安</td></tr></tbody></table></div><div id="table_top_p"><table><tbody><tr><td></td><td><a href="/bis/players/1.html">甲</a></td><td>10</td><td>3</td><td>0.2</td><td>0</td><td>0</td><td>0</td><td>0</td><td>1</td><td>0</td><td>0</td><td>0</td><td>0</td></tr></tbody></table></div>',
        'https://npb.jp/scores/2026/0327/g-t-01/box.html');
    expect(row!['players']['1']['lines'], hasLength(2));
    expect(row['players']['1']['plays'].single['result'], '中前安');
    final pitcher = row['players']['1']['lines'].last;
    expect(pitcher['starter'], true);
    expect(pitcher['int_runs'], 0);
    expect(pitcher['int_four'], 0);
    expect(pitcher['int_dead_pitching'], 0);
    expect(row['players']['1']['opponent'], row['home']);
  });

  test('同名選手を推測で選ばずID照合を優先', () {
    final people = [
      {'id': 1, 'name_full': '同名', 'id_team': 1},
      {'id': 2, 'name_full': '同名', 'id_team': 2}
    ];
    expect(matchPlayer({'name': '同名'}, people), isNull);
    expect(matchPlayer({'name': '同名', 'id_team': 2}, people)?['id'], 2);
    expect(matchPlayer({'id_player': 1, 'name': '別名'}, people)?['id'], 1);
  });
  test('Yahoo IDをMLB公式IDと混同しない', () {
    expect(
        officialPlayerId(
            {'url': 'https://baseball.yahoo.co.jp/mlb/player/2100825/'}),
        isNull);
    expect(officialPlayerId({'official_source_player_id': 660271}), '660271');
  });
  test('投球回端数をアウトで計算しBBと四死球を区別', () {
    final values = [
      '選手',
      '2',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      '10',
      '1.2',
      '1',
      '0',
      '1',
      '0',
      '1',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0'
    ];
    final rows = parseExtendedNpb(
        '<table><tr>${values.map((v) => '<td>$v</td>').join()}</tr></table>',
        kind: 'pitch',
        url: 'https://npb.jp/');
    final m = {for (final r in rows.single['metrics']) r['title']: r};
    expect(m['BB/9']['numeric_value'], closeTo(5.4, .0001));
    expect(m['四死球/9']['numeric_value'], closeTo(10.8, .0001));
    expect(m['平均投球回']['numeric_value'], closeTo(5 / 6, .0001));
    expect(m['投球回数']['stats'], '1 2/3');
  });
  test('記録ゼロは保留、少標本も参考判定、防御率は低い方を好調にする', () {
    expect(
        comparePostseasonForm(
            season: .3, recent: .5, sample: 0, pitcher: false)['level'],
        isNull);
    expect(
        comparePostseasonForm(
            season: .3, recent: .42, sample: 20, pitcher: false)['level'],
        2);
    expect(
        comparePostseasonForm(
            season: 3, recent: 1, sample: 18, pitcher: true)['level'],
        2);
    expect(
        comparePostseasonForm(
            season: 2, recent: 5, sample: 18, pitcher: true)['level'],
        -2);
  });
  test('同じ球団・公式URLの別名IDにも今季成績を結び付ける', () {
    final stats = <Map<String, dynamic>>[];
    addCareerFormBaselines(stats, [
      {
        'id_player': 10,
        'identity_url': 'https://baseball.yahoo.co.jp/mlb/player/123/',
        'identity_team': 40,
        'double_inning': 63.2,
        'double_average_earned_runs': 2.69
      },
    ], people: [
      {
        'id_player': 20,
        'id_team': 40,
        'url': 'https://baseball.yahoo.co.jp/mlb/player/123/'
      },
      {
        'id_player': 30,
        'id_team': 40,
        'url': 'https://baseball.yahoo.co.jp/mlb/player/999/'
      },
      {
        'id_player': 40,
        'id_team': 41,
        'url': 'https://baseball.yahoo.co.jp/mlb/player/123/'
      },
    ]);
    expect(stats.map((s) => s['id_player']), [10, 20]);
    expect(stats.last['stats'], 2.69);
  });
  test('ランキング外の救援投手と野手もシーズン成績を比較に使う', () {
    final stats = <Map<String, dynamic>>[];
    addCareerFormBaselines(stats, [
      {
        'id_player': 1,
        'double_inning': 12.1,
        'double_average_earned_runs': 0.0
      },
      {'id_player': 2, 'int_batting': 20, 'double_average_batting': .2},
      {'id_player': 3, 'double_inning': 0, 'double_average_earned_runs': 0.0},
    ]);
    expect(stats.length, 2);
    expect(stats.first['stats'], 0.0);
    expect(stats.last['title'], '打率');
    addCareerFormBaselines(stats, [
      {'id_player': 1, 'double_inning': 12, 'double_average_earned_runs': 5.0}
    ]);
    expect(stats.length, 2);
    expect(stats.first['stats'], 0.0);
  });
  test('絵文字付き開始時刻でもPSの打撃・救援投手を比較する', () {
    for (final time in ['☀️ 14:00', '🌙 18:00', '18:00']) {
      final game = <String, dynamic>{
        'date_game': '2026-10-16',
        'time_game': time,
        'code_game': 'NLCS',
        'id_team_home': 1,
        'id_team_away': 2
      };
      attachFormsFromRecords([
        game
      ], [
        {
          'id_player': 1,
          'name_full': '打者',
          'current_team': 1,
          'start': '2026-10-15 18:00:00',
          'code_game': 'NLDS',
          'int_batting': 4,
          'int_hit1': 0,
          'int_hit2': 1,
          'int_homerun': 1
        },
        {
          'id_player': 2,
          'name_full': '救援',
          'current_team': 2,
          'start': '2026-10-15 18:00:00',
          'code_game': 'NLDS',
          'double_inning_pitch': '0.1',
          'int_runs_earned': 0
        },
        {
          'id_player': 1,
          'name_full': '打者',
          'current_team': 1,
          'start': '2026-10-17 18:00:00',
          'code_game': 'NLCS',
          'int_batting': 20,
          'int_hit1': 0
        },
      ], [
        {'id_player': 1, 'title': '打率', 'stats': '.250'},
        {'id_player': 2, 'title': '防御率', 'stats': '3.00'},
      ]);
      final forms = game['postseason_form'] as List;
      final batter = forms
          .singleWhere((r) => r['id_player'] == 1 && r['pitcher'] == false);
      final pitcher =
          forms.singleWhere((r) => r['id_player'] == 2 && r['pitcher'] == true);
      expect(batter['postseason'], .5);
      expect(batter['level'], 2);
      expect(pitcher['level'], 2);
      expect(pitcher['small_sample'], true);
      expect(batter['sample'], 4);
    }
  });
  test('Statcast CSVの引用符・BOM・空欄を保持', () {
    final rows = parseStatcastCsv(
        '\uFEFF"last_name, first_name",player_id,value\r\n"O""Neil, Test",123,\r\n');
    expect(rows.single['last_name, first_name'], 'O"Neil, Test');
    expect(rows.single['value'], '');
  });
}
