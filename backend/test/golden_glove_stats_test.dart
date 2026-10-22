import 'package:test/test.dart';
import '../app/GoldenGloveStats.dart';
import '../app/SeasonAwards.dart';

void main() {
  test('打者GGランキングから投手を除外する', () {
    final people = <Map<String,dynamic>>[
      {'id':1,'name_full':'投手選手','id_league':1,'active_season':2026,'txt_position':'投手'},
      {'id':2,'name_full':'野手選手','id_league':1,'active_season':2026,'txt_position':'内野手'},
      {'id':3,'name_full':'登録不明','id_league':2,'active_season':2026},
    ];
    final awards = <int,List<Map<String,dynamic>>>{2025:[
      {'key':'glove','name':'投手選手','career_count':5,'detail':'投手'},
      {'key':'glove','name':'野手選手','career_count':3,'detail':'二塁手'},
      {'key':'glove','name':'登録不明','career_count':2,'detail':'投手'},
    ]};
    final rows = goldenGloveRows(2026,people,awards:awards);
    expect(rows,hasLength(1));
    expect(rows.single['id_player'],2);
    final pitchers = goldenGloveRows(2026,people,awards:awards,pitching:true);
    expect(pitchers.map((p)=>p['id_player']),[1,3]);
    expect(pitchers.every((p)=>p['flg_pitcher']==true),isTrue);
    expect(pitchers.every((p)=>p['txt_position']=='投手'),isTrue);
    expect(goldenGloveRows(2027,people,awards:awards,pitching:true),isEmpty);
  });

  test('official cumulative counts and identity are extracted', () {
    final rows = parseSeasonAwardPage(
        '''<div class="contents"><div class="player_unit"><a href="/bis/players/123.html"><h6>外野手</h6><span class="name">甲 選手</span><span class="team">阪神</span><div class="comment">3年連続5回目</div></a></div></div>''',
        'award/2025/glove.html',
        2025);
    expect(rows.single['career_count'], 5);
    expect(rows.single['source_player_id'], '123');
  });
  test('counts are as of selected year and follow players across clubs', () {
    final people = <Map<String, dynamic>>[
      {
        'id': 1,
        'name_full': '甲選手',
        'id_team': 2,
        'id_league': 2,
        'official_source_player_id': '123'
      }
    ];
    final awards = <int, List<Map<String, dynamic>>>{
      2023: [
        {
          'key': 'glove',
          'name': '旧登録名',
          'source_player_id': '123',
          'career_count': 5
        }
      ],
      2025: [
        {
          'key': 'glove',
          'name': '甲選手',
          'source_player_id': '123',
          'career_count': 6
        }
      ],
    };
    expect(goldenGloveRows(2022, people.map((p) => {...p, 'active_season':2022}).toList(), awards: awards), isEmpty);
    expect(
        goldenGloveRows(2024, people.map((p) => {...p, 'active_season':2024}).toList(), awards: awards).single['numeric_value'],
        5);
    final current = goldenGloveRows(2025, people.map((p) => {...p, 'active_season':2025}).toList(), awards: awards).single;
    expect(current['numeric_value'], 6);
    expect(current['id_league'], 2);
    expect(current['flg_pitcher'], false);
    expect(goldenGloveRows(2025, people, awards: awards), isEmpty);
    expect(goldenGloveRows(2025, people.map((p) => {...p, 'active_season':2024}).toList(), awards: awards), isEmpty);
    // Current retirement must not exclude a player from a season when active.
    expect(goldenGloveRows(2024, people.map((p) => {...p, 'active_season':2024, 'flg_retired':true}).toList(), awards: awards), hasLength(1));
  });
}
