import 'package:test/test.dart';
import '../app/GameSeasonStats.dart';
import '../app/PostseasonForm.dart';

void main() {
  test('NPB公式表は規定未達と0本の選手も取り、別年や壊れた表を拒否する', () {
    const body = '<title>2026年度 個人打撃成績</title><table><thead><tr>'
      '<th>選手</th><th>打数</th><th>安打</th><th>本塁打</th><th>打率</th>'
      '</tr></thead><tbody><tr><td>新人 太郎</td><td>2</td><td>0</td><td>0</td><td>.000</td></tr>'
      '<tr><td>主力 選手</td><td>500</td><td>150</td><td>20</td><td>.300</td></tr></tbody></table>';
    final records = parseNpbGameSeasonStats(body, 'g', 2026, pitching: false);
    expect(records, hasLength(2));
    expect(records.first['values'], {'打率': '.000', '本塁打': '0'});
    expect(() => parseNpbGameSeasonStats(body, 'g', 2025, pitching: false), throwsFormatException);
    expect(() => parseNpbGameSeasonStats('<title>2026</title>', 'g', 2026, pitching: false), throwsFormatException);
  });

  test('MLBは当年の公式IDで取り、不明の値を0にしない', () {
    final records = parseMlbGameSeasonStats({'stats': [{
      'group': {'displayName': 'hitting'}, 'splits': [
        {'season': '2026','player': {'id': 1, 'fullName': 'A Smith'},'stat': {'avg': '.000','homeRuns': 0}},
        {'season': '2026','player': {'id': 2, 'fullName': 'B Smith'},'stat': {'avg': '.300'}},
        {'season': '2025','player': {'id': 3},'stat': {'avg': '.999','homeRuns': 100}},
      ]
    }]}, 2026, pitching: false);
    expect(records, hasLength(2));
    expect(records.last['values'], {'打率': '.300'});
    final stats = <Map<String,dynamic>>[];
    addOfficialGameSeasonStats(stats, [{
      'id_player': 10,'id_team': 1,'id_league': 3,'name_full_summary': '同姓選手', 'identity_sources': {'mlb': '2'},
    }], records);
    expect(stats.single['stats'], '.300');
  });

  test('移籍分は打数と安打で加重し、本塁打数を合算する', () {
    final stats = <Map<String,dynamic>>[];
    addOfficialGameSeasonStats(stats, [{
      'id_player': 10,'id_team': 1,'id_league': 1,'name_full_summary': '移籍 太郎',
    }], [
      {'org': 'npb','name': '移籍 太郎','group': 'hitting','values': {'打率': '.500','本塁打': '1'},'samples': {'打数': '2','安打': '1'}},
      {'org': 'npb','name': '移籍 太郎','group': 'hitting','values': {'打率': '.250','本塁打': '10'},'samples': {'打数': '100','安打': '25'}},
    ]);
    expect(stats.singleWhere((s) => s['title'] == '打率')['stats'], '0.255');
    expect(stats.singleWhere((s) => s['title'] == '本塁打')['stats'], 11);
  });

  test('年度別成績はランキング外選手の率・本塁打・勝利・H・Sを補完する', () {
    final stats = <Map<String,dynamic>>[];
    addCareerFormBaselines(stats, [{
      'id_player': 1,'int_batting': 10,'double_average_batting': .3,'int_homerun': 0,
      'int_pitching': 1,'double_inning': 2,'double_average_earned_runs': 0.0,
      'int_win': 0,'int_hold': 0,'int_save': 0,
    }], people: [{'id_player': 1,'id_team': 1,'name_full_summary': '新人 太郎'}]);
    expect(stats.map((s) => s['title']).toSet(), {'打率','本塁打','防御率','勝利','ホールド','セーブ'});
    expect(stats.every((s) => s['name_player'] == '新人 太郎'), isTrue);
  });
}
