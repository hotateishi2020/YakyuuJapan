import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../app/HistoricalBaseballImporter.dart';
import '../tool_history_backfill.dart';

void main() {
  test('baseball innings preserve thirds', () {
    expect(HistoricalBaseballImporter.baseballInnings('162.1'),
        closeTo(162 + 1 / 3, 0.0001));
    expect(HistoricalBaseballImporter.baseballInnings('7.2'),
        closeTo(7 + 2 / 3, 0.0001));
  });

  test('MLB qualification separates rate and counting stats', () {
    final line = <String, dynamic>{
      'plateAppearances': 501,
      'inningsPitched': '161.2',
      'stolenBases': 15,
      'caughtStealing': 2,
    };
    expect(
        HistoricalBaseballImporter.qualifiesForMlbRate(1, line, 162), isFalse);
    expect(
        HistoricalBaseballImporter.qualifiesForMlbRate(3, line, 162), isTrue);
    expect(
        HistoricalBaseballImporter.qualifiesForMlbRate(9, line, 162), isFalse);
    expect(
        HistoricalBaseballImporter.qualifiesForMlbRate(22, line, 162), isTrue);
  });

  test('NPB aliases resolve only through explicit unambiguous mapping', () {
    const teams = [
      '読売ジャイアンツ',
      '阪神タイガース',
      '横浜DeNAベイスターズ',
    ];
    expect(
      HistoricalBaseballImporter.resolveNpbTeamAlias('巨 人', teams),
      '読売ジャイアンツ',
    );
    expect(
      HistoricalBaseballImporter.resolveNpbTeamAlias('DeNA', teams),
      '横浜DeNAベイスターズ',
    );
    expect(
        HistoricalBaseballImporter.resolveNpbTeamAlias('横浜っぽい', teams), isNull);
    expect(
      HistoricalBaseballImporter.resolveNpbTeamAlias(
        '阪神',
        const ['大阪タイガース', '読売ジャイアンツ'],
      ),
      '大阪タイガース',
    );
    expect(
      HistoricalBaseballImporter.resolveNpbTeamAlias(
        '巨人',
        const ['東京巨人', '大阪タイガース'],
      ),
      '東京巨人',
    );
  });

  test('NPB franchise keys reuse current clubs and keep defunct clubs distinct',
      () {
    expect(HistoricalBaseballImporter.npbTeamSourceKey('東京巨人'),
        'npb:franchise:giants');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('読売ジャイアンツ'),
        'npb:franchise:giants');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('大阪タイガース'),
        'npb:franchise:tigers');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('阪急'),
        'npb:franchise:buffaloes');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('東京セネタース'),
        'npb:team:東京セネタース');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('名古屋金鯱'),
        'npb:team:名古屋金鯱');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('大東京'),
        'npb:franchise:robins');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('松竹ロビンス'),
        'npb:franchise:robins');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('広島東洋'),
        'npb:franchise:carp');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('阪　急'),
        'npb:franchise:buffaloes');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('福岡ダイエー'),
        'npb:franchise:hawks');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('大阪近鉄バファローズ'),
        'npb:franchise:kintetsu');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('大　毎'),
        'npb:franchise:marines');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('東　映'),
        'npb:franchise:fighters');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('大阪近鉄'),
        'npb:franchise:kintetsu');
    expect(HistoricalBaseballImporter.npbTeamSourceKey('阪急ブレーブス'),
        isNot(HistoricalBaseballImporter.npbTeamSourceKey('近鉄バファローズ')));
  });

  test('NPB official yearly tables are parsed conservatively', () {
    const source = '''
      <table>
        <tr><th colspan="8">■ チーム勝敗表</th></tr>
        <tr><th>チーム</th><th>試 合</th><th>勝 利</th><th>敗 北</th>
          <th>引 分</th><th>勝 率</th><th></th><th>ゲーム差</th></tr>
        <tr><td>読売ジャイアンツ</td><td>143</td><td>77</td><td>59</td>
          <td>7</td><td>.566</td><td>-</td><td>-</td></tr>
      </table>
      <table>
        <tr><th>順 位</th><th>選 手</th><th>打 率</th><th>試 合</th>
          <th>打 数</th><th>得 点</th><th>安 打</th><th>二 塁 打</th>
          <th>三 塁 打</th><th>本 塁 打</th><th>打 点</th><th>盗 塁</th></tr>
        <tr><td>1</td><td>オースティン (DeNA)</td><td>.316</td><td>106</td>
          <td>396</td><td>66</td><td>125</td><td>34</td><td>2</td>
          <td>25</td><td>69</td><td>0</td></tr>
      </table>
    ''';
    final page = HistoricalBaseballImporter.parseNpbYearPage(
      source,
      year: 2024,
      leagueId: 1,
    );
    expect(page.standings, hasLength(1));
    expect(page.standings.single.teamName, '読売ジャイアンツ');
    expect(page.hitting, hasLength(1));
    expect(page.hitting.single.playerName, 'オースティン');
    expect(page.hitting.single.values['hits'], 125);
  });

  test('NPB wrapper and team-pitching tables are not league standings', () {
    const source = '''
      <table>
        <tr><th>チーム</th><th>試合</th><th>勝利</th><th>敗北</th>
          <th>引分</th><th>勝率</th><th>ゲーム差</th><th>チーム</th></tr>
        <tr><td>
          <table>
            <tr><th>チーム</th><th>試 合</th><th>勝 利</th><th>敗 北</th>
              <th>引 分</th><th>勝 率</th><th></th><th>ゲーム差</th></tr>
            <tr><td>読売ジャイアンツ</td><td>143</td><td>77</td><td>59</td>
              <td>7</td><td>.566</td><td>-</td><td>-</td></tr>
          </table>
        </td></tr>
      </table>
      <table>
        <tr><th>チーム</th><th>防御率</th><th>試合</th><th>勝利</th><th>敗北</th></tr>
        <tr><td>読売ジャイアンツ</td><td>3.10</td><td>143</td><td>77</td><td>59</td></tr>
      </table>
    ''';
    final page = HistoricalBaseballImporter.parseNpbYearPage(
      source,
      year: 1950,
      leagueId: 1,
    );
    expect(page.standings, hasLength(1));
    expect(page.standings.single.teamName, '読売ジャイアンツ');
    expect(page.standings.single.wins, 77);
    expect(page.standings.single.draws, 7);
  });

  test('NPB yearly player tables accept split name and team cells', () {
    const source = '''
      <table>
        <tr><th>順位</th><th>選手</th><th></th><th>打率</th><th>試合</th>
          <th>打数</th><th>得点</th><th>安打</th><th>二塁打</th><th>三塁打</th>
          <th>本塁打</th><th>打点</th><th>盗塁</th></tr>
        <tr><td>1</td><td>中根 之</td><td>(名古屋)</td><td>.376</td>
          <td>25</td><td>93</td><td>20</td><td>35</td><td>2</td><td>3</td>
          <td>0</td><td>7</td><td>7</td></tr>
      </table>
    ''';
    final page = HistoricalBaseballImporter.parseNpbYearPage(
      source,
      year: 1936,
      leagueId: 1,
    );
    expect(page.hitting, hasLength(1));
    expect(page.hitting.single.playerName, '中根 之');
    expect(page.hitting.single.teamAlias, '名古屋');
    expect(page.hitting.single.values['hits'], 35);
    expect(
      HistoricalBaseballImporter.resolveNpbTeamAlias(
        '名古屋',
        const ['名古屋', '名古屋金鯱', '東京巨人'],
      ),
      '名古屋',
    );
  });

  test('NPB source routing includes both split-season phases', () {
    final split = HistoricalBaseballImporter.npbSourcesForYear(1936);
    expect(split, hasLength(2));
    expect(split.map((source) => source.phase), ['spring', 'fall']);
    expect(split.every((source) => source.leagueId == 1), isTrue);
    expect(
      HistoricalBaseballImporter.npbSourcesForYear(1949).single.uri,
      endsWith('yakyuremmei_1949.html'),
    );
    expect(HistoricalBaseballImporter.npbSourcesForYear(1945), isEmpty);
    expect(HistoricalBaseballImporter.npbSourcesForYear(1950), hasLength(2));
  });

  test('split NPB pages combine standings and player totals', () {
    final spring = NpbYearPage(1936, 1, phase: 'spring')
      ..standings.add(const NpbStanding(
        teamName: '東京巨人軍',
        games: 10,
        wins: 7,
        losses: 3,
        draws: 0,
        gamesBack: '-',
      ))
      ..hitting.add(const NpbPlayerRow(
        '選手 一',
        '東京巨人軍',
        {'atBats': 20, 'hits': 6, 'homeRuns': 1},
        phase: 'spring',
      ));
    final fall = NpbYearPage(1936, 1, phase: 'fall')
      ..standings.add(const NpbStanding(
        teamName: '東京巨人軍',
        games: 12,
        wins: 8,
        losses: 4,
        draws: 0,
        gamesBack: '-',
      ))
      ..hitting.add(const NpbPlayerRow(
        '選手 一',
        '東京巨人軍',
        {'atBats': 30, 'hits': 12, 'homeRuns': 2},
        phase: 'fall',
      ));
    final combined = HistoricalBaseballImporter.combineNpbPages([spring, fall]);
    expect(combined.standings.single.games, 22);
    expect(combined.standings.single.wins, 15);
    expect(combined.hitting.single.values['hits'], 18);
    expect(combined.hitting.single.values['homeRuns'], 3);
    expect(combined.hitting.single.values['avg'], closeTo(.36, .0001));
  });

  test('split tournament matrices aggregate wins losses and draws', () {
    const source = '''
      <title>1936年 春</title>
      <table>
        <tr><th>大会</th></tr><tr><th>チーム</th></tr>
        <tr><td>東京巨人</td></tr><tr><td>大阪タイガース</td></tr>
      </table>
      <table>
        <tr><th>勝</th><th>-</th><th>敗</th></tr>
        <tr><td>3</td><td>(1)</td><td>2</td></tr>
        <tr><td>2</td><td>-</td><td>3</td></tr>
      </table>
      <table>
        <tr><th>勝</th><th>-</th><th>敗</th></tr>
        <tr><td>1</td><td>-</td><td>1</td></tr>
        <tr><td>4</td><td>-</td><td>0</td></tr>
      </table>
    ''';
    final page = HistoricalBaseballImporter.parseNpbYearPage(
      source,
      year: 1936,
      leagueId: 1,
      phase: 'spring',
    );
    final giants = page.standings.singleWhere((row) => row.teamName == '東京巨人');
    expect(giants.wins, 4);
    expect(giants.losses, 3);
    expect(giants.draws, 1);
    expect(giants.games, 8);
  });

  test('real-style nested 1936 matrices aggregate every competition', () {
    const source = '''
      <html><head><title>1936年 春</title></head><body>
        <div class="contentsPadding"><table>
          <tr><td><table>
            <tr><td class="matchHdTeam">チーム</td></tr>
            <tr><td class="matchTeam">東京巨人</td></tr>
            <tr><td class="matchTeam">大阪タイガース</td></tr>
          </table></td>
          <td><table>
            <tr><td class="matchHdWin">勝</td><td class="matchHdTai">-</td>
              <td class="matchHdLose">敗</td></tr>
            <tr><td class="matchStats">3</td><td class="matchStats">(1)</td>
              <td class="matchStats">2</td></tr>
            <tr><td class="matchTop">2</td><td class="matchTop">-</td>
              <td class="matchTop">3</td></tr>
          </table></td>
          <td><table>
            <tr><td class="matchHdWin">勝</td><td class="matchHdTai">-</td>
              <td class="matchHdLose">敗</td></tr>
            <tr><td class="matchStats">1</td><td class="matchStats">-</td>
              <td class="matchStats">1</td></tr>
            <tr><td class="matchStats">4</td><td class="matchStats">-</td>
              <td class="matchStats">0</td></tr>
          </table></td></tr>
        </table></div>
        <div class="contentsPadding"><table>
          <tr><td><table>
            <tr><td class="matchHdTeam">チーム</td></tr>
            <tr><td class="matchTeam">東京巨人</td></tr>
            <tr><td class="matchTeam">大阪タイガース</td></tr>
          </table></td>
          <td><table>
            <tr><td class="matchHdWin">勝</td><td class="matchHdTai">-</td>
              <td class="matchHdLose">敗</td></tr>
            <tr><td class="matchTop">2</td><td class="matchTop">-</td>
              <td class="matchTop">1</td></tr>
            <tr><td class="matchStats">1</td><td class="matchStats">(1)</td>
              <td class="matchStats">2</td></tr>
          </table></td></tr>
        </table></div>
      </body></html>
    ''';
    final page = HistoricalBaseballImporter.parseNpbYearPage(
      source,
      year: 1936,
      leagueId: 1,
      phase: 'spring',
    );
    expect(page.hitting, isEmpty);
    expect(page.pitching, isEmpty);
    final giants = page.standings.singleWhere((row) => row.teamName == '東京巨人');
    final tigers =
        page.standings.singleWhere((row) => row.teamName == '大阪タイガース');
    expect(
      [giants.wins, giants.losses, giants.draws, giants.games],
      [6, 4, 1, 11],
    );
    expect(
      [tigers.wins, tigers.losses, tigers.draws, tigers.games],
      [7, 5, 1, 13],
    );
  });

  test('numeric batting cells are not treated as standings teams', () {
    const source = '''
      <table>
        <tr><th>順位</th><th>選手</th><th>打率</th><th>試合</th>
          <th>打数</th><th>得点</th><th>安打</th></tr>
        <tr><td>1</td><td>中根 之 (名古屋)</td><td>.376</td>
          <td>25</td><td>93</td><td>20</td><td>35</td></tr>
      </table>
      <table>
        <tr><th>チーム</th><th>防御率</th><th>試合</th><th>勝利</th><th>敗北</th></tr>
        <tr><td>9</td><td>1.40</td><td>147</td><td>0</td><td>0</td></tr>
        <tr><td>東京巨人</td><td>1.40</td><td>27</td><td>18</td><td>9</td></tr>
      </table>
    ''';
    final page = HistoricalBaseballImporter.parseNpbYearPage(
      source,
      year: 1936,
      leagueId: 1,
    );
    expect(page.standings, isEmpty);
  });

  test('detailed NPB ranking parser keeps official rank rows', () {
    const source = '''
      <html><head><title>2024年度 打率</title></head><body><table>
        <tr><td class="stpos">1</td><td class="stplayer">選手 一</td>
          <td class="stteam">（巨）</td><td class="ststats">.321</td></tr>
        <tr><td class="stpos">2</td><td class="stplayer">選手 二</td>
          <td class="stteam">（神）</td><td class="ststats">.310</td></tr>
      </table></body></html>
    ''';
    final rows = HistoricalBaseballImporter.parseNpbDetailedRanking(
      source,
      expectedYear: 2024,
      statId: 1,
    );
    expect(rows, hasLength(2));
    expect(rows.last.rank, 2);
    expect(rows.first.teamAlias, '巨');
    expect(rows.first.value, closeTo(.321, .0001));
  });

  test('2025 NPB ranking tablefix2 rows parse player and team', () {
    const source = '''
      <html><head><title>2025年度 打率</title></head><body>
        <table class="tablefix2">
          <tr class="ststats">
            <td>1</td><td>小園　海斗(広)</td><td>.309</td>
          </tr>
          <tr class="ststats">
            <td>2</td><td>泉口　友汰(巨)</td><td>.301</td>
          </tr>
        </table>
      </body></html>
    ''';
    final rows = HistoricalBaseballImporter.parseNpbDetailedRanking(
      source,
      expectedYear: 2025,
      statId: 1,
    );
    expect(rows, hasLength(2));
    expect(rows.first.playerName, '小園　海斗');
    expect(rows.first.teamAlias, '広');
    expect(rows.first.value, closeTo(.309, .0001));
    expect(rows.last.teamAlias, '巨');
  });

  test('HTTP retries 429 and then succeeds', () async {
    var calls = 0;
    final importer = HistoricalBaseballImporter(
      maxHttpAttempts: 3,
      retryBaseDelay: Duration.zero,
      httpGet: (uri) async {
        calls++;
        return calls < 3
            ? http.Response('busy', 429)
            : http.Response('ok', 200);
      },
    );
    final response =
        await importer.fetchOfficial(Uri.parse('https://example.test/data'));
    expect(response.statusCode, 200);
    expect(calls, 3);
  });

  test('ranking writes prepare one bulk payload instead of row-stat calls', () {
    final candidates = List.generate(1000, (index) {
      final line = SeasonLine(
        playerId: index + 1,
        teamId: 10,
        leagueId: 3,
        name: 'Player $index',
        teamName: 'Team',
        values: const {},
      );
      return RankValue(line, (1000 - index).toDouble(), 500);
    });
    final payload = HistoricalBaseballImporter.prepareRankingRows(
      candidates,
      lowerIsBetter: false,
    );
    expect(payload, hasLength(1000));
    expect(payload.first['rank'], 1);
    expect(payload.last['rank'], 1000);
    // The production writer passes this entire payload to one
    // jsonb_to_recordset INSERT for the statistic.
    expect(payload.every((row) => row.keys.length == 5), isTrue);
  });

  test('large career writes split into deterministic bounded chunks', () {
    final chunks = HistoricalBaseballImporter.chunksOf(
      List.generate(1001, (index) => index),
      HistoricalBaseballImporter.writeChunkSize,
    );
    expect(chunks.map((chunk) => chunk.length), [300, 300, 300, 101]);
    expect(chunks.expand((chunk) => chunk),
        orderedEquals(List.generate(1001, (i) => i)));
  });

  test('closed PostgreSQL connections are classified for safe retry', () {
    expect(
      HistoricalBaseballImporter.isBrokenConnectionError(StateError(
          'Attempting to execute query, but connection is not open')),
      isTrue,
    );
    expect(
      HistoricalBaseballImporter.isBrokenConnectionError(
          StateError('duplicate key')),
      isFalse,
    );
    expect(
      HistoricalBaseballImporter.isBrokenConnectionError(StateError(
          'SocketException: Connection timed out, host: db.example, port: 5432')),
      isTrue,
    );
  });

  test('season sentinel rejects mismatched NPB source', () {
    expect(
      () => HistoricalBaseballImporter.validateNpbSeason(
          '<title>2023年度</title>', 2024),
      throwsStateError,
    );
  });

  test('MLB division names map to historical area codes', () {
    expect(HistoricalBaseballImporter.mlbDivisionCode('American League East'),
        'EAST');
    expect(HistoricalBaseballImporter.mlbDivisionCode('NL Central'), 'CENTER');
    expect(HistoricalBaseballImporter.mlbDivisionCode('National League West'),
        'WEST');
  });

  test('MLB postseason schedule maps official game types and state', () {
    final games = HistoricalBaseballImporter.parseMlbPostseasonSchedule({
      'dates': [
        {
          'games': [
            {
              'season': '2024',
              'gamePk': 775300,
              'gameType': 'D',
              'gameDate': '2024-10-05T20:08:00Z',
              'status': {
                'abstractGameState': 'Final',
                'detailedState': 'Final'
              },
              'teams': {
                'home': {
                  'team': {'id': 147},
                  'score': 7
                },
                'away': {
                  'team': {'id': 121},
                  'score': 2
                }
              }
            }
          ]
        }
      ]
    }, expectedYear: 2024);
    expect(games, hasLength(1));
    expect(games.single.externalId, '775300');
    expect(games.single.codeGame, 'DS');
    expect(games.single.state, '試合終了');
    expect(games.single.homeTeamKey, '147');
  });

  test('NPB Japan Series line score uses visitor then home rows', () {
    const source = '''
      <title>2024年度 日本シリーズ</title>
      <div class="scoreMainList">
        <div class="scoreNumber">【第1戦】</div>
        <div class="scoreDate">10月26日（土）</div>
        <div class="scoreInfomation">横浜 ◇開始 18:33</div>
        <table>
          <tr><td class="scoreTeam">福岡ソフトバンク</td>
            <td class="scoreTotal">5</td></tr>
          <tr><td class="scoreTeam">横浜DeNA</td>
            <td class="scoreTotal">3</td></tr>
        </table>
      </div>
    ''';
    final games = HistoricalBaseballImporter.parseNpbJapanSeries(
      source,
      expectedYear: 2024,
      sourceUrl: HistoricalBaseballImporter.npbJapanSeriesUrl(2024),
    );
    expect(games, hasLength(1));
    expect(games.single.codeGame, 'JS');
    expect(games.single.awayTeamKey, '福岡ソフトバンク');
    expect(games.single.homeTeamKey, '横浜DeNA');
    expect(games.single.scoreHome, 3);
    expect(games.single.start.hour, 18);
  });

  test('historical NPB Japan Series ignores nested wrapper rows', () {
    const source = '''
      <title>1950年度日本シリーズ　試合結果</title>
      <table><tr><td class="scoreMainList">
        <div class="scoreNumber">【第1戦】</div>
        <div class="scoreDate">11月22日（水）</div>
        <div class="scoreInfomation">神　宮　◇開始 13:16</div>
        <table><tr><td class="scoreResult"><table>
          <tr><td class="scoreTeam">毎　日</td>
            <td class="scoreIning">0</td><td class="scoreTotal">3</td></tr>
          <tr><td class="scoreTeam">松　竹</td>
            <td class="scoreIning">0</td><td class="scoreTotal">2</td></tr>
        </table></td></tr></table>
      </td></tr></table>
    ''';
    final games = HistoricalBaseballImporter.parseNpbJapanSeries(
      source,
      expectedYear: 1950,
      sourceUrl: HistoricalBaseballImporter.npbJapanSeriesUrl(1950),
    );
    expect(games, hasLength(1));
    expect(games.single.awayTeamKey, '毎　日');
    expect(games.single.homeTeamKey, '松　竹');
    expect(games.single.scoreAway, 3);
    expect(games.single.scoreHome, 2);
    expect(
      HistoricalBaseballImporter.npbTeamSourceKey('毎　日'),
      'npb:franchise:marines',
    );
    expect(
      HistoricalBaseballImporter.npbTeamSourceKey('松　竹'),
      'npb:franchise:robins',
    );
  });

  test('Japan Series short labels resolve through franchise keys', () {
    const byKey = {
      'npb:franchise:carp': 11,
      'npb:franchise:buffaloes': 22,
      'npb:franchise:marines': 6,
      'npb:franchise:fighters': 8,
      'npb:franchise:kintetsu': 9,
    };
    const byName = {
      '広島東洋カープ': 11,
      'オリックス・バファローズ': 22,
      '毎日オリオンズ': 6,
      '東映フライヤーズ': 8,
      '近鉄バファローズ': 9,
    };
    expect(
      HistoricalBaseballImporter.resolveNpbPostseasonTeamId(
          '広島東洋', byName, byKey),
      11,
    );
    expect(
      HistoricalBaseballImporter.resolveNpbPostseasonTeamId(
          '阪　急', byName, byKey),
      22,
    );
    expect(
      HistoricalBaseballImporter.resolveNpbPostseasonTeamId(
          '大　毎', byName, byKey),
      6,
    );
    expect(
      HistoricalBaseballImporter.resolveNpbPostseasonTeamId(
          '東　映', byName, byKey),
      8,
    );
    expect(
      HistoricalBaseballImporter.resolveNpbPostseasonTeamId(
          '大阪近鉄', byName, byKey),
      9,
    );
  });

  test('NPB calendar parser routes both Climax stages', () {
    const source = '''
      <title>2024年10月</title>
      <table><tr><td class="stschedule"><div class="stvsteam">
          <div class="tescheaten">CS ファーストS</div>
          <div><a href="/bis/2024/games/s2024101201980.html">神 1 - 3 デ</a></div>
          <div class="tescheaten">CS ファイナルS</div>
          <div><a href="/bis/2024/games/s2024101601985.html">巨 0 - 2 デ</a></div>
        </div></td></tr></table>
    ''';
    final games = HistoricalBaseballImporter.parseNpbClimaxCalendar(
      source,
      expectedYear: 2024,
      sourceUrl: HistoricalBaseballImporter.npbClimaxCalendarUrl(2024),
    );
    expect(games.map((game) => game.codeGame), ['CS1', 'CSF']);
    expect(games.first.externalId, 's2024101201980.html');
    expect(games.first.state, '試合終了');
  });

  test('early Climax calendars use 第1S and 第2S headings', () {
    const source = '''
      <title>2009年10月</title>
      <table><tr><td class="stschedule"><div class="stvsteam">
          <div class="tescheaten">パ CS 第1S</div>
          <div><a href="/bis/2009/games/s2009101601715.html">楽 11 - 4 ソ</a></div>
          <div class="tescheaten">セ CS 第2S</div>
          <div><a href="/bis/2009/games/s2009102101720.html">中 2 - 3 巨</a></div>
        </div></td></tr></table>
    ''';
    final games = HistoricalBaseballImporter.parseNpbClimaxCalendar(
      source,
      expectedYear: 2009,
      sourceUrl: HistoricalBaseballImporter.npbClimaxCalendarUrl(2009),
    );
    expect(games.map((game) => game.codeGame), ['CS1', 'CSF']);
    expect(games.first.homeTeamKey, '楽');
    expect(games.last.awayTeamKey, '巨');
  });

  test('MLB team pitching stats fill standings when league table is empty', () {
    const source = {
      'stats': [
        {
          'splits': [
            {
              'season': '1892',
              'team': {
                'id': 144,
                'name': 'Boston Beaneaters',
                'teamName': 'Beaneaters'
              },
              'stat': {
                'wins': 102,
                'losses': 48,
                'gamesPlayed': 152,
                'winPercentage': '.680'
              }
            },
            {
              'season': '1892',
              'team': {
                'id': 209,
                'name': 'Cleveland Spiders',
                'teamName': 'Spiders'
              },
              'stat': {
                'wins': 93,
                'losses': 56,
                'gamesPlayed': 152,
                'winPercentage': '.624'
              }
            }
          ]
        }
      ]
    };
    final rows =
        HistoricalBaseballImporter.standingsFromTeamPitching(source, 1892);
    expect(rows, hasLength(2));
    expect(rows.first['team']['name'], 'Boston Beaneaters');
    expect(rows.first['wins'], 102);
    expect(rows.first['leagueRank'], 1);
    expect(rows.last['leagueRank'], 2);
  });

  test('postseason source routing is stable', () {
    expect(
      HistoricalBaseballImporter.mlbPostseasonUri(2024)
          .queryParameters['gameTypes'],
      'F,D,L,W',
    );
    expect(HistoricalBaseballImporter.npbJapanSeriesUrl(1950),
        endsWith('linescore1950.html'));
    expect(HistoricalBaseballImporter.npbClimaxCalendarUrl(2007),
        endsWith('/bis/2007/calendar/index_10.html'));
  });

  test('latin1-decoded UTF-8 team names can be repaired', () {
    final mojibake = String.fromCharCodes(utf8.encode('大阪タイガース'));
    expect(HistoricalBaseballImporter.repairUtf8Mojibake(mojibake), '大阪タイガース');
    expect(HistoricalBaseballImporter.repairUtf8Mojibake('阪神タイガース'), isNull);
  });

  test('official HTML is decoded as UTF-8 when charset is omitted', () {
    const html = '''
      <table>
        <tr><th>順位</th><th>選　手</th><th>打率</th><th>試合</th>
          <th>打数</th><th>得点</th><th>安打</th></tr>
        <tr><td>1</td><td>中根 之 (名古屋)</td><td>.376</td>
          <td>25</td><td>93</td><td>20</td><td>35</td></tr>
      </table>
    ''';
    final response = http.Response.bytes(utf8.encode(html), 200);
    final decoded = HistoricalBaseballImporter.decodeOfficialHtml(response);
    final page = HistoricalBaseballImporter.parseNpbYearPage(
      decoded,
      year: 1936,
      leagueId: 1,
    );
    expect(page.hitting, hasLength(1));
    expect(page.hitting.single.playerName, '中根 之');
    expect(page.hitting.single.teamAlias, '名古屋');
  });

  test('CLI requires explicit bounded range and accepts NPB 1936', () {
    final options = BackfillOptions.parse(
      ['--org=mlb', '--from=2020', '--to=2021', '--resume'],
    );
    expect(options.org, 'mlb');
    expect(options.resume, isTrue);
    expect(
      BackfillOptions.parse(['--org=npb', '--from=1936', '--to=1936']).fromYear,
      1936,
    );
    expect(
        () => BackfillOptions.parse(['--org=npb', '--from=1935', '--to=1936']),
        throwsFormatException);
    expect(
      BackfillOptions.parse(['--org=all', '--from=1876', '--to=1876']).fromYear,
      1876,
    );
  });

  test('checkpoint keys uniquely identify a dataset', () {
    expect(
      HistoricalBaseballImporter.checkpointKey(
          'npb', 2009, 'postseason-climax'),
      'npb|2009|postseason-climax',
    );
    expect(
      HistoricalBaseballImporter.doneCheckpointStatuses,
      containsAll(['complete', 'not_applicable', 'unavailable', 'no_data']),
    );
  });
}
