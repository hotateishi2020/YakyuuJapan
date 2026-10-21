import 'package:test/test.dart';
import '../app/ChampionshipSummary.dart';
Map<String,dynamic> season(int year, {bool win = true, bool league = true, bool inter = false, String name = '前身球団'}) => {
  'year': year,
  'leagues': [{'teams': [{'id_team': 1, 'name': name, 'champion': win, 'league_champion': league, 'rank': 1}]}],
  if (inter) 'interleague_champion': {'id_team': 1, 'name': name},
};
void main() {
  test('公式リーグ優勝を勝利数順の順位より優先し近鉄をオリックスへ合算しない', () {
    final official = {'1986': {'central': '広島東洋カープ', 'pacific': '西武ライオンズ'},
      '2001': {'central': 'ヤクルトスワローズ', 'pacific': '大阪近鉄バファローズ'}};
    expect(championshipSummary([season(1986,name:'読売ジャイアンツ')],1986,
      officialLeagueWinners: official).single['league_count'],0);
    expect(championshipSummary([season(2001,name:'オリックス・バファローズ')],2001,
      officialLeagueWinners: official).single['league_count'],0);
  });

  test('交流戦優勝の旧表記と文字列エスケープを球団名と照合する', () {
    final row = season(2012, name: '読売ジャイアンツ');
    row['interleague_champion'] = {'name': r'読\u3000\u3000売ジャイアンツ'};
    expect(championshipSummary([row],2012).single['interleague_count'],1);
  });

  test('前身球団を合算し選択年度より後と一リーグ時代を除外する', () {
    final rows = [season(1949),season(1950),season(1951),season(1952, win:false,league:false),season(1953,name:'現球団'),season(1954)];
    final summary = championshipSummary(rows,1953).single;
    expect(summary['name'],'現球団');
    expect(summary['champion_count'],3);
    expect(summary['champion_streak'],2);
    expect(summary['league_count'],3);
    expect(summary['league_streak'],2);
    expect(summary['champion_years'],0);
  });
  test('重複年は一度だけ数え未取得年は連覇としてつながない', () {
    final result = championshipSummary([season(2000),season(2000),season(2002),season(2003)],2003).first;
    expect(result['champion_count'],3);
    expect(result['champion_streak'],2);
  });
  test('交流戦は2020年の中止を挟んで開催回の連覇を数える', () {
    final result = championshipSummary([season(2018,inter:true),season(2019,inter:true),season(2020,inter:true),season(2021,inter:true),season(2022,win:false,league:false)],2022).first;
    expect(result['interleague_count'],3);
    expect(result['interleague_streak'],3);
    expect(result['champion_count'],4);
    expect(result['league_years'],1);
  });
  test('明示的な未優勝を順位1位だけで上書きしない', () {
    final result = championshipSummary([season(2026,win:false,league:false)],2026).single;
    expect(result['league_count'],0);
    expect(result['league_years'],isNull);
    expect(result['champion_streak'],0);
  });
}
