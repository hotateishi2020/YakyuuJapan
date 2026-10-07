import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import '../tools/Postgres.dart';

typedef HistoricalHttpGet = Future<http.Response> Function(Uri uri);

/// Resumable historical importer for official MLB and NPB sources.
///
/// Each organisation/year/league/dataset is committed separately. A checkpoint
/// is marked complete only after that dataset commits; rerunning the small gap
/// between commit and checkpoint is safe because dataset writes are idempotent.
class HistoricalBaseballImporter {
  HistoricalBaseballImporter({
    HistoricalHttpGet? httpGet,
    this.maxHttpAttempts = 4,
    this.retryBaseDelay = const Duration(milliseconds: 500),
  }) : _httpGet = httpGet ?? http.get;

  final HistoricalHttpGet _httpGet;
  final int maxHttpAttempts;
  final Duration retryBaseDelay;
  final Map<String, int> _teamIdCache = {};
  final Map<String, int> _playerIdCache = {};

  static const int writeChunkSize = 300;

  static const _mlbLeagues = <int, int>{103: 3, 104: 4};
  static const _npbLeagues = <String, int>{
    'centralleague': 1,
    'pacificleague': 2,
  };

  static const _hittingStatIds = <int>[1, 2, 3, 4, 5, 6, 7, 8, 20, 22];
  static const _pitchingStatIds = <int>[
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    21
  ];

  static const _bulkHittingCareerSql = '''
    WITH data AS (
      SELECT * FROM jsonb_to_recordset(\$1::jsonb) AS x(
        player_id integer, year integer, team_id integer, games integer,
        appearances integer, at_bats integer, runs integer, rbi integer,
        hits integer, doubles integer, triples integer, home_runs integer,
        total_bases integer, steals integer, caught integer, sacrifice integer,
        walks integer, hit_by_pitch integer, strikeouts integer,
        double_plays integer, average numeric, slugging numeric, onbase numeric
      )
    ), updated AS (
      UPDATE m_player_career career SET
        int_games = data.games, int_appearance = data.appearances,
        int_batting = data.at_bats, int_runs = data.runs, int_rbi = data.rbi,
        int_hit1 = data.hits, int_hit2 = data.doubles, int_hit3 = data.triples,
        int_homerun = data.home_runs, int_total_bases = data.total_bases,
        int_steal_base = data.steals, int_steal_caught = data.caught,
        int_sacrifice = data.sacrifice, int_four_batting = data.walks,
        int_dead_batting = data.hit_by_pitch,
        int_strike_out_batting = data.strikeouts,
        int_double_play = data.double_plays,
        double_average_batting = data.average,
        double_average_slugging = data.slugging,
        double_average_onbase = data.onbase, flg_delete = false, updat = now()
      FROM data
      WHERE career.id_player = data.player_id
        AND career.int_year = data.year AND career.id_team = data.team_id
        AND COALESCE(career.flg_delete, false) = false
      RETURNING career.id
    )
    INSERT INTO m_player_career
      (id_player, int_year, id_team, int_games, int_appearance, int_batting,
       int_runs, int_rbi, int_hit1, int_hit2, int_hit3, int_homerun,
       int_total_bases, int_steal_base, int_steal_caught, int_sacrifice,
       int_four_batting, int_dead_batting, int_strike_out_batting,
       int_double_play, double_average_batting, double_average_slugging,
       double_average_onbase, flg_delete, crtat, updat)
    SELECT data.player_id, data.year, data.team_id, data.games, data.appearances,
      data.at_bats, data.runs, data.rbi, data.hits, data.doubles, data.triples,
      data.home_runs, data.total_bases, data.steals, data.caught,
      data.sacrifice, data.walks, data.hit_by_pitch, data.strikeouts,
      data.double_plays, data.average, data.slugging, data.onbase,
      false, now(), now()
    FROM data
    WHERE NOT EXISTS (
      SELECT 1 FROM m_player_career career
      WHERE career.id_player = data.player_id
        AND career.int_year = data.year AND career.id_team = data.team_id
        AND COALESCE(career.flg_delete, false) = false
    )
  ''';

  static const _bulkPitchingCareerSql = '''
    WITH data AS (
      SELECT * FROM jsonb_to_recordset(\$1::jsonb) AS x(
        player_id integer, year integer, team_id integer, games integer,
        wins integer, losses integer, saves integer, holds integer,
        hold_points integer, complete_games integer, shutouts integer,
        win_average numeric, batters integer, innings numeric, hits integer,
        home_runs integer, walks integer, hit_batsmen integer,
        strikeouts integer, wild_pitches integer, balks integer, runs integer,
        earned_runs integer, era numeric
      )
    ), updated AS (
      UPDATE m_player_career career SET
        int_pitching = data.games, int_win = data.wins, int_lose = data.losses,
        int_save = data.saves, int_hold = data.holds,
        int_hold_point = data.hold_points,
        int_complete_game = data.complete_games,
        int_shutout = data.shutouts, double_average_win = data.win_average,
        int_batter = data.batters, double_inning = data.innings,
        int_hit_pitcher = data.hits, int_homerun_pitcher = data.home_runs,
        int_four_pitcher = data.walks, int_dead_pitcher = data.hit_batsmen,
        int_strike_out_pitcher = data.strikeouts,
        int_wild_pitch = data.wild_pitches, int_balk = data.balks,
        int_runs_allowed = data.runs, int_earned_runds = data.earned_runs,
        double_average_earned_runs = data.era,
        flg_delete = false, updat = now()
      FROM data
      WHERE career.id_player = data.player_id
        AND career.int_year = data.year AND career.id_team = data.team_id
        AND COALESCE(career.flg_delete, false) = false
      RETURNING career.id
    )
    INSERT INTO m_player_career
      (id_player, int_year, id_team, int_games, int_pitching, int_win, int_lose,
       int_save, int_hold, int_hold_point, int_complete_game, int_shutout,
       double_average_win, int_batter, double_inning, int_hit_pitcher,
       int_homerun_pitcher, int_four_pitcher, int_dead_pitcher,
       int_strike_out_pitcher, int_wild_pitch, int_balk, int_runs_allowed,
       int_earned_runds, double_average_earned_runs,
       flg_delete, crtat, updat)
    SELECT data.player_id, data.year, data.team_id, data.games, data.games,
      data.wins, data.losses, data.saves, data.holds, data.hold_points,
      data.complete_games, data.shutouts, data.win_average, data.batters,
      data.innings, data.hits, data.home_runs, data.walks, data.hit_batsmen,
      data.strikeouts, data.wild_pitches, data.balks, data.runs,
      data.earned_runs, data.era, false, now(), now()
    FROM data
    WHERE NOT EXISTS (
      SELECT 1 FROM m_player_career career
      WHERE career.id_player = data.player_id
        AND career.int_year = data.year AND career.id_team = data.team_id
        AND COALESCE(career.flg_delete, false) = false
    )
  ''';

  bool _schemaReady = false;
  final List<String> _failedDatasets = [];
  final Set<String> _completeCheckpoints = {};
  bool _checkpointsLoaded = false;

  static const doneCheckpointStatuses = {
    'complete',
    'unavailable',
    'no_data',
    'not_applicable',
  };

  static String checkpointKey(String org, int year, String dataset) =>
      '$org|$year|$dataset';

  static Future<void> ensureYearRetire(Connection conn) async {
    await conn.execute(
        'ALTER TABLE m_player ADD COLUMN IF NOT EXISTS year_retire integer');
    await conn.execute('''
      WITH last_year AS (
        SELECT id_player, MAX(int_year) AS last_year
        FROM (
          SELECT id_player, int_year
          FROM m_player_career
          WHERE COALESCE(flg_delete, false) = false AND int_year > 0
          UNION ALL
          SELECT id_player, int_year
          FROM t_stats_player
          WHERE COALESCE(flg_delete, false) = false
            AND int_year IS NOT NULL AND int_year > 0
        ) years
        GROUP BY id_player
      )
      UPDATE m_player player
      SET year_retire = computed.year_retire
      FROM (
        SELECT
          last_year.id_player,
          CASE
            WHEN last_year.last_year < EXTRACT(YEAR FROM CURRENT_DATE)::int
              THEN last_year.last_year
            ELSE NULL
          END AS year_retire
        FROM last_year
      ) computed
      WHERE player.id = computed.id_player
        AND player.year_retire IS DISTINCT FROM computed.year_retire
    ''');
  }

  Future<void> ensureSchema(Connection conn) async {
    if (_schemaReady) return;
    await ensureYearRetire(conn);
    final alreadyMigrated = await conn.execute('''
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'm_team'
        AND column_name = 'source_key'
    ''');
    final checkpointReady = await conn.execute('''
      SELECT 1
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = 'historical_backfill_checkpoint'
    ''');
    if (alreadyMigrated.isNotEmpty && checkpointReady.isNotEmpty) {
      await _attachKnownTeamIdentities(conn);
      final dirty = await conn.execute('''
        SELECT 1 FROM m_team
        WHERE source_key LIKE 'npb:%'
          AND (name_full LIKE '%Ã%' OR name_full LIKE '%ã%' OR name_full LIKE '%Â%')
        LIMIT 1
      ''');
      if (dirty.isNotEmpty) {
        await _repairNpbMojibakeTeams(conn);
      }
      _schemaReady = true;
      return;
    }

    await conn
        .execute('ALTER TABLE m_team ADD COLUMN IF NOT EXISTS source_key text');
    await conn.execute(
        'ALTER TABLE m_team ADD COLUMN IF NOT EXISTS external_id text');
    await conn.execute(
        'ALTER TABLE m_player ADD COLUMN IF NOT EXISTS source_key text');
    await conn.execute(
        'ALTER TABLE m_player ADD COLUMN IF NOT EXISTS external_id text');
    await conn.execute(
        'ALTER TABLE t_stats_player ADD COLUMN IF NOT EXISTS int_year integer');
    await conn.execute(
        'ALTER TABLE t_stats_team ADD COLUMN IF NOT EXISTS id_league integer');
    await conn.execute(
        'ALTER TABLE t_stats_team ADD COLUMN IF NOT EXISTS name_team text');
    await conn.execute(
        'ALTER TABLE t_stats_team ADD COLUMN IF NOT EXISTS name_shortest text');
    await conn.execute(
        'ALTER TABLE t_stats_team ADD COLUMN IF NOT EXISTS code_area text');
    await conn
        .execute('ALTER TABLE t_game ADD COLUMN IF NOT EXISTS source_key text');
    await conn.execute(
        'ALTER TABLE t_game ADD COLUMN IF NOT EXISTS external_id text');
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS historical_backfill_checkpoint (
        org text NOT NULL,
        int_year integer NOT NULL,
        dataset text NOT NULL,
        status text NOT NULL,
        row_count integer NOT NULL DEFAULT 0,
        source_url text,
        error_text text,
        completed_at timestamptz,
        updated_at timestamptz NOT NULL DEFAULT now(),
        PRIMARY KEY (org, int_year, dataset)
      )
    ''');

    // Existing installations can contain duplicates. In that case importing
    // still works via SELECT/UPDATE; the optional index is deliberately skipped.
    await conn.execute(r'''
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_indexes
          WHERE schemaname = current_schema()
            AND indexname = 'ux_m_team_source_external'
        ) AND NOT EXISTS (
          SELECT 1 FROM m_team
          WHERE source_key IS NOT NULL AND external_id IS NOT NULL
          GROUP BY source_key, external_id HAVING count(*) > 1
        ) THEN
          CREATE UNIQUE INDEX ux_m_team_source_external
            ON m_team (source_key, external_id)
            WHERE source_key IS NOT NULL AND external_id IS NOT NULL;
        END IF;
      END $$;
    ''');
    await conn.execute(r'''
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_indexes
          WHERE schemaname = current_schema()
            AND indexname = 'ux_t_game_source_external'
        ) AND NOT EXISTS (
          SELECT 1 FROM t_game
          WHERE source_key IS NOT NULL AND external_id IS NOT NULL
          GROUP BY source_key, external_id HAVING count(*) > 1
        ) THEN
          CREATE UNIQUE INDEX ux_t_game_source_external
            ON t_game (source_key, external_id)
            WHERE source_key IS NOT NULL AND external_id IS NOT NULL;
        END IF;
      END $$;
    ''');
    await conn.execute(r'''
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_indexes
          WHERE schemaname = current_schema()
            AND indexname = 'ux_m_player_source_external'
        ) AND NOT EXISTS (
          SELECT 1 FROM m_player
          WHERE source_key IS NOT NULL AND external_id IS NOT NULL
          GROUP BY source_key, external_id HAVING count(*) > 1
        ) THEN
          CREATE UNIQUE INDEX ux_m_player_source_external
            ON m_player (source_key, external_id)
            WHERE source_key IS NOT NULL AND external_id IS NOT NULL;
        END IF;
      END $$;
    ''');
    await conn.execute('''
      CREATE INDEX IF NOT EXISTS ix_t_stats_player_year_league
        ON t_stats_player (int_year, id_league)
    ''');
    await _attachKnownTeamIdentities(conn);
    await _repairNpbMojibakeTeams(conn);
    _schemaReady = true;
  }

  static const mlbAbbreviationIds = <String, String>{
    'BAL': '110',
    'BOS': '111',
    'NYY': '147',
    'TB': '139',
    'TOR': '141',
    'CWS': '145',
    'CLE': '114',
    'DET': '116',
    'KC': '118',
    'MIN': '142',
    'ATH': '133',
    'HOU': '117',
    'LAA': '108',
    'SEA': '136',
    'TEX': '140',
    'ATL': '144',
    'MIA': '146',
    'NYM': '121',
    'PHI': '143',
    'WSH': '120',
    'CHC': '112',
    'CIN': '113',
    'MIL': '158',
    'PIT': '134',
    'STL': '138',
    'AZ': '109',
    'COL': '115',
    'LAD': '119',
    'SD': '135',
    'SF': '137',
  };

  static const npbFranchiseByExistingId = <int, String>{
    1: 'npb:franchise:giants',
    2: 'npb:franchise:tigers',
    3: 'npb:franchise:dragons',
    4: 'npb:franchise:swallows',
    5: 'npb:franchise:baystars',
    6: 'npb:franchise:carp',
    7: 'npb:franchise:hawks',
    8: 'npb:franchise:lions',
    9: 'npb:franchise:fighters',
    10: 'npb:franchise:buffaloes',
    11: 'npb:franchise:eagles',
    12: 'npb:franchise:marines',
  };

  Future<void> _attachKnownTeamIdentities(Connection conn) async {
    final pending = await conn.execute('''
      SELECT COUNT(*) FROM m_team
      WHERE COALESCE(flg_delete, false) = false
        AND (source_key IS NULL OR external_id IS NULL)
        AND (id_league IN (3, 4) OR id <= 12)
    ''');
    if (_integer(pending.first[0]) == 0) return;

    for (final entry in mlbAbbreviationIds.entries) {
      await conn.execute(
        '''
          UPDATE m_team
          SET source_key = 'mlb', external_id = \$1::text, updat = now()
          WHERE name_shortest = \$2::text
            AND id_league IN (3, 4)
            AND COALESCE(flg_delete, false) = false
            AND (source_key IS NULL OR external_id IS NULL)
        ''',
        parameters: [entry.value, entry.key],
      );
    }
    for (final entry in npbFranchiseByExistingId.entries) {
      await conn.execute(
        '''
          UPDATE m_team
          SET source_key = \$1::text, external_id = \$1::text,
              flg_delete = false, updat = now()
          WHERE id = \$2::int
            AND (source_key IS NULL OR external_id IS NULL)
        ''',
        parameters: [entry.value, entry.key],
      );
    }
  }

  Future<void> _repointTeam(
    Connection conn, {
    required int keepId,
    required int dropId,
  }) async {
    for (final sql in const [
      'UPDATE t_stats_team SET id_team = \$1 WHERE id_team = \$2',
      'UPDATE t_stats_player SET id_team = \$1 WHERE id_team = \$2',
      'UPDATE t_stats_player_latest SET id_team = \$1 WHERE id_team = \$2',
      'UPDATE m_player SET id_team = \$1 WHERE id_team = \$2',
      'UPDATE m_player_career SET id_team = \$1 WHERE id_team = \$2',
      'UPDATE t_game SET id_team_home = \$1 WHERE id_team_home = \$2',
      'UPDATE t_game SET id_team_away = \$1 WHERE id_team_away = \$2',
    ]) {
      await conn.execute(sql, parameters: [keepId, dropId]);
    }
    await conn.execute(
      '''
        UPDATE m_team
        SET source_key = NULL, external_id = NULL, flg_delete = true, updat = now()
        WHERE id = \$1::int
      ''',
      parameters: [dropId],
    );
  }

  Future<void> _repairNpbMojibakeTeams(Connection conn) async {
    final rows = await conn.execute('''
      SELECT id, source_key, name_full, name_short, name_shortest
      FROM m_team
      WHERE source_key LIKE 'npb:%'
        AND COALESCE(flg_delete, false) = false
      ORDER BY id
    ''');
    for (final row in rows) {
      final id = row[0] as int;
      final sourceKey = '${row[1] ?? ''}';
      final fullName = repairUtf8Mojibake('${row[2] ?? ''}') ?? '${row[2] ?? ''}';
      final shortName =
          repairUtf8Mojibake('${row[3] ?? ''}') ?? '${row[3] ?? ''}';
      final shortest =
          repairUtf8Mojibake('${row[4] ?? ''}') ?? '${row[4] ?? ''}';
      final correctedKey = npbTeamSourceKey(fullName);
      if (fullName.isEmpty) continue;
      final existing = await conn.execute(
        '''
          SELECT id FROM m_team
          WHERE source_key = \$1::text
            AND id <> \$2::int
            AND COALESCE(flg_delete, false) = false
          ORDER BY id LIMIT 1
        ''',
        parameters: [correctedKey, id],
      );
      if (existing.isNotEmpty) {
        await _repointTeam(
            conn, keepId: existing.first[0] as int, dropId: id);
        continue;
      }
      if (sourceKey != correctedKey ||
          fullName != '${row[2] ?? ''}' ||
          shortName != '${row[3] ?? ''}') {
        await conn.execute(
          '''
            UPDATE m_team
            SET source_key = \$1::text, external_id = \$1::text,
                name_full = \$2::text, name_short = \$3::text,
                name_shortest = \$4::text, flg_delete = false, updat = now()
            WHERE id = \$5::int
          ''',
          parameters: [
            correctedKey,
            fullName,
            shortName.isEmpty ? fullName : shortName,
            shortest.isEmpty ? fullName : shortest,
            id,
          ],
        );
      }
    }
  }

  Future<void> importRange({
    required String org,
    required int fromYear,
    required int toYear,
    bool resume = false,
    void Function(String message)? progress,
  }) async {
    if (fromYear > toYear) {
      throw ArgumentError('--from must not be later than --to');
    }
    if (!const {'npb', 'mlb', 'all'}.contains(org)) {
      throw ArgumentError('--org must be npb, mlb, or all');
    }
    final log = progress ?? print;
    await Postgres.withConnection(ensureSchema);
    _failedDatasets.clear();
    _completeCheckpoints.clear();
    _checkpointsLoaded = false;
    if (resume) {
      await _loadCompleteCheckpoints(log);
    }
    for (var year = fromYear; year <= toYear; year++) {
      if (org == 'mlb' || org == 'all') {
        await importMlbYear(year, resume: resume, progress: log);
      }
      if ((org == 'npb' || org == 'all') && year >= 1936) {
        await importNpbYear(year, resume: resume, progress: log);
      }
    }
    if (_failedDatasets.isNotEmpty) {
      log('completed with ${_failedDatasets.length} failed dataset(s):');
      for (final failure in _failedDatasets) {
        log('  $failure');
      }
    }
  }

  Future<void> importMlbYear(
    int year, {
    bool resume = false,
    void Function(String message)? progress,
  }) async {
    final log = progress ?? print;
    for (final league in _mlbLeagues.entries) {
      if (league.key == 103 && year < 1901) continue;
      if (league.key == 104 && year < 1876) continue;
      final suffix = 'league-${league.key}';
      await _runDataset(
        org: 'mlb',
        year: year,
        dataset: 'standings-$suffix',
        resume: resume,
        sourceUrl: _mlbStandingsUri(year, league.key).toString(),
        progress: log,
        load: () => _loadMlbStandings(year, league.key, league.value),
      );
      await _runDataset(
        org: 'mlb',
        year: year,
        dataset: 'hitting-$suffix',
        resume: resume,
        sourceUrl: _mlbStatsUri(year, league.key, 'hitting').toString(),
        progress: log,
        load: () => _loadMlbStats(year, league.key, league.value, 'hitting'),
      );
      await _runDataset(
        org: 'mlb',
        year: year,
        dataset: 'pitching-$suffix',
        resume: resume,
        sourceUrl: _mlbStatsUri(year, league.key, 'pitching').toString(),
        progress: log,
        load: () => _loadMlbStats(year, league.key, league.value, 'pitching'),
      );
    }
    await _importMlbPostseason(year, resume: resume, progress: log);
  }

  Future<void> importNpbYear(
    int year, {
    bool resume = false,
    void Function(String message)? progress,
  }) async {
    if (year < 1936) return;
    final log = progress ?? print;
    final sources = npbSourcesForYear(year);
    if (sources.isEmpty) {
      await _markNpbSeasonNotPlayed(year, resume: resume, progress: log);
      await _importNpbPostseason(year, resume: resume, progress: log);
      return;
    }
    final byLeague = <int, List<NpbSourceSpec>>{};
    for (final source in sources) {
      byLeague.putIfAbsent(source.leagueId, () => []).add(source);
    }
    for (final leagueSources in byLeague.values) {
      NpbYearPage? combined;
      Future<NpbYearPage> getPage() async {
        if (combined != null) return combined!;
        final pages = <NpbYearPage>[];
        for (final source in leagueSources) {
          pages.add(await _fetchNpbSource(source, year));
        }
        combined = combineNpbPages(pages);
        return combined!;
      }

      final sourceTag =
          leagueSources.map((source) => source.checkpointTag).join('+');
      final sourceUrls = leagueSources.map((source) => source.uri).join(',');
      for (final dataset in const ['standings', 'hitting', 'pitching']) {
        await _runDataset(
          org: 'npb',
          year: year,
          dataset: '$dataset-$sourceTag',
          resume: resume,
          sourceUrl: sourceUrls,
          progress: log,
          load: () async {
            final parsed = await getPage();
            if (dataset == 'standings') {
              return _loadNpbStandings(parsed);
            }
            return _loadNpbPlayers(parsed, pitching: dataset == 'pitching');
          },
        );
      }

      if (year >= 2005) {
        final leagueId = leagueSources.first.leagueId;
        final suffix = leagueId == 1 ? 'c' : 'p';
        for (final category in npbDetailedCategories.entries) {
          final uri = Uri.parse(
              'https://npb.jp/bis/$year/stats/${category.key}_$suffix.html');
          await _runOptionalDataset(
            org: 'npb',
            year: year,
            dataset: 'ranking-${category.key}-$suffix',
            resume: resume,
            sourceUrl: uri.toString(),
            progress: log,
            load: () async {
              final body = await _getHtml(uri);
              final rows = parseNpbDetailedRanking(
                body,
                expectedYear: year,
                statId: category.value,
              );
              if (rows.isEmpty) {
                if (year == DateTime.now().year) {
                  throw const HistoricalNotYetAvailable();
                }
                throw StateError('Empty NPB ranking source: $uri');
              }
              final page = await getPage();
              return _loadNpbDetailedRanking(
                  page, rows, category.value, leagueId);
            },
          );
        }
      }
    }
    await _importNpbPostseason(year, resume: resume, progress: log);
  }

  /// Before 1950 NPB was a single league. App league 1 is used as a
  /// compatibility mapping because the app has no historical one-league ID.
  static List<NpbSourceSpec> npbSourcesForYear(int year) {
    if (year < 1936) return const [];
    if (year <= 1938) {
      return [
        for (final phase in const ['s', 'f'])
          NpbSourceSpec(
            leagueId: 1,
            checkpointTag: 'oneleague-${phase == 's' ? 'spring' : 'fall'}',
            uri: 'https://npb.jp/bis/yearly/yakyuremmei_${year}$phase.html',
            phase: phase == 's' ? 'spring' : 'fall',
          ),
      ];
    }
    // 1945: Japanese Professional Baseball League cancelled (Pacific War).
    if (year == 1945) return const [];
    if (year <= 1949) {
      return [
        NpbSourceSpec(
          leagueId: 1,
          checkpointTag: 'oneleague',
          uri: 'https://npb.jp/bis/yearly/yakyuremmei_$year.html',
        ),
      ];
    }
    return [
      for (final league in _npbLeagues.entries)
        NpbSourceSpec(
          leagueId: league.value,
          checkpointTag: league.key,
          uri: year == DateTime.now().year
              ? 'https://npb.jp/bis/$year/stats/std_${league.value == 1 ? 'c' : 'p'}.html'
              : 'https://npb.jp/bis/yearly/${league.key}_$year.html',
          activeStatsBase: year == DateTime.now().year
              ? 'https://npb.jp/bis/$year/stats'
              : null,
        ),
    ];
  }

  static const npbDetailedCategories = <String, int>{
    'lb_avg': 1,
    'lb_h': 2,
    'lb_hr': 3,
    'lb_rbi': 4,
    'lb_sb': 5,
    'lb_obp': 6,
    'lb_slg': 7,
    'lp_era': 9,
    'lp_w': 10,
    'lp_so': 11,
    'lp_hld': 17,
    'lp_sv': 19,
    'lp_ip': 21,
  };

  static Uri mlbPostseasonUri(int year) => Uri.https(
        'statsapi.mlb.com',
        '/api/v1/schedule',
        {
          'sportId': '1',
          'season': '$year',
          'gameTypes': 'F,D,L,W',
          'hydrate': 'team',
        },
      );

  static String npbJapanSeriesUrl(int year) =>
      'https://npb.jp/bis/scores/nipponseries/linescore$year.html';

  static String npbClimaxCalendarUrl(int year) =>
      'https://npb.jp/bis/$year/calendar/index_10.html';

  static List<String> npbClimaxCalendarUrls(int year) => [
        npbClimaxCalendarUrl(year),
        'https://npb.jp/bis/$year/calendar/index_11.html',
      ];

  Future<void> _importMlbPostseason(
    int year, {
    required bool resume,
    required void Function(String) progress,
  }) {
    final uri = mlbPostseasonUri(year);
    return _runPostseasonDataset(
      org: 'mlb',
      year: year,
      dataset: 'postseason-mlb',
      resume: resume,
      sourceUrl: uri.toString(),
      progress: progress,
      load: () async {
        final json = await _getJson(uri);
        final games = parseMlbPostseasonSchedule(json, expectedYear: year);
        if (games.isEmpty) {
          return PostseasonImportResult(
            0,
            year == DateTime.now().year ? 'not_yet_available' : 'no_data',
          );
        }
        final count = await _loadPostseasonGames(games);
        return PostseasonImportResult(count, 'complete');
      },
    );
  }

  Future<void> _importNpbPostseason(
    int year, {
    required bool resume,
    required void Function(String) progress,
  }) async {
    if (year < 1950) {
      await _runPostseasonDataset(
        org: 'npb',
        year: year,
        dataset: 'postseason-japan-series',
        resume: resume,
        sourceUrl: '',
        progress: progress,
        load: () async => const PostseasonImportResult(0, 'not_applicable'),
      );
    } else {
      final url = npbJapanSeriesUrl(year);
      await _runPostseasonDataset(
        org: 'npb',
        year: year,
        dataset: 'postseason-japan-series',
        resume: resume,
        sourceUrl: url,
        progress: progress,
        load: () async {
          try {
            final body = await _getHtml(Uri.parse(url));
            final games =
                parseNpbJapanSeries(body, expectedYear: year, sourceUrl: url);
            if (games.isEmpty) {
              throw StateError('Empty NPB Japan Series source: $url');
            }
            return PostseasonImportResult(
                await _loadPostseasonGames(games), 'complete');
          } on HistoricalHttpException catch (error) {
            if (error.statusCode != 404) rethrow;
            if (year == DateTime.now().year) {
              return const PostseasonImportResult(0, 'not_yet_available');
            }
            rethrow;
          }
        },
      );
    }

    if (year < 2007 || year == 2020) {
      await _runPostseasonDataset(
        org: 'npb',
        year: year,
        dataset: 'postseason-climax',
        resume: resume,
        sourceUrl: '',
        progress: progress,
        load: () async => const PostseasonImportResult(0, 'not_applicable'),
      );
      return;
    }
    final urls = npbClimaxCalendarUrls(year);
    await _runPostseasonDataset(
      org: 'npb',
      year: year,
      dataset: 'postseason-climax',
      resume: resume,
      sourceUrl: urls.join(','),
      progress: progress,
      load: () async {
        try {
          final games = <HistoricalGame>[];
          for (final url in urls) {
            try {
              final body = await _getHtml(Uri.parse(url));
              games.addAll(parseNpbClimaxCalendar(body,
                  expectedYear: year, sourceUrl: url));
            } on HistoricalHttpException catch (error) {
              if (error.statusCode != 404) rethrow;
            }
          }
          if (games.isEmpty) {
            if (year == DateTime.now().year) {
              return const PostseasonImportResult(0, 'not_yet_available');
            }
            throw StateError('Empty NPB Climax source for $year');
          }
          return PostseasonImportResult(
              await _loadPostseasonGames(games), 'complete');
        } on HistoricalHttpException {
          rethrow;
        }
      },
    );
  }

  Future<void> _runPostseasonDataset({
    required String org,
    required int year,
    required String dataset,
    required bool resume,
    required String sourceUrl,
    required void Function(String) progress,
    required Future<PostseasonImportResult> Function() load,
  }) async {
    if (resume && await _checkpointComplete(org, year, dataset)) {
      progress('skip $org $year $dataset (checkpoint complete)');
      return;
    }
    progress('start $org $year $dataset');
    try {
      final result =
          await _retryBrokenConnection(load, progress, '$org $year $dataset');
      await _saveCheckpoint(
          org, year, dataset, result.status, result.rowCount, sourceUrl, null);
      progress(
          'done  $org $year $dataset (${result.rowCount} rows, ${result.status})');
    } catch (error) {
      await _saveCheckpoint(
          org, year, dataset, 'failed', 0, sourceUrl, '$error');
      progress('fail  $org $year $dataset: $error');
      _failedDatasets.add('$org $year $dataset');
    }
  }

  Future<void> _runDataset({
    required String org,
    required int year,
    required String dataset,
    required bool resume,
    required String sourceUrl,
    required void Function(String) progress,
    required Future<int> Function() load,
  }) async {
    if (resume && await _checkpointComplete(org, year, dataset)) {
      progress('skip $org $year $dataset (checkpoint complete)');
      return;
    }
    progress('start $org $year $dataset');
    try {
      final count =
          await _retryBrokenConnection(load, progress, '$org $year $dataset');
      await _saveCheckpoint(
          org, year, dataset, 'complete', count, sourceUrl, null);
      progress('done  $org $year $dataset ($count rows)');
    } on HistoricalNotYetAvailable {
      await _saveCheckpoint(
          org, year, dataset, 'not_yet_available', 0, sourceUrl, null);
      progress('skip $org $year $dataset (not yet available)');
    } on HistoricalHttpException catch (error) {
      if (error.statusCode != 404) {
        await _saveCheckpoint(
            org, year, dataset, 'failed', 0, sourceUrl, '$error');
        progress('fail  $org $year $dataset: $error');
        _failedDatasets.add('$org $year $dataset');
        return;
      }
      await _saveCheckpoint(
          org, year, dataset, 'unavailable', 0, sourceUrl, '$error');
      progress('skip $org $year $dataset (official page unavailable)');
    } catch (error) {
      await _saveCheckpoint(
          org, year, dataset, 'failed', 0, sourceUrl, '$error');
      progress('fail  $org $year $dataset: $error');
      _failedDatasets.add('$org $year $dataset');
    }
  }

  Future<void> _markNpbSeasonNotPlayed(
    int year, {
    required bool resume,
    required void Function(String) progress,
  }) async {
    for (final dataset in const [
      'standings-oneleague',
      'hitting-oneleague',
      'pitching-oneleague',
    ]) {
      if (resume && await _checkpointComplete('npb', year, dataset)) {
        progress('skip npb $year $dataset (checkpoint complete)');
        continue;
      }
      await _saveCheckpoint(
          'npb', year, dataset, 'not_applicable', 0, '', null);
      progress('skip npb $year $dataset (season not played)');
    }
  }

  Future<T> _retryBrokenConnection<T>(
    Future<T> Function() operation,
    void Function(String) progress,
    String label,
  ) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        return await operation();
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
        if (attempt == 2 || !isBrokenConnectionError(error)) {
          Error.throwWithStackTrace(error, stack);
        }
        _teamIdCache.clear();
        _playerIdCache.clear();
        progress('retry $label after closed database connection');
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  static bool isBrokenConnectionError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('connection is not open') ||
        text.contains('connection closed') ||
        text.contains('closed connection') ||
        text.contains('connection reset') ||
        text.contains('connection timed out') ||
        text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('broken pipe');
  }

  Future<void> _runOptionalDataset({
    required String org,
    required int year,
    required String dataset,
    required bool resume,
    required String sourceUrl,
    required void Function(String) progress,
    required Future<int> Function() load,
  }) async {
    if (resume && await _checkpointComplete(org, year, dataset)) {
      progress('skip $org $year $dataset (checkpoint complete)');
      return;
    }
    try {
      await _runDataset(
        org: org,
        year: year,
        dataset: dataset,
        resume: false,
        sourceUrl: sourceUrl,
        progress: progress,
        load: load,
      );
    } on HistoricalHttpException catch (error) {
      if (error.statusCode != 404) rethrow;
      await _saveCheckpoint(
          org, year, dataset, 'unavailable', 0, sourceUrl, error.toString());
      progress('skip $org $year $dataset (official page unavailable)');
    }
  }

  Future<void> _loadCompleteCheckpoints(void Function(String) progress) async {
    await _retryBrokenConnection(() async {
      await Postgres.withConnection((conn) async {
        final result = await conn.execute('''
          SELECT org, int_year, dataset, status
          FROM historical_backfill_checkpoint
        ''');
        _completeCheckpoints.clear();
        for (final row in result) {
          if (doneCheckpointStatuses.contains(row[3])) {
            _completeCheckpoints.add(
                checkpointKey('${row[0]}', row[1] as int, '${row[2]}'));
          }
        }
      });
    }, progress, 'load checkpoints');
    _checkpointsLoaded = true;
    progress('loaded ${_completeCheckpoints.length} completed checkpoints');
  }

  Future<bool> _checkpointComplete(String org, int year, String dataset) async {
    final key = checkpointKey(org, year, dataset);
    if (_completeCheckpoints.contains(key)) return true;
    if (_checkpointsLoaded) return false;
    return _retryBrokenConnection(() {
      return Postgres.withConnection((conn) async {
        final result = await conn.execute(
          '''
            SELECT status FROM historical_backfill_checkpoint
            WHERE org = \$1::text AND int_year = \$2::int AND dataset = \$3::text
          ''',
          parameters: [org, year, dataset],
        );
        final done = result.isNotEmpty &&
            doneCheckpointStatuses.contains(result.first[0]);
        if (done) _completeCheckpoints.add(key);
        return done;
      });
    }, (_) {}, '$org $year $dataset checkpoint');
  }

  Future<void> _saveCheckpoint(
    String org,
    int year,
    String dataset,
    String status,
    int count,
    String sourceUrl,
    String? error,
  ) async {
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        await Postgres.withConnection((conn) => conn.execute(
              '''
                INSERT INTO historical_backfill_checkpoint
                  (org, int_year, dataset, status, row_count, source_url,
                   error_text, completed_at, updated_at)
                VALUES (\$1::text, \$2::int, \$3::text, \$4::text, \$5::int,
                        \$6::text, \$7::text,
                        CASE WHEN \$4::text IN
                          ('complete','unavailable','no_data','not_applicable')
                          THEN now() ELSE NULL END,
                        now())
                ON CONFLICT (org, int_year, dataset) DO UPDATE SET
                  status = EXCLUDED.status,
                  row_count = EXCLUDED.row_count,
                  source_url = EXCLUDED.source_url,
                  error_text = EXCLUDED.error_text,
                  completed_at = EXCLUDED.completed_at,
                  updated_at = now()
              ''',
              parameters: [org, year, dataset, status, count, sourceUrl, error],
            ));
        final key = checkpointKey(org, year, dataset);
        if (doneCheckpointStatuses.contains(status)) {
          _completeCheckpoints.add(key);
        } else {
          _completeCheckpoints.remove(key);
        }
        return;
      } catch (checkpointError, stack) {
        if (attempt == 4 || !isBrokenConnectionError(checkpointError)) {
          Error.throwWithStackTrace(checkpointError, stack);
        }
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  static Uri _mlbTeamPitchingStatsUri(int year, int leagueId) => Uri.https(
        'statsapi.mlb.com',
        '/api/v1/teams/stats',
        {
          'season': '$year',
          'group': 'pitching',
          'stats': 'season',
          'sportIds': '1',
          'leagueIds': '$leagueId',
        },
      );

  static Uri _mlbStandingsUri(int year, int leagueId) => Uri.https(
        'statsapi.mlb.com',
        '/api/v1/standings',
        {
          'leagueId': '$leagueId',
          'season': '$year',
          'standingsTypes': 'regularSeason',
          'hydrate': 'team',
        },
      );

  static Uri _mlbStatsUri(int year, int leagueId, String group) => Uri.https(
        'statsapi.mlb.com',
        '/api/v1/stats',
        {
          'stats': 'season',
          'group': group,
          'season': '$year',
          'leagueIds': '$leagueId',
          'sportIds': '1',
          'playerPool': 'ALL',
          'limit': '5000',
          'hydrate': 'person,team',
        },
      );

  Future<http.Response> _get(Uri uri) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxHttpAttempts; attempt++) {
      try {
        final response =
            await _httpGet(uri).timeout(const Duration(seconds: 45));
        if (response.statusCode == 200) return response;
        if (response.statusCode == 404) {
          throw HistoricalHttpException(404, uri);
        }
        if (response.statusCode != 429 && response.statusCode < 500) {
          throw HistoricalHttpException(response.statusCode, uri);
        }
        lastError = HistoricalHttpException(response.statusCode, uri);
      } on HistoricalHttpException catch (error) {
        if (error.statusCode == 404 ||
            (error.statusCode != 429 && error.statusCode < 500)) {
          rethrow;
        }
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      }
      if (attempt < maxHttpAttempts) {
        await Future<void>.delayed(retryBaseDelay * (1 << (attempt - 1)));
      }
    }
    throw StateError(
        'HTTP failed after $maxHttpAttempts attempts for $uri: $lastError');
  }

  /// Exposed for focused transport tests; import code uses the same bounded
  /// retry path.
  Future<http.Response> fetchOfficial(Uri uri) => _get(uri);

  /// NPB pages are UTF-8. Dart's [http.Response.body] falls back to latin1
  /// when Content-Type has no charset, which breaks Japanese header matching.
  static String decodeOfficialHtml(http.Response response) {
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<String> _getHtml(Uri uri) async {
    return decodeOfficialHtml(await _get(uri));
  }

  Future<NpbYearPage> _fetchNpbSource(
      NpbSourceSpec source, int expectedYear) async {
    final body = await _getHtml(Uri.parse(source.uri));
    validateNpbSeason(body, expectedYear);
    var page = parseNpbYearPage(
      body,
      year: expectedYear,
      leagueId: source.leagueId,
      phase: source.phase,
    );
    if (source.activeStatsBase != null) {
      final suffix = source.leagueId == 1 ? 'c' : 'p';
      final extra = <NpbYearPage>[];
      for (final kind in const ['bat', 'pit']) {
        final uri = Uri.parse('${source.activeStatsBase}/${kind}_$suffix.html');
        final extraBody = await _getHtml(uri);
        validateNpbSeason(extraBody, expectedYear);
        extra.add(parseNpbYearPage(
          extraBody,
          year: expectedYear,
          leagueId: source.leagueId,
          phase: source.phase,
        ));
      }
      page = combineNpbPages([page, ...extra]);
    }
    // A split phase is valid with standings alone (notably spring 1936);
    // individual rows are combined from whichever official phase publishes them.
    if (page.standings.isEmpty) {
      throw StateError('Empty NPB source for $expectedYear: ${source.uri}');
    }
    return page;
  }

  static void validateNpbSeason(String source, int expectedYear) {
    final years = RegExp(r'(?:19|20)\d{2}')
        .allMatches(source)
        .map((match) => int.parse(match.group(0)!))
        .toSet();
    if (!years.contains(expectedYear)) {
      throw StateError(
          'NPB season mismatch: expected $expectedYear, found ${years.take(5).join(',')}');
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _get(uri);
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<String, dynamic>) {
      throw FormatException('Expected JSON object from $uri');
    }
    return value;
  }

  Future<int> _loadMlbStandings(
      int year, int mlbLeagueId, int appLeagueId) async {
    final json = await _getJson(_mlbStandingsUri(year, mlbLeagueId));
    final rows = <Map<String, dynamic>>[];
    for (final record in _maps(json['records'])) {
      final division = _map(record['division']);
      for (final teamRecord in _maps(record['teamRecords'])) {
        teamRecord['_division'] = division;
        rows.add(teamRecord);
      }
    }
    if (rows.isEmpty) {
      final fallback =
          await _getJson(_mlbTeamPitchingStatsUri(year, mlbLeagueId));
      rows.addAll(standingsFromTeamPitching(fallback, year));
    }
    if (rows.isEmpty) {
      throw StateError(
          'MLB returned no standings for $year league $mlbLeagueId');
    }
    return _transaction((conn) async {
      final teamIds = <int>[];
      var rank = 0;
      rows.sort((a, b) => _number(b['winningPercentage'])
          .compareTo(_number(a['winningPercentage'])));
      for (final row in rows) {
        final returnedSeason = _integer(row['season']);
        if (returnedSeason > 0 && returnedSeason != year) {
          throw StateError(
              'MLB standings season mismatch: expected $year, got $returnedSeason');
        }
        final team = _map(row['team']);
        final externalId = _integer(team['id']);
        final name = _text(team['name']);
        if (externalId <= 0 || name.isEmpty) continue;
        final teamId = await _upsertTeam(
          conn,
          sourceKey: 'mlb',
          externalId: '$externalId',
          fullName: name,
          leagueId: appLeagueId,
          shortName:
              _text(team['teamName']).isEmpty ? name : _text(team['teamName']),
        );
        teamIds.add(teamId);
        rank++;
        final area = mlbDivisionCode(_text(_map(row['_division'])['name']));
        await conn.execute(
          '''
            DELETE FROM t_stats_team
            WHERE year = \$1::int AND id_team = \$2::int
          ''',
          parameters: [year, teamId],
        );
        await conn.execute(
          '''
            INSERT INTO t_stats_team
              (year, id_team, id_league, name_team, name_shortest, code_area,
               int_rank, int_game, int_win, int_lose, int_draw, game_behind,
               flg_delete, crtat, updat)
            VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9,\$10,\$11,\$12,
                    false,now(),now())
          ''',
          parameters: [
            year,
            teamId,
            appLeagueId,
            name,
            _text(team['teamName']).isEmpty ? name : _text(team['teamName']),
            area,
            _integer(row['leagueRank']) > 0
                ? _integer(row['leagueRank'])
                : rank,
            _integer(row['gamesPlayed']),
            _integer(row['wins']),
            _integer(row['losses']),
            0,
            _text(row['gamesBack']),
          ],
        );
      }
      return teamIds.length;
    });
  }

  Future<int> _loadMlbStats(
    int year,
    int mlbLeagueId,
    int appLeagueId,
    String group,
  ) async {
    final json = await _getJson(_mlbStatsUri(year, mlbLeagueId, group));
    final splits = <Map<String, dynamic>>[];
    for (final stat in _maps(json['stats'])) {
      splits.addAll(_maps(stat['splits']));
    }
    if (splits.isEmpty) {
      throw StateError(
          'MLB returned no $group stats for $year league $mlbLeagueId');
    }
    final rawLines = <MlbRawLine>[];
    for (final split in splits) {
      final returnedSeason = _integer(split['season']);
      if (returnedSeason > 0 && returnedSeason != year) {
        throw StateError(
            'MLB stats season mismatch: expected $year, got $returnedSeason');
      }
      final person = _map(split['player']).isNotEmpty
          ? _map(split['player'])
          : _map(split['person']);
      final team = _map(split['team']);
      final playerExternalId = _integer(person['id']);
      final teamExternalId = _integer(team['id']);
      final fullName = _text(person['fullName']);
      final teamName = _text(team['name']);
      if (playerExternalId <= 0 ||
          teamExternalId <= 0 ||
          fullName.isEmpty ||
          teamName.isEmpty) {
        continue;
      }
      rawLines.add(MlbRawLine(
        playerExternalId: '$playerExternalId',
        teamExternalId: '$teamExternalId',
        playerName: fullName,
        teamName: teamName,
        teamShortName: _text(team['teamName']).isEmpty
            ? teamName
            : _text(team['teamName']),
        birthDate: _date(person['birthDate']),
        values: _map(split['stat']),
      ));
    }
    if (rawLines.isEmpty) {
      throw StateError(
          'MLB returned no usable $group rows for $year league $mlbLeagueId');
    }

    await _transaction(
        (conn) => _bulkResolveMlbEntities(conn, rawLines, appLeagueId));
    final lines = [
      for (final raw in rawLines)
        SeasonLine(
          playerId: _playerIdCache['mlb|${raw.playerExternalId}']!,
          teamId: _teamIdCache['mlb|${raw.teamExternalId}']!,
          leagueId: appLeagueId,
          name: raw.playerName,
          teamName: raw.teamName,
          values: raw.values,
        ),
    ];

    for (final chunk in chunksOf(lines, writeChunkSize)) {
      await _transaction((conn) => _bulkUpsertCareers(
            conn,
            year,
            chunk,
            pitching: group == 'pitching',
          ));
    }
    final ids = group == 'pitching' ? _pitchingStatIds : _hittingStatIds;
    await _replaceMlbRankingsBounded(year, appLeagueId, ids, lines);
    return lines.length;
  }

  Future<void> _bulkResolveMlbEntities(
    Connection conn,
    List<MlbRawLine> rawLines,
    int leagueId,
  ) async {
    final teamsByExternal = <String, MlbRawLine>{};
    for (final line in rawLines) {
      teamsByExternal[line.teamExternalId] = line;
    }
    final teamRows = [
      for (final entry in teamsByExternal.entries)
        {
          'external_id': entry.key,
          'full_name': entry.value.teamName,
          'short_name': entry.value.teamShortName,
          'league_id': leagueId,
        }
    ];
    await conn.execute(
      '''
        WITH data AS (
          SELECT * FROM jsonb_to_recordset(\$1::jsonb) AS x(
            external_id text, full_name text, short_name text, league_id integer
          )
        )
        INSERT INTO m_team
          (name_shortest, name_short, name_full, id_league, color_font,
           color_back, source_key, external_id, flg_delete, crtat, updat)
        SELECT data.short_name, data.short_name, data.full_name, data.league_id,
               '', '', 'mlb', data.external_id, false, now(), now()
        FROM data
        WHERE NOT EXISTS (
          SELECT 1 FROM m_team existing
          WHERE existing.source_key = 'mlb'
            AND existing.external_id = data.external_id
        )
      ''',
      parameters: [jsonEncode(teamRows)],
    );
    final teamIds = await conn.execute(
      '''
        SELECT DISTINCT ON (external_id) external_id, id FROM m_team
        WHERE source_key = \$1::text AND external_id = ANY(\$2::text[])
        ORDER BY external_id, id
      ''',
      parameters: ['mlb', teamsByExternal.keys.toList()],
    );
    for (final row in teamIds) {
      _teamIdCache['mlb|${row[0]}'] = row[1] as int;
    }
    if (teamsByExternal.keys
        .any((key) => !_teamIdCache.containsKey('mlb|$key'))) {
      throw StateError('Failed to resolve all MLB teams in bulk');
    }

    final playersByExternal = <String, MlbRawLine>{};
    for (final line in rawLines) {
      playersByExternal[line.playerExternalId] = line;
    }
    final playerRows = [
      for (final entry in playersByExternal.entries)
        {
          'external_id': entry.key,
          'full_name': entry.value.playerName,
          'last_name': splitPlayerName(entry.value.playerName).$1,
          'first_name': splitPlayerName(entry.value.playerName).$2,
          'team_id': _teamIdCache['mlb|${entry.value.teamExternalId}'],
          'birth_date': entry.value.birthDate?.toIso8601String() ?? '',
        }
    ];
    await conn.execute(
      '''
        WITH data AS (
          SELECT * FROM jsonb_to_recordset(\$1::jsonb) AS x(
            external_id text, full_name text, last_name text, first_name text,
            team_id integer, birth_date text
          )
        )
        UPDATE m_player player SET
          name_full = data.full_name,
          name_last = data.last_name,
          name_first = data.first_name,
          id_team = data.team_id,
          date_birth = COALESCE(
            NULLIF(data.birth_date, '')::timestamp, player.date_birth),
          flg_delete = false,
          updat = now()
        FROM data
        WHERE player.source_key = 'mlb'
          AND player.external_id = data.external_id
      ''',
      parameters: [jsonEncode(playerRows)],
    );
    await conn.execute(
      '''
        WITH data AS (
          SELECT * FROM jsonb_to_recordset(\$1::jsonb) AS x(
            external_id text, full_name text, last_name text, first_name text,
            team_id integer, birth_date text
          )
        )
        INSERT INTO m_player
          (name_last, name_first, name_middle, name_full, id_team, date_birth,
           source_key, external_id, flg_delete, crtat, updat)
        SELECT data.last_name, data.first_name, '', data.full_name, data.team_id,
               NULLIF(data.birth_date, '')::timestamp,
               'mlb', data.external_id, false, now(), now()
        FROM data
        WHERE NOT EXISTS (
          SELECT 1 FROM m_player existing
          WHERE existing.source_key = 'mlb'
            AND existing.external_id = data.external_id
        )
      ''',
      parameters: [jsonEncode(playerRows)],
    );
    final playerIds = await conn.execute(
      '''
        SELECT DISTINCT ON (external_id) external_id, id FROM m_player
        WHERE source_key = \$1::text AND external_id = ANY(\$2::text[])
        ORDER BY external_id, id
      ''',
      parameters: ['mlb', playersByExternal.keys.toList()],
    );
    for (final row in playerIds) {
      _playerIdCache['mlb|${row[0]}'] = row[1] as int;
    }
    if (playersByExternal.keys
        .any((key) => !_playerIdCache.containsKey('mlb|$key'))) {
      throw StateError('Failed to resolve all MLB players in bulk');
    }
  }

  Future<void> _bulkUpsertCareers(
    Connection conn,
    int year,
    List<SeasonLine> lines, {
    required bool pitching,
  }) async {
    final rows = [
      for (final line in lines) careerJsonRow(line, year, pitching: pitching),
    ];
    if (rows.isEmpty) return;
    final json = jsonEncode(rows);
    if (pitching) {
      await conn.execute(_bulkPitchingCareerSql, parameters: [json]);
    } else {
      await conn.execute(_bulkHittingCareerSql, parameters: [json]);
    }
  }

  Future<void> _replaceMlbRankingsBounded(
    int year,
    int leagueId,
    List<int> statIds,
    List<SeasonLine> lines,
  ) async {
    final teamGames = <int, int>{};
    await Postgres.withConnection((conn) async {
      final games = await conn.execute(
        '''
          SELECT id_team, max(int_game) AS games FROM t_stats_team
          WHERE year = \$1::int GROUP BY id_team
        ''',
        parameters: [year],
      );
      for (final row in games) {
        teamGames[row[0] as int] = _integer(row[1]);
      }
    });
    for (final statId in statIds) {
      final candidates = <RankValue>[];
      for (final line in lines) {
        final value = statValue(statId, line.values);
        if (value == null) continue;
        if (!qualifiesForMlbRate(
            statId, line.values, teamGames[line.teamId] ?? 0)) {
          continue;
        }
        candidates
            .add(RankValue(line, value, countForStat(statId, line.values)));
      }
      await _transaction((conn) async {
        await _deleteRankings(conn, year, leagueId, [statId]);
        await _insertRankValues(conn, year, leagueId, statId, candidates);
      });
    }
  }

  static Map<String, Object?> careerJsonRow(
    SeasonLine line,
    int year, {
    required bool pitching,
  }) {
    final v = line.values;
    if (pitching) {
      return {
        'player_id': line.playerId,
        'year': year,
        'team_id': line.teamId,
        'games': _integer(v['gamesPitched']),
        'wins': _integer(v['wins']),
        'losses': _integer(v['losses']),
        'saves': _integer(v['saves']),
        'holds': _integer(v['holds']),
        'hold_points': _integer(v['holdPoints']),
        'complete_games': _integer(v['completeGames']),
        'shutouts': _integer(v['shutouts']),
        'win_average': _number(v['winPercentage']),
        'batters': _integer(v['battersFaced']),
        'innings': baseballInnings(_text(v['inningsPitched'])),
        'hits': _integer(v['hits']),
        'home_runs': _integer(v['homeRuns']),
        'walks': _integer(v['baseOnBalls']),
        'hit_batsmen': _integer(v['hitBatsmen']),
        'strikeouts': _integer(v['strikeOuts']),
        'wild_pitches': _integer(v['wildPitches']),
        'balks': _integer(v['balks']),
        'runs': _integer(v['runs']),
        'earned_runs': _integer(v['earnedRuns']),
        'era': _number(v['era']),
      };
    }
    return {
      'player_id': line.playerId,
      'year': year,
      'team_id': line.teamId,
      'games': _integer(v['gamesPlayed']),
      'appearances': _integer(v['plateAppearances']),
      'at_bats': _integer(v['atBats']),
      'runs': _integer(v['runs']),
      'rbi': _integer(v['rbi']),
      'hits': _integer(v['hits']),
      'doubles': _integer(v['doubles']),
      'triples': _integer(v['triples']),
      'home_runs': _integer(v['homeRuns']),
      'total_bases': _integer(v['totalBases']),
      'steals': _integer(v['stolenBases']),
      'caught': _integer(v['caughtStealing']),
      'sacrifice': _integer(v['sacBunts']),
      'walks': _integer(v['baseOnBalls']),
      'hit_by_pitch': _integer(v['hitByPitch']),
      'strikeouts': _integer(v['strikeOuts']),
      'double_plays': _integer(v['groundIntoDoublePlay']),
      'average': _number(v['avg']),
      'slugging': _number(v['slg']),
      'onbase': _number(v['obp']),
    };
  }

  static List<List<T>> chunksOf<T>(List<T> values, int size) {
    if (size <= 0) throw ArgumentError.value(size, 'size');
    return [
      for (var start = 0; start < values.length; start += size)
        values.sublist(start, math.min(start + size, values.length)),
    ];
  }

  Future<int> _loadNpbStandings(NpbYearPage page) {
    if (page.standings.isEmpty) {
      throw StateError('NPB standings table was not found for ${page.year}');
    }
    return _transaction((conn) async {
      var count = 0;
      for (var i = 0; i < page.standings.length; i++) {
        final row = page.standings[i];
        final key = npbTeamSourceKey(row.teamName);
        final teamId = await _upsertTeam(
          conn,
          sourceKey: key,
          externalId: key,
          fullName: row.teamName,
          leagueId: page.leagueId,
          shortName: row.teamName,
        );
        page.teamIdsByName[row.teamName] = teamId;
        await conn.execute(
          'DELETE FROM t_stats_team WHERE year = \$1::int AND id_team = \$2::int',
          parameters: [page.year, teamId],
        );
        await conn.execute(
          '''
            INSERT INTO t_stats_team
              (year, id_team, id_league, name_team, name_shortest, code_area,
               int_rank, int_game, int_win, int_lose, int_draw, game_behind,
               flg_delete, crtat, updat)
            VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9,\$10,\$11,\$12,
                    false,now(),now())
          ''',
          parameters: [
            page.year,
            teamId,
            page.leagueId,
            row.teamName,
            row.teamName,
            null,
            i + 1,
            row.games,
            row.wins,
            row.losses,
            row.draws,
            row.gamesBack,
          ],
        );
        count++;
      }
      return count;
    });
  }

  Future<int> _loadNpbPlayers(NpbYearPage page,
      {required bool pitching}) async {
    // Standings may have been checkpointed by an earlier run; reconstruct IDs.
    await Postgres.withConnection((conn) async {
      for (final row in page.standings) {
        final key = npbTeamSourceKey(row.teamName);
        final found = await conn.execute(
          '''
            SELECT id FROM m_team
            WHERE (source_key = \$1::text AND external_id = \$2::text)
               OR (
                 COALESCE(flg_delete, false) = false
                 AND regexp_replace(COALESCE(name_full, ''), '[\\s　・･（）()]', '', 'g')
                   = \$3::text
               )
            ORDER BY
              CASE WHEN source_key = \$1::text THEN 0 ELSE 1 END,
              id
            LIMIT 1
          ''',
          parameters: [key, key, _normalizeTeam(row.teamName)],
        );
        if (found.isNotEmpty)
          page.teamIdsByName[row.teamName] = found.first[0] as int;
      }
    });
    final sourceRows = pitching ? page.pitching : page.hitting;
    final leaderRows = pitching ? page.pitchingLeaders : page.hittingLeaders;
    if (sourceRows.isEmpty && leaderRows.isEmpty) {
      return 0;
    }
    return _transaction((conn) async {
      final lines = <SeasonLine>[];
      final seen = <String>{};
      for (final row in [...sourceRows, ...leaderRows]) {
        final canonicalTeam =
            resolveNpbTeamAlias(row.teamAlias, page.teamIdsByName.keys);
        if (canonicalTeam == null) continue;
        final teamId = page.teamIdsByName[canonicalTeam];
        if (teamId == null) continue;
        final normalizedName = normalizeJapaneseName(row.playerName);
        if (normalizedName.isEmpty) continue;
        final identity = '$normalizedName|$teamId';
        if (!seen.add(identity)) continue;
        final ambiguousTeams = [...sourceRows, ...leaderRows]
            .where((candidate) =>
                normalizeJapaneseName(candidate.playerName) == normalizedName)
            .map((candidate) => resolveNpbTeamAlias(
                candidate.teamAlias, page.teamIdsByName.keys))
            .whereType<String>()
            .toSet();
        if (ambiguousTeams.length > 1) {
          // The official yearly page has no person ID. Do not merge homonyms.
          continue;
        }
        final playerId = await _upsertPlayer(
          conn,
          sourceKey: 'npb',
          externalId: 'name:$normalizedName',
          fullName: row.playerName,
          teamId: teamId,
        );
        final values = <String, dynamic>{...row.values};
        final matchingLeader = leaderRows.where((leader) =>
            normalizeJapaneseName(leader.playerName) == normalizedName);
        for (final leader in matchingLeader) {
          values.addAll(leader.values);
        }
        final line = SeasonLine(
          playerId: playerId,
          teamId: teamId,
          leagueId: page.leagueId,
          name: row.playerName,
          teamName: canonicalTeam,
          values: values,
        );
        lines.add(line);
        await _upsertCareer(conn, page.year, line, pitching: pitching);
      }
      final ids = pitching ? _pitchingStatIds : _hittingStatIds;
      await _replaceNpbRankings(
          conn, page.year, page.leagueId, ids, lines, pitching);
      return lines.length;
    });
  }

  Future<int> _loadNpbDetailedRanking(
    NpbYearPage page,
    List<NpbDetailedRankRow> rows,
    int statId,
    int leagueId,
  ) {
    return _transaction((conn) async {
      for (final standing in page.standings) {
        final key = npbTeamSourceKey(standing.teamName);
        final found = await conn.execute(
          '''
            SELECT id FROM m_team
            WHERE source_key = \$1::text AND external_id = \$2::text
            ORDER BY id LIMIT 1
          ''',
          parameters: [key, key],
        );
        if (found.isNotEmpty) {
          page.teamIdsByName[standing.teamName] = found.first[0] as int;
        }
      }
      await _deleteRankings(conn, page.year, leagueId, [statId]);
      final rankingRows = <Map<String, Object?>>[];
      for (final row in rows) {
        final canonicalTeam =
            resolveNpbTeamAlias(row.teamAlias, page.teamIdsByName.keys);
        final teamId =
            canonicalTeam == null ? null : page.teamIdsByName[canonicalTeam];
        if (teamId == null) continue;
        final normalizedName = normalizeJapaneseName(row.playerName);
        if (normalizedName.isEmpty) continue;
        final teamsForName = rows
            .where((candidate) =>
                normalizeJapaneseName(candidate.playerName) == normalizedName)
            .map((candidate) => resolveNpbTeamAlias(
                candidate.teamAlias, page.teamIdsByName.keys))
            .whereType<String>()
            .toSet();
        if (teamsForName.length > 1) continue;
        final playerId = await _upsertPlayer(
          conn,
          sourceKey: 'npb',
          externalId: 'name:$normalizedName',
          fullName: row.playerName,
          teamId: teamId,
        );
        rankingRows.add({
          'player_id': playerId,
          'team_id': teamId,
          'rank': row.rank,
          'value': row.value,
          'play_count': statId == 21 ? row.value.truncate() : 0,
        });
      }
      if (rankingRows.isEmpty) {
        throw StateError(
            'NPB ranking had no resolvable rows for ${page.year} stat $statId');
      }
      await _insertPreparedRankingRows(
          conn, page.year, leagueId, statId, rankingRows);
      return rankingRows.length;
    });
  }

  Future<int> _loadPostseasonGames(List<HistoricalGame> games) {
    return _transaction((conn) async {
      final mlbTeamIds = <String, int>{};
      final npbTeamsByName = <String, int>{};
      final npbTeamsByKey = <String, int>{};
      if (games.any((game) => game.sourceKey == 'npb')) {
        final teams = await conn.execute(
          '''
            SELECT id, name_full, source_key FROM m_team
            WHERE source_key LIKE \$1::text
              AND COALESCE(flg_delete, false) = false
          ''',
          parameters: ['npb:%'],
        );
        for (final row in teams) {
          npbTeamsByName['${row[1] ?? ''}'] = row[0] as int;
          final key = '${row[2] ?? ''}';
          if (key.isNotEmpty) npbTeamsByKey[key] = row[0] as int;
        }
      }

      var count = 0;
      for (final game in games) {
        int? homeId;
        int? awayId;
        if (game.sourceKey == 'mlb') {
          Future<int?> teamId(String externalId) async {
            if (mlbTeamIds.containsKey(externalId)) {
              return mlbTeamIds[externalId];
            }
            final found = await conn.execute(
              '''
                SELECT id FROM m_team
                WHERE source_key = \$1::text AND external_id = \$2::text
                ORDER BY id LIMIT 1
              ''',
              parameters: ['mlb', externalId],
            );
            if (found.isEmpty) return null;
            final id = found.first[0] as int;
            mlbTeamIds[externalId] = id;
            return id;
          }

          homeId = await teamId(game.homeTeamKey);
          awayId = await teamId(game.awayTeamKey);
        } else {
          homeId = resolveNpbPostseasonTeamId(
              game.homeTeamKey, npbTeamsByName, npbTeamsByKey);
          awayId = resolveNpbPostseasonTeamId(
              game.awayTeamKey, npbTeamsByName, npbTeamsByKey);
        }
        if (homeId == null || awayId == null) {
          // Current-year MLB brackets include seed placeholders
          // (e.g. "NL Higher Seed") until the series is set.
          if (game.sourceKey == 'mlb' &&
              game.start.year == DateTime.now().year) {
            continue;
          }
          throw StateError(
              'Unresolved postseason teams: ${game.awayTeamKey} @ ${game.homeTeamKey}');
        }

        final found = await conn.execute(
          '''
            SELECT id FROM t_game
            WHERE source_key = \$1::text AND external_id = \$2::text
            ORDER BY id LIMIT 1
          ''',
          parameters: [game.sourceKey, game.externalId],
        );
        Future<bool> yahooTwinExists() async {
          final yahooTwin = await conn.execute(
            '''
              SELECT id FROM t_game
              WHERE COALESCE(flg_delete, false) = false
                AND (
                  (id_team_home = \$1 AND id_team_away = \$2)
                  OR (id_team_home = \$2 AND id_team_away = \$1)
                )
                AND datetime_start::date BETWEEN (\$3::date - 1) AND (\$3::date + 1)
                AND id < 2000
              ORDER BY id
              LIMIT 1
            ''',
            parameters: [homeId, awayId, game.start],
          );
          return yahooTwin.isNotEmpty;
        }

        if (found.isEmpty) {
          if (await yahooTwinExists()) {
            continue;
          }
          await conn.execute(
            '''
              INSERT INTO t_game
                (source_key, external_id, id_team_home, id_team_away,
                 score_home, score_away, state, code_game, datetime_start,
                 flg_delete, crtat, updat)
              VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9,false,now(),now())
            ''',
            parameters: [
              game.sourceKey,
              game.externalId,
              homeId,
              awayId,
              game.scoreHome,
              game.scoreAway,
              game.state,
              game.codeGame,
              game.start,
            ],
          );
        } else {
          if (await yahooTwinExists()) {
            await conn.execute(
              'UPDATE t_game SET flg_delete = true, updat = now() WHERE id = \$1',
              parameters: [found.first[0]],
            );
            continue;
          }
          await conn.execute(
            '''
              UPDATE t_game SET id_team_home = \$1, id_team_away = \$2,
                score_home = \$3, score_away = \$4, state = \$5,
                code_game = \$6, datetime_start = \$7,
                flg_delete = false, updat = now()
              WHERE id = \$8
            ''',
            parameters: [
              homeId,
              awayId,
              game.scoreHome,
              game.scoreAway,
              game.state,
              game.codeGame,
              game.start,
              found.first[0],
            ],
          );
        }
        count++;
      }
      return count;
    });
  }

  static List<HistoricalGame> parseMlbPostseasonSchedule(
    Map<String, dynamic> source, {
    required int expectedYear,
  }) {
    const codeByType = {'F': 'WC', 'D': 'DS', 'L': 'LCS', 'W': 'WS'};
    final result = <HistoricalGame>[];
    for (final date in _maps(source['dates'])) {
      for (final game in _maps(date['games'])) {
        final season = _integer(game['season']);
        if (season > 0 && season != expectedYear) {
          throw StateError(
              'MLB postseason season mismatch: expected $expectedYear, got $season');
        }
        final code = codeByType[_text(game['gameType'])];
        final gamePk = _integer(game['gamePk']);
        final teams = _map(game['teams']);
        final home = _map(teams['home']);
        final away = _map(teams['away']);
        final homeTeam = _map(home['team']);
        final awayTeam = _map(away['team']);
        final homeKey = _integer(homeTeam['id']);
        final awayKey = _integer(awayTeam['id']);
        final start = DateTime.tryParse(_text(game['gameDate']));
        if (code == null ||
            gamePk <= 0 ||
            homeKey <= 0 ||
            awayKey <= 0 ||
            start == null) {
          continue;
        }
        final abstractState =
            _text(_map(game['status'])['abstractGameState']).toLowerCase();
        final detailedState =
            _text(_map(game['status'])['detailedState']).toLowerCase();
        final state = abstractState == 'final'
            ? '試合終了'
            : detailedState.contains('cancel') ||
                    detailedState.contains('postpon')
                ? '試合中止'
                : abstractState == 'live'
                    ? '試合中'
                    : '試合前';
        result.add(HistoricalGame(
          sourceKey: 'mlb',
          externalId: '$gamePk',
          codeGame: code,
          start: start,
          homeTeamKey: '$homeKey',
          awayTeamKey: '$awayKey',
          scoreHome: home['score'] == null ? null : _integer(home['score']),
          scoreAway: away['score'] == null ? null : _integer(away['score']),
          state: state,
        ));
      }
    }
    return result;
  }

  static List<HistoricalGame> parseNpbJapanSeries(
    String source, {
    required int expectedYear,
    required String sourceUrl,
  }) {
    validateNpbSeason(source, expectedYear);
    final document = html_parser.parse(source);
    final games = <HistoricalGame>[];
    for (final block in document.querySelectorAll('.scoreMainList')) {
      final number = block.querySelector('.scoreNumber')?.text.trim() ?? '';
      final dateText = block.querySelector('.scoreDate')?.text.trim() ?? '';
      final dateMatch = RegExp(r'(\d{1,2})月\s*(\d{1,2})日').firstMatch(dateText);
      // Nested wrapper <tr>s also contain .scoreTeam descendants. Only the
      // inning table's direct team cells are the visitor/home line score.
      final teamRows = block.querySelectorAll('tr').where((row) {
        return row.children.any((cell) => cell.classes.contains('scoreTeam')) &&
            row.children.any((cell) => cell.classes.contains('scoreTotal'));
      }).toList();
      if (dateMatch == null || teamRows.length != 2) continue;
      final info = block.querySelector('.scoreInfomation')?.text ?? '';
      final timeMatch = RegExp(r'開始\s*(\d{1,2}):(\d{2})').firstMatch(info);
      final month = int.parse(dateMatch.group(1)!);
      final day = int.parse(dateMatch.group(2)!);
      final start = DateTime(
        expectedYear,
        month,
        day,
        timeMatch == null ? 0 : int.parse(timeMatch.group(1)!),
        timeMatch == null ? 0 : int.parse(timeMatch.group(2)!),
      );
      // Official line-score rows are visitor first, home second.
      final awayName = teamRows[0].querySelector('.scoreTeam')!.text.trim();
      final homeName = teamRows[1].querySelector('.scoreTeam')!.text.trim();
      final awayScore =
          int.tryParse(teamRows[0].querySelector('.scoreTotal')!.text.trim());
      final homeScore =
          int.tryParse(teamRows[1].querySelector('.scoreTotal')!.text.trim());
      games.add(HistoricalGame(
        sourceKey: 'npb',
        externalId: 'js:$expectedYear:${number.replaceAll(RegExp(r'\s+'), '')}',
        codeGame: 'JS',
        start: start,
        homeTeamKey: homeName,
        awayTeamKey: awayName,
        scoreHome: homeScore,
        scoreAway: awayScore,
        state: homeScore == null || awayScore == null ? '試合前' : '試合終了',
      ));
    }
    return games;
  }

  static List<HistoricalGame> parseNpbClimaxCalendar(
    String source, {
    required int expectedYear,
    required String sourceUrl,
  }) {
    validateNpbSeason(source, expectedYear);
    final document = html_parser.parse(source);
    final games = <HistoricalGame>[];
    for (final cell in document.querySelectorAll('.stschedule')) {
      final container = cell.querySelector('.stvsteam');
      if (container == null) continue;
      String? code;
      for (final child in container.children) {
        final heading = child.text.replaceAll(RegExp(r'\s+'), '');
        if (child.classes.contains('tescheaten')) {
          // 2007-2010 official calendars say 第1S/第2S; later years use
          // ファースト/ファイナル. Japan Series cells are imported separately.
          code = (heading.contains('ファイナル') || heading.contains('第2S'))
              ? 'CSF'
              : (heading.contains('ファースト') || heading.contains('第1S'))
                  ? 'CS1'
                  : null;
          continue;
        }
        if (code == null) continue;
        final link = child.querySelector('a');
        final href = link?.attributes['href'] ?? '';
        final text = link?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
        final dateMatch = RegExp(r's((?:19|20)\d{6})').firstMatch(href);
        final scoreMatch = RegExp(r'^(.+?)\s+(\d+|\*)\s*-\s*(\d+|\*)\s+(.+)$')
            .firstMatch(text);
        if (dateMatch == null || scoreMatch == null) continue;
        final ymd = dateMatch.group(1)!;
        final year = int.parse(ymd.substring(0, 4));
        if (year != expectedYear) {
          throw StateError(
              'NPB Climax season mismatch: expected $expectedYear, got $year');
        }
        final homeScore = int.tryParse(scoreMatch.group(2)!);
        final awayScore = int.tryParse(scoreMatch.group(3)!);
        final start = DateTime(
          year,
          int.parse(ymd.substring(4, 6)),
          int.parse(ymd.substring(6, 8)),
        );
        final scoresAvailable = homeScore != null && awayScore != null;
        games.add(HistoricalGame(
          sourceKey: 'npb',
          externalId: Uri.parse(href).pathSegments.last,
          codeGame: code,
          start: start,
          homeTeamKey: scoreMatch.group(1)!.trim(),
          awayTeamKey: scoreMatch.group(4)!.trim(),
          scoreHome: homeScore,
          scoreAway: awayScore,
          state: !scoresAvailable
              ? '試合前'
              : start.isBefore(DateTime.now())
                  ? '試合終了'
                  : '試合中',
        ));
      }
    }
    return games;
  }

  Future<T> _transaction<T>(Future<T> Function(Connection conn) callback) {
    return Postgres.withConnection((conn) async {
      await conn.execute('BEGIN');
      try {
        final result = await callback(conn);
        await conn.execute('COMMIT');
        return result;
      } catch (error, stack) {
        try {
          await conn.execute('ROLLBACK');
        } catch (_) {
          // The pool will discard this connection after the original error.
        }
        Error.throwWithStackTrace(error, stack);
      }
    });
  }

  Future<int> _upsertTeam(
    Connection conn, {
    required String sourceKey,
    required String externalId,
    required String fullName,
    required int leagueId,
    required String shortName,
  }) async {
    final cacheKey = '$sourceKey|$externalId';
    final cached = _teamIdCache[cacheKey];
    if (cached != null) return cached;
    var found = await conn.execute(
      '''
        SELECT id FROM m_team
        WHERE source_key = \$1::text AND external_id = \$2::text
        ORDER BY id LIMIT 1
      ''',
      parameters: [sourceKey, externalId],
    );
    if (found.isEmpty && sourceKey.startsWith('npb:')) {
      found = await conn.execute(
        '''
          SELECT id FROM m_team
          WHERE COALESCE(flg_delete, false) = false
            AND (
              regexp_replace(COALESCE(name_full, ''), '[\\s　・･（）()]', '', 'g')
                = \$1::text
              OR regexp_replace(COALESCE(name_short, ''), '[\\s　・･（）()]', '', 'g')
                = \$1::text
            )
          ORDER BY id LIMIT 2
        ''',
        parameters: [_normalizeTeam(fullName)],
      );
    }
    if (found.length == 1) {
      final id = found.first[0] as int;
      await conn.execute(
        '''
          UPDATE m_team
          SET source_key = COALESCE(source_key, \$1::text),
              external_id = COALESCE(external_id, \$2::text),
              flg_delete = false, updat = now()
          WHERE id = \$3::int
        ''',
        parameters: [sourceKey, externalId, id],
      );
      _teamIdCache[cacheKey] = id;
      return id;
    }
    final inserted = await conn.execute(
      '''
        INSERT INTO m_team
          (name_shortest, name_short, name_full, id_league, color_font,
           color_back, source_key, external_id, flg_delete, crtat, updat)
        VALUES (\$1,\$2,\$3,\$4,'','',\$5,\$6,false,now(),now())
        RETURNING id
      ''',
      parameters: [
        shortName,
        shortName,
        fullName,
        leagueId,
        sourceKey,
        externalId
      ],
    );
    final id = inserted.first[0] as int;
    _teamIdCache[cacheKey] = id;
    return id;
  }

  Future<int> _upsertPlayer(
    Connection conn, {
    required String sourceKey,
    required String externalId,
    required String fullName,
    required int teamId,
    DateTime? birthDate,
  }) async {
    final cacheKey = '$sourceKey|$externalId';
    var existingId = _playerIdCache[cacheKey];
    if (existingId == null) {
      final found = await conn.execute(
        '''
          SELECT id FROM m_player
          WHERE source_key = \$1::text AND external_id = \$2::text
          ORDER BY id LIMIT 1
        ''',
        parameters: [sourceKey, externalId],
      );
      if (found.isNotEmpty) existingId = found.first[0] as int;
    }
    final parts = splitPlayerName(fullName);
    if (existingId == null && sourceKey == 'npb') {
      final byName = await conn.execute(
        '''
          SELECT id FROM m_player
          WHERE COALESCE(flg_delete, false) = false
            AND (
              regexp_replace(COALESCE(name_full, ''), '[\\s　・･]', '', 'g')
                = \$1::text
              OR (
                regexp_replace(COALESCE(name_last, ''), '[\\s　・･]', '', 'g')
                  = \$2::text
                AND regexp_replace(COALESCE(name_first, ''), '[\\s　・･]', '', 'g')
                  = \$3::text
                AND \$2::text <> ''
                AND \$3::text <> ''
              )
            )
          ORDER BY id LIMIT 2
        ''',
        parameters: [
          normalizeJapaneseName(fullName),
          normalizeJapaneseName(parts.$1),
          normalizeJapaneseName(parts.$2),
        ],
      );
      if (byName.length == 1) existingId = byName.first[0] as int;
    }
    if (existingId != null) {
      await conn.execute(
        '''
          UPDATE m_player SET name_full = \$1::text, name_last = \$2::text,
            name_first = \$3::text,
            date_birth = COALESCE(\$4::timestamp, date_birth),
            source_key = COALESCE(source_key, \$6::text),
            external_id = COALESCE(external_id, \$7::text),
            flg_delete = false, updat = now()
          WHERE id = \$5::int
        ''',
        parameters: [
          fullName,
          parts.$1,
          parts.$2,
          birthDate,
          existingId,
          sourceKey,
          externalId,
        ],
      );
      _playerIdCache[cacheKey] = existingId;
      return existingId;
    }
    final inserted = await conn.execute(
      '''
        INSERT INTO m_player
          (name_last, name_first, name_middle, name_full, id_team, date_birth,
           source_key, external_id, flg_delete, crtat, updat)
        VALUES (\$1,\$2,'',\$3,\$4,\$5,\$6,\$7,false,now(),now())
        RETURNING id
      ''',
      parameters: [
        parts.$1,
        parts.$2,
        fullName,
        teamId,
        birthDate,
        sourceKey,
        externalId,
      ],
    );
    final id = inserted.first[0] as int;
    _playerIdCache[cacheKey] = id;
    return id;
  }

  Future<void> _upsertCareer(
    Connection conn,
    int year,
    SeasonLine line, {
    required bool pitching,
  }) async {
    final found = await conn.execute(
      '''
        SELECT id FROM m_player_career
        WHERE id_player = \$1::int AND int_year = \$2::int AND id_team = \$3::int
          AND COALESCE(flg_delete, false) = false
        ORDER BY id LIMIT 1
      ''',
      parameters: [line.playerId, year, line.teamId],
    );
    final v = line.values;
    if (found.isEmpty) {
      await conn.execute(
        '''
          INSERT INTO m_player_career
            (id_player, int_year, id_team, int_games, flg_delete, crtat, updat)
          VALUES (\$1,\$2,\$3,\$4,false,now(),now())
        ''',
        parameters: [
          line.playerId,
          year,
          line.teamId,
          _integer(v[pitching ? 'gamesPitched' : 'gamesPlayed']),
        ],
      );
    }
    if (pitching) {
      await conn.execute(
        '''
          UPDATE m_player_career SET
            int_pitching = \$1, int_win = \$2, int_lose = \$3, int_save = \$4,
            int_hold = \$5, int_hold_point = \$6, int_complete_game = \$7,
            int_shutout = \$8, double_average_win = \$9, int_batter = \$10,
            double_inning = \$11, int_hit_pitcher = \$12,
            int_homerun_pitcher = \$13, int_four_pitcher = \$14,
            int_dead_pitcher = \$15, int_strike_out_pitcher = \$16,
            int_wild_pitch = \$17, int_balk = \$18, int_runs_allowed = \$19,
            int_earned_runds = \$20, double_average_earned_runs = \$21,
            updat = now()
          WHERE id_player = \$22 AND int_year = \$23 AND id_team = \$24
            AND COALESCE(flg_delete, false) = false
        ''',
        parameters: [
          _integer(v['gamesPitched']),
          _integer(v['wins']),
          _integer(v['losses']),
          _integer(v['saves']),
          _integer(v['holds']),
          _integer(v['holdPoints']),
          _integer(v['completeGames']),
          _integer(v['shutouts']),
          _number(v['winPercentage']),
          _integer(v['battersFaced']),
          baseballInnings(_text(v['inningsPitched'])),
          _integer(v['hits']),
          _integer(v['homeRuns']),
          _integer(v['baseOnBalls']),
          _integer(v['hitBatsmen']),
          _integer(v['strikeOuts']),
          _integer(v['wildPitches']),
          _integer(v['balks']),
          _integer(v['runs']),
          _integer(v['earnedRuns']),
          _number(v['era']),
          line.playerId,
          year,
          line.teamId,
        ],
      );
    } else {
      await conn.execute(
        '''
          UPDATE m_player_career SET
            int_games = \$1, int_appearance = \$2, int_batting = \$3,
            int_runs = \$4, int_rbi = \$5, int_hit1 = \$6, int_hit2 = \$7,
            int_hit3 = \$8, int_homerun = \$9, int_total_bases = \$10,
            int_steal_base = \$11, int_steal_caught = \$12,
            int_sacrifice = \$13, int_four_batting = \$14,
            int_dead_batting = \$15, int_strike_out_batting = \$16,
            int_double_play = \$17, double_average_batting = \$18,
            double_average_slugging = \$19, double_average_onbase = \$20,
            updat = now()
          WHERE id_player = \$21 AND int_year = \$22 AND id_team = \$23
            AND COALESCE(flg_delete, false) = false
        ''',
        parameters: [
          _integer(v['gamesPlayed']),
          _integer(v['plateAppearances']),
          _integer(v['atBats']),
          _integer(v['runs']),
          _integer(v['rbi']),
          _integer(v['hits']),
          _integer(v['doubles']),
          _integer(v['triples']),
          _integer(v['homeRuns']),
          _integer(v['totalBases']),
          _integer(v['stolenBases']),
          _integer(v['caughtStealing']),
          _integer(v['sacBunts']),
          _integer(v['baseOnBalls']),
          _integer(v['hitByPitch']),
          _integer(v['strikeOuts']),
          _integer(v['groundIntoDoublePlay']),
          _number(v['avg']),
          _number(v['slg']),
          _number(v['obp']),
          line.playerId,
          year,
          line.teamId,
        ],
      );
    }
  }

  Future<void> _replaceNpbRankings(
    Connection conn,
    int year,
    int leagueId,
    List<int> statIds,
    List<SeasonLine> lines,
    bool pitching,
  ) async {
    await _deleteRankings(conn, year, leagueId, statIds);
    // Qualified tables accurately rank average/ERA. Other counting rankings are
    // inserted only when the league-leaders table supplied that exact category.
    for (final statId in statIds) {
      if (pitching &&
          statId != 9 &&
          !lines.any((l) => l.values.containsKey('leader:$statId'))) {
        continue;
      }
      if (!pitching &&
          statId != 1 &&
          !lines.any((l) => l.values.containsKey('leader:$statId'))) {
        continue;
      }
      final candidates = <RankValue>[];
      for (final line in lines) {
        final leaderValue = line.values['leader:$statId'];
        final value = leaderValue == null
            ? statValue(statId, line.values)
            : _number(leaderValue);
        if (value == null) continue;
        if (statId != 1 && statId != 9 && leaderValue == null) continue;
        candidates
            .add(RankValue(line, value, countForStat(statId, line.values)));
      }
      await _insertRankValues(conn, year, leagueId, statId, candidates);
    }
  }

  Future<void> _deleteRankings(
    Connection conn,
    int year,
    int leagueId,
    List<int> statIds,
  ) async {
    await conn.execute(
      '''
        DELETE FROM t_stats_player
        WHERE int_year = \$1::int AND id_league = \$2::int
          AND id_stats = ANY(\$3::int[])
      ''',
      parameters: [year, leagueId, statIds],
    );
  }

  Future<void> _insertRankValues(
    Connection conn,
    int year,
    int leagueId,
    int statId,
    List<RankValue> candidates,
  ) async {
    final lowerIsBetter = const {9, 13, 14, 15}.contains(statId);
    final rows = prepareRankingRows(candidates, lowerIsBetter: lowerIsBetter);
    await _insertPreparedRankingRows(conn, year, leagueId, statId, rows);
  }

  Future<void> _insertPreparedRankingRows(
    Connection conn,
    int year,
    int leagueId,
    int statId,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return;
    await conn.execute(
      '''
        INSERT INTO t_stats_player
          (int_year, id_league, id_stats, id_player, id_team, int_rank,
           stats, cnt_play, flg_delete, crtat, updat)
        SELECT \$1::int, \$2::int, \$3::int, data.player_id, data.team_id,
               data.rank, data.value, data.play_count, false, now(), now()
        FROM jsonb_to_recordset(\$4::jsonb) AS data(
          player_id integer, team_id integer, rank integer,
          value numeric, play_count integer
        )
      ''',
      parameters: [year, leagueId, statId, jsonEncode(rows)],
    );
  }

  static List<Map<String, Object?>> prepareRankingRows(
    List<RankValue> candidates, {
    required bool lowerIsBetter,
  }) {
    candidates.sort((a, b) {
      final compared = lowerIsBetter
          ? a.value.compareTo(b.value)
          : b.value.compareTo(a.value);
      return compared != 0 ? compared : b.count.compareTo(a.count);
    });
    num? previous;
    var rank = 0;
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      if (previous == null || candidate.value != previous) rank = i + 1;
      previous = candidate.value;
      rows.add({
        'player_id': candidate.line.playerId,
        'team_id': candidate.line.teamId,
        'rank': rank,
        'value': candidate.value,
        'play_count': candidate.count,
      });
    }
    return rows;
  }

  static double? statValue(int id, Map<String, dynamic> v) {
    double? present(String key) => v.containsKey(key) ? _number(v[key]) : null;
    switch (id) {
      case 1:
        return present('avg');
      case 2:
        return present('hits');
      case 3:
        return present('homeRuns');
      case 4:
        return present('rbi');
      case 5:
        return present('stolenBases');
      case 6:
        return present('obp');
      case 7:
        return present('slg');
      case 8:
        return present('ops');
      case 9:
        return present('era');
      case 10:
        return present('wins');
      case 11:
        return present('strikeOuts');
      case 12:
        return present('strikeoutsPer9Inn') ??
            _perNine(v['strikeOuts'], v['inningsPitched']);
      case 13:
        return present('walksPer9Inn') ??
            _perNine(v['baseOnBalls'], v['inningsPitched']);
      case 14:
        return present('avg');
      case 15:
        return present('whip');
      case 16:
        final starts = _integer(v['gamesStarted']);
        return starts > 0 && v.containsKey('qualityStarts')
            ? _integer(v['qualityStarts']) * 100 / starts
            : null;
      case 17:
        return present('holds');
      case 18:
        return present('holdPoints');
      case 19:
        return present('saves');
      case 20:
        return present('plateAppearances');
      case 21:
        return v.containsKey('inningsPitched')
            ? baseballInnings(_text(v['inningsPitched']))
            : null;
      case 22:
        final attempts =
            _integer(v['stolenBases']) + _integer(v['caughtStealing']);
        return attempts > 0
            ? _integer(v['stolenBases']) * 100 / attempts
            : null;
    }
    return null;
  }

  static int countForStat(int id, Map<String, dynamic> values) {
    if (id == 22) {
      return _integer(values['stolenBases']) +
          _integer(values['caughtStealing']);
    }
    if (id >= 9 && id <= 19 || id == 21) {
      return baseballInnings(_text(values['inningsPitched'])).truncate();
    }
    return _integer(values['plateAppearances']);
  }

  static bool qualifiesForMlbRate(
    int statId,
    Map<String, dynamic> values,
    int teamGames,
  ) {
    if (!const {1, 6, 7, 8, 9, 12, 13, 14, 15, 16, 22}.contains(statId)) {
      return true;
    }
    if (teamGames <= 0) return false;
    if (statId == 22) {
      final attempts =
          _integer(values['stolenBases']) + _integer(values['caughtStealing']);
      return attempts >= teamGames * 0.1;
    }
    if (statId == 16) {
      return _integer(values['gamesStarted']) >= teamGames * 0.2;
    }
    if (statId >= 9 && statId <= 15) {
      return baseballInnings(_text(values['inningsPitched'])) >= teamGames;
    }
    return _integer(values['plateAppearances']) >= teamGames * 3.1;
  }

  static double? _perNine(dynamic count, dynamic innings) {
    final ip = baseballInnings(_text(innings));
    return ip > 0 ? _integer(count) * 9 / ip : null;
  }

  static double baseballInnings(String raw) {
    final parts = raw.trim().split('.');
    final whole = int.tryParse(parts.first) ?? 0;
    if (parts.length == 1) return whole.toDouble();
    final outs = int.tryParse(parts[1]) ?? 0;
    return whole + math.min(outs, 2) / 3;
  }

  static (String, String) splitPlayerName(String fullName) {
    final normalized = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final pieces = normalized.split(' ');
    if (pieces.length < 2) return (normalized, '');
    if (_containsJapanese(normalized)) {
      return (pieces.first, pieces.sublist(1).join(' '));
    }
    return (pieces.last, pieces.sublist(0, pieces.length - 1).join(' '));
  }

  static bool _containsJapanese(String value) =>
      RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(value);

  static String normalizeJapaneseName(String value) => value
      .replaceAll(RegExp(r'[\s\u3000・･]'), '')
      .replaceAll('髙', '高')
      .replaceAll('﨑', '崎')
      .trim();

  /// Dart http latin1-decoded UTF-8 leaves each source byte as a code unit.
  static String? repairUtf8Mojibake(String value) {
    if (value.isEmpty) return null;
    final units = value.codeUnits;
    if (units.any((unit) => unit > 0xFF) || units.every((unit) => unit < 0x80)) {
      return null;
    }
    try {
      final repaired = utf8.decode(units);
      if (repaired == value || !_containsJapanese(repaired)) return null;
      return repaired;
    } catch (_) {
      return null;
    }
  }

  static String _normalizeTeam(String value) => value
      .replaceAll(RegExp(r'[\s\u3000・･]'), '')
      .replaceAll(RegExp(r'[（）()]'), '')
      .replaceAll('讀賣', '読売')
      .trim();

  static String npbTeamSourceKey(String exactOfficialFullName) =>
      npbFranchiseKey(exactOfficialFullName) ??
      'npb:team:${_normalizeTeam(exactOfficialFullName)}';

  static String? npbFranchiseKey(String officialName) {
    final normalized = _normalizeTeam(officialName);
    const franchises = <String, String>{
      '東京巨人': 'npb:franchise:giants',
      '東京巨人軍': 'npb:franchise:giants',
      '巨人軍': 'npb:franchise:giants',
      '読売ジャイアンツ': 'npb:franchise:giants',
      '東京読売ジャイアンツ': 'npb:franchise:giants',
      '巨人': 'npb:franchise:giants',
      '大阪タイガース': 'npb:franchise:tigers',
      '阪神タイガース': 'npb:franchise:tigers',
      'タイガース': 'npb:franchise:tigers',
      '阪神': 'npb:franchise:tigers',
      '名古屋': 'npb:franchise:dragons',
      '名古屋軍': 'npb:franchise:dragons',
      '産業軍': 'npb:franchise:dragons',
      '中部日本': 'npb:franchise:dragons',
      '中部日本ドラゴンズ': 'npb:franchise:dragons',
      '名古屋ドラゴンズ': 'npb:franchise:dragons',
      '中日ドラゴンズ': 'npb:franchise:dragons',
      '中日': 'npb:franchise:dragons',
      '国鉄スワローズ': 'npb:franchise:swallows',
      'サンケイスワローズ': 'npb:franchise:swallows',
      'サンケイアトムズ': 'npb:franchise:swallows',
      'アトムズ': 'npb:franchise:swallows',
      'ヤクルトアトムズ': 'npb:franchise:swallows',
      'ヤクルトスワローズ': 'npb:franchise:swallows',
      '東京ヤクルトスワローズ': 'npb:franchise:swallows',
      'ヤクルト': 'npb:franchise:swallows',
      '大洋ホエールズ': 'npb:franchise:baystars',
      '大洋': 'npb:franchise:baystars',
      '大洋松竹ロビンス': 'npb:franchise:baystars',
      '横浜大洋ホエールズ': 'npb:franchise:baystars',
      '横浜ベイスターズ': 'npb:franchise:baystars',
      '横浜DeNAベイスターズ': 'npb:franchise:baystars',
      'DeNA': 'npb:franchise:baystars',
      '広島カープ': 'npb:franchise:carp',
      '広島東洋カープ': 'npb:franchise:carp',
      '広島東洋': 'npb:franchise:carp',
      '広島': 'npb:franchise:carp',
      '南海ホークス': 'npb:franchise:hawks',
      '南海': 'npb:franchise:hawks',
      '福岡ダイエーホークス': 'npb:franchise:hawks',
      'ダイエーホークス': 'npb:franchise:hawks',
      '福岡ダイエー': 'npb:franchise:hawks',
      'ダイエー': 'npb:franchise:hawks',
      '福岡ソフトバンクホークス': 'npb:franchise:hawks',
      'ソフトバンク': 'npb:franchise:hawks',
      '西鉄ライオンズ': 'npb:franchise:lions',
      '西鉄': 'npb:franchise:lions',
      '太平洋クラブライオンズ': 'npb:franchise:lions',
      'クラウンライターライオンズ': 'npb:franchise:lions',
      '西武ライオンズ': 'npb:franchise:lions',
      '埼玉西武ライオンズ': 'npb:franchise:lions',
      '西武': 'npb:franchise:lions',
      '東急フライヤーズ': 'npb:franchise:fighters',
      '急映フライヤーズ': 'npb:franchise:fighters',
      '東映': 'npb:franchise:fighters',
      '東映フライヤーズ': 'npb:franchise:fighters',
      '日拓ホームフライヤーズ': 'npb:franchise:fighters',
      '日本ハムファイターズ': 'npb:franchise:fighters',
      '北海道日本ハムファイターズ': 'npb:franchise:fighters',
      '日本ハム': 'npb:franchise:fighters',
      '阪急': 'npb:franchise:buffaloes',
      '阪急ブレーブス': 'npb:franchise:buffaloes',
      'オリックスブレーブス': 'npb:franchise:buffaloes',
      'オリックスブルーウェーブ': 'npb:franchise:buffaloes',
      'オリックスバファローズ': 'npb:franchise:buffaloes',
      'オリックス': 'npb:franchise:buffaloes',
      '近鉄パールス': 'npb:franchise:kintetsu',
      '近鉄バファロー': 'npb:franchise:kintetsu',
      '近鉄バファローズ': 'npb:franchise:kintetsu',
      '大阪近鉄バファローズ': 'npb:franchise:kintetsu',
      '大阪近鉄': 'npb:franchise:kintetsu',
      '近鉄': 'npb:franchise:kintetsu',
      '大東京': 'npb:franchise:robins',
      '大東京軍': 'npb:franchise:robins',
      'ライオン軍': 'npb:franchise:robins',
      '朝日軍': 'npb:franchise:robins',
      'パシフィック': 'npb:franchise:robins',
      '太陽ロビンス': 'npb:franchise:robins',
      '松竹ロビンス': 'npb:franchise:robins',
      '松竹': 'npb:franchise:robins',
      '毎日オリオンズ': 'npb:franchise:marines',
      '毎日': 'npb:franchise:marines',
      '毎日大映オリオンズ': 'npb:franchise:marines',
      '大毎オリオンズ': 'npb:franchise:marines',
      '大毎': 'npb:franchise:marines',
      '東京オリオンズ': 'npb:franchise:marines',
      'ロッテオリオンズ': 'npb:franchise:marines',
      '千葉ロッテマリーンズ': 'npb:franchise:marines',
      'ロッテ': 'npb:franchise:marines',
      '東北楽天ゴールデンイーグルス': 'npb:franchise:eagles',
      '楽天': 'npb:franchise:eagles',
    };
    return franchises[normalized];
  }

  static String? resolveNpbTeamAlias(String alias, Iterable<String> fullNames) {
    final normalizedAlias = _normalizeTeam(alias);
    if (normalizedAlias.isEmpty) return null;
    final names = fullNames.toList();
    final exact = names
        .where((full) => _normalizeTeam(full) == normalizedAlias)
        .toList();
    if (exact.length == 1) return exact.single;
    if (exact.length > 1) return null;
    const known = <String, String>{
      '巨人': '読売ジャイアンツ',
      '阪神': '阪神タイガース',
      'DeNA': '横浜DeNAベイスターズ',
      '横浜': '横浜DeNAベイスターズ',
      '広島': '広島東洋カープ',
      '中日': '中日ドラゴンズ',
      'ヤクルト': '東京ヤクルトスワローズ',
      'ソフトバンク': '福岡ソフトバンクホークス',
      '日本ハム': '北海道日本ハムファイターズ',
      'ロッテ': '千葉ロッテマリーンズ',
      '楽天': '東北楽天ゴールデンイーグルス',
      'オリックス': 'オリックス・バファローズ',
      '西武': '埼玉西武ライオンズ',
      'タイガース': '阪神タイガース',
      '金鯱': '名古屋金鯱',
      'セネタース': '東京セネタース',
      '阪急': '阪急',
      '名古屋': '名古屋',
      '巨': '読売ジャイアンツ',
      '神': '阪神タイガース',
      'デ': '横浜DeNAベイスターズ',
      '広': '広島東洋カープ',
      '中': '中日ドラゴンズ',
      'ヤ': '東京ヤクルトスワローズ',
      'ソ': '福岡ソフトバンクホークス',
      '日': '北海道日本ハムファイターズ',
      'ロ': '千葉ロッテマリーンズ',
      '楽': '東北楽天ゴールデンイーグルス',
      'オ': 'オリックス・バファローズ',
      '西': '埼玉西武ライオンズ',
    };
    final aliasKey = npbFranchiseKey(normalizedAlias) ??
        npbFranchiseKey(known[normalizedAlias] ?? '');
    if (aliasKey != null && aliasKey.isNotEmpty) {
      final byFranchise = names
          .where((full) => npbFranchiseKey(full) == aliasKey)
          .toList();
      if (byFranchise.length == 1) return byFranchise.single;
    }
    final exactMapped = known[normalizedAlias];
    if (exactMapped != null) {
      final mapped = names
          .where((full) => _normalizeTeam(full) == _normalizeTeam(exactMapped))
          .toList();
      if (mapped.length == 1) return mapped.single;
    }
    if (normalizedAlias.length < 2) return null;
    final contains = names
        .where((full) => _normalizeTeam(full).contains(normalizedAlias))
        .toList();
    return contains.length == 1 ? contains.single : null;
  }

  /// Japan Series line scores use short labels (広島東洋, 阪　急). Resolve
  /// through franchise source_key first so later name changes still match.
  static int? resolveNpbPostseasonTeamId(
    String alias,
    Map<String, int> byName,
    Map<String, int> byKey,
  ) {
    final bySource = byKey[npbTeamSourceKey(alias)];
    if (bySource != null) return bySource;
    final resolved = resolveNpbTeamAlias(alias, byName.keys);
    return resolved == null ? null : byName[resolved];
  }

  static String mlbDivisionCode(String name) {
    final upper = name.toUpperCase();
    if (upper.contains('EAST')) return 'EAST';
    if (upper.contains('CENTRAL')) return 'CENTER';
    if (upper.contains('WEST')) return 'WEST';
    return '';
  }

  /// Some 19th-century seasons (notably 1892) have official teams/W-L in
  /// team pitching stats even though /standings returns no records.
  static List<Map<String, dynamic>> standingsFromTeamPitching(
    Map<String, dynamic> json,
    int year,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final stat in _maps(json['stats'])) {
      for (final split in _maps(stat['splits'])) {
        final returnedSeason = _integer(split['season']);
        if (returnedSeason > 0 && returnedSeason != year) continue;
        final team = _map(split['team']);
        final values = _map(split['stat']);
        final wins = _integer(values['wins']);
        final losses = _integer(values['losses']);
        if (_integer(team['id']) <= 0 || _text(team['name']).isEmpty) continue;
        if (wins + losses <= 0) continue;
        final games = _integer(values['gamesPlayed']);
        rows.add({
          'season': year,
          'team': team,
          'wins': wins,
          'losses': losses,
          'gamesPlayed': games > 0 ? games : wins + losses,
          'winningPercentage': _number(values['winPercentage']).toString(),
          'gamesBack': '',
        });
      }
    }
    rows.sort((a, b) {
      final byPct = _number(b['winningPercentage'])
          .compareTo(_number(a['winningPercentage']));
      if (byPct != 0) return byPct;
      return _integer(b['wins']).compareTo(_integer(a['wins']));
    });
    for (var i = 0; i < rows.length; i++) {
      rows[i]['leagueRank'] = i + 1;
    }
    return rows;
  }

  static List<NpbDetailedRankRow> parseNpbDetailedRanking(
    String source, {
    required int expectedYear,
    required int statId,
  }) {
    validateNpbSeason(source, expectedYear);
    final document = html_parser.parse(source);
    final rows = <NpbDetailedRankRow>[];
    for (final tr in document.querySelectorAll('tr')) {
      final parsed = _rankingCells(tr);
      if (parsed == null) continue;
      final (rank, player, team, rawValue) = parsed;
      final value = statId == 21
          ? baseballInnings(rawValue)
          : double.tryParse(rawValue.startsWith('.') ? '0$rawValue' : rawValue);
      if (rank <= 0 || player.isEmpty || team.isEmpty || value == null) {
        continue;
      }
      rows.add(NpbDetailedRankRow(rank, player, team, value));
    }
    return rows;
  }

  /// 2024 pages use td.stpos/stplayer/stteam/ststats. 2025+ uses
  /// tr.ststats with rank, "選手(球団)", and the stat value.
  static (int, String, String, String)? _rankingCells(Element tr) {
    final rankCell = tr.querySelector('.stpos');
    if (rankCell != null) {
      final rank = int.tryParse(rankCell.text.trim());
      if (rank == null) return null;
      final player = tr.querySelector('.stplayer')?.text.trim() ?? '';
      final team = tr
              .querySelector('.stteam')
              ?.text
              .replaceAll(RegExp(r'[（）()]'), '')
              .trim() ??
          '';
      final rawValue =
          tr.querySelector('.ststats')?.text.replaceAll(' ', '').trim() ?? '';
      return (rank, player, team, rawValue);
    }
    if (!tr.classes.contains('ststats')) return null;
    final cells = tr.children
        .where((cell) => cell.localName == 'td')
        .toList(growable: false);
    if (cells.length < 3) return null;
    final rank = int.tryParse(cells[0].text.trim());
    if (rank == null) return null;
    final nameTeam = cells[1].text.trim();
    final match =
        RegExp(r'^(.*)[（(]([^）)]+)[）)]$').firstMatch(nameTeam);
    if (match == null) return null;
    return (
      rank,
      match.group(1)!.trim(),
      match.group(2)!.trim(),
      cells[2].text.replaceAll(' ', '').trim(),
    );
  }

  static NpbYearPage combineNpbPages(List<NpbYearPage> pages) {
    if (pages.isEmpty) {
      throw ArgumentError('At least one NPB page is required');
    }
    final year = pages.first.year;
    final leagueId = pages.first.leagueId;
    if (pages.any((page) => page.year != year || page.leagueId != leagueId)) {
      throw ArgumentError('Cannot combine different NPB seasons or leagues');
    }
    final combined = NpbYearPage(year, leagueId);
    final standings = <String, NpbStanding>{};
    for (final page in pages) {
      for (final row in page.standings) {
        final key = _normalizeTeam(row.teamName);
        final previous = standings[key];
        standings[key] = previous == null
            ? row
            : NpbStanding(
                teamName: previous.teamName,
                games: previous.games + row.games,
                wins: previous.wins + row.wins,
                losses: previous.losses + row.losses,
                draws: previous.draws + row.draws,
                gamesBack: '',
              );
      }
    }
    combined.standings.addAll(standings.values);
    combined.standings.sort((a, b) {
      final wins = b.wins.compareTo(a.wins);
      return wins != 0 ? wins : a.losses.compareTo(b.losses);
    });
    combined.hitting.addAll(_combineNpbPlayerRows(
        pages.expand((page) => page.hitting).toList(),
        pitching: false));
    combined.pitching.addAll(_combineNpbPlayerRows(
        pages.expand((page) => page.pitching).toList(),
        pitching: true));
    combined.hittingLeaders.addAll(_combineNpbPlayerRows(
        pages.expand((page) => page.hittingLeaders).toList(),
        pitching: false));
    combined.pitchingLeaders.addAll(_combineNpbPlayerRows(
        pages.expand((page) => page.pitchingLeaders).toList(),
        pitching: true));
    return combined;
  }

  static List<NpbPlayerRow> _combineNpbPlayerRows(
    List<NpbPlayerRow> rows, {
    required bool pitching,
  }) {
    final grouped = <String, List<NpbPlayerRow>>{};
    for (final row in rows) {
      final key =
          '${normalizeJapaneseName(row.playerName)}|${_normalizeTeam(row.teamAlias)}';
      grouped.putIfAbsent(key, () => []).add(row);
    }
    return grouped.values.map((group) {
      if (group.length == 1) return group.single;
      final values = <String, dynamic>{};
      const additive = {
        'gamesPlayed',
        'plateAppearances',
        'atBats',
        'runs',
        'hits',
        'doubles',
        'triples',
        'homeRuns',
        'totalBases',
        'rbi',
        'stolenBases',
        'caughtStealing',
        'sacBunts',
        'baseOnBalls',
        'hitByPitch',
        'strikeOuts',
        'groundIntoDoublePlay',
        'gamesPitched',
        'wins',
        'losses',
        'saves',
        'holds',
        'holdPoints',
        'completeGames',
        'shutouts',
        'battersFaced',
        'runsAllowed',
        'earnedRuns',
      };
      for (final key in additive) {
        if (group.any((row) => row.values.containsKey(key))) {
          values[key] =
              group.fold<int>(0, (sum, row) => sum + _integer(row.values[key]));
        }
      }
      final innings = group.fold<double>(
          0,
          (sum, row) =>
              sum + baseballInnings(_text(row.values['inningsPitched'])));
      if (innings > 0) values['inningsPitched'] = innings;
      final atBats = _integer(values['atBats']);
      if (atBats > 0) values['avg'] = _integer(values['hits']) / atBats;
      if (pitching && innings > 0) {
        final weightedEra = group.fold<double>(0, (sum, row) {
          final ip = baseballInnings(_text(row.values['inningsPitched']));
          return sum + _number(row.values['era']) * ip;
        });
        values['era'] = weightedEra / innings;
      }
      for (final row in group) {
        for (final entry in row.values.entries) {
          if (entry.key.startsWith('leader:')) {
            values[entry.key] =
                _number(values[entry.key]) + _number(entry.value);
          }
        }
      }
      return NpbPlayerRow(group.first.playerName, group.first.teamAlias, values,
          phase: 'combined');
    }).toList();
  }

  static NpbYearPage parseNpbYearPage(
    String source, {
    required int year,
    required int leagueId,
    String? phase,
  }) {
    final document = html_parser.parse(source);
    final page = NpbYearPage(year, leagueId, phase: phase);
    final tables = document.querySelectorAll('table');
    for (final table in tables) {
      if (table.querySelector('table') != null) continue;
      final headers = _tableHeaders(table);
      final text = table.text.replaceAll(RegExp(r'\s+'), '');
      if (isNpbLeagueStandingsHeaders(headers)) {
        page.standings.addAll(_parseNpbStandings(table));
      } else if (headers.contains('選手') &&
          headers.any((h) => h.contains('打率'))) {
        page.hitting.addAll(_parseNpbBatting(table).map((row) => NpbPlayerRow(
            row.playerName, row.teamAlias, row.values,
            phase: phase)));
      } else if ((headers.contains('選手') || headers.contains('投手')) &&
          headers.any((h) => h.contains('防御率'))) {
        page.pitching.addAll(_parseNpbPitching(table).map((row) => NpbPlayerRow(
            row.playerName, row.teamAlias, row.values,
            phase: phase)));
      } else if (text.contains('首位打者') || text.contains('最優秀防御率')) {
        _parseNpbLeaders(table, page);
      }
    }
    if (page.standings.isEmpty) {
      page.standings.addAll(_parseNpbTournamentStandings(document, tables));
    }
    page.standings
      ..removeWhere((row) => !looksLikeTeamName(row.teamName))
      ..retainWhere((row) {
        final key = _normalizeTeam(row.teamName);
        return page.standings
                .where((other) => _normalizeTeam(other.teamName) == key)
                .reduce((a, b) => a.games >= b.games ? a : b) ==
            row;
      });
    return page;
  }

  static List<NpbStanding> _parseNpbTournamentStandings(
    Document document,
    List<Element> tables,
  ) {
    final nested = _parseNpbNestedTournamentStandings(document);
    if (nested.isNotEmpty) return nested;

    // Compatibility fallback for simplified/older markup where the team list
    // and each W-D-L table are siblings instead of nested contentsPadding.
    final totals = <String, List<int>>{};
    for (var i = 0; i < tables.length; i++) {
      final rows = tables[i].querySelectorAll('tr');
      final teamHeader = rows.indexWhere((row) {
        final cells = _cells(row);
        return cells.length == 1 && cells.single == 'チーム';
      });
      if (teamHeader < 0) continue;
      final teams = <String>[];
      for (var r = teamHeader + 1; r < rows.length; r++) {
        final cells = _cells(rows[r]);
        if (cells.length != 1) break;
        teams.add(cells.single);
      }
      if (teams.length < 2) continue;
      for (var j = i + 1; j < tables.length; j++) {
        final resultRows = tables[j].querySelectorAll('tr');
        if (resultRows.isEmpty) break;
        final heading = _cells(resultRows.first).join();
        if (!heading.contains('勝') || !heading.contains('敗')) break;
        if (resultRows.length < teams.length + 1) break;
        for (var teamIndex = 0; teamIndex < teams.length; teamIndex++) {
          final cells = _cells(resultRows[teamIndex + 1]);
          if (cells.length < 3) continue;
          final wins = cells.first == '-' ? 0 : _integer(cells.first);
          final losses = cells.last == '-' ? 0 : _integer(cells.last);
          final drawsMatch = RegExp(r'\((\d+)\)')
              .firstMatch(cells.sublist(1, cells.length - 1).join());
          final draws =
              drawsMatch == null ? 0 : int.parse(drawsMatch.group(1)!);
          final total = totals.putIfAbsent(teams[teamIndex], () => [0, 0, 0]);
          total[0] += wins;
          total[1] += losses;
          total[2] += draws;
        }
      }
    }
    return totals.entries
        .map((entry) => NpbStanding(
              teamName: entry.key,
              games: entry.value[0] + entry.value[1] + entry.value[2],
              wins: entry.value[0],
              losses: entry.value[1],
              draws: entry.value[2],
              gamesBack: '',
            ))
        .toList()
      ..sort((a, b) => b.wins.compareTo(a.wins));
  }

  static List<NpbStanding> _parseNpbNestedTournamentStandings(
      Document document) {
    final totals = <String, List<int>>{};
    for (final matrix in document.querySelectorAll('.contentsPadding')) {
      final teams = matrix
          .querySelectorAll('td.matchTeam')
          .map((cell) => cell.text.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((name) => name.isNotEmpty)
          .toList();
      if (teams.isEmpty) continue;

      final competitionTables = matrix.querySelectorAll('table').where((table) {
        final win = table.querySelector('.matchHdWin');
        final draw = table.querySelector('.matchHdTai');
        final loss = table.querySelector('.matchHdLose');
        return _nearestTable(win) == table &&
            _nearestTable(draw) == table &&
            _nearestTable(loss) == table;
      });
      for (final competition in competitionTables) {
        var teamIndex = 0;
        for (final row in competition.querySelectorAll('tr')) {
          if (teamIndex >= teams.length) break;
          final cells = row
              .querySelectorAll('td.matchStats,td.matchTop')
              .map((cell) => cell.text.replaceAll(RegExp(r'\s+'), '').trim())
              .where((text) => text.isNotEmpty)
              .toList();
          if (cells.length < 3) continue;
          final wins = cells[0] == '-' ? 0 : _integer(cells[0]);
          final drawMatch = RegExp(r'\((\d+)\)').firstMatch(cells[1]);
          final draws = drawMatch == null ? 0 : int.parse(drawMatch.group(1)!);
          final losses = cells[2] == '-' ? 0 : _integer(cells[2]);
          final total = totals.putIfAbsent(teams[teamIndex], () => [0, 0, 0]);
          total[0] += wins;
          total[1] += losses;
          total[2] += draws;
          teamIndex++;
        }
      }
    }
    return totals.entries
        .map((entry) => NpbStanding(
              teamName: entry.key,
              games: entry.value[0] + entry.value[1] + entry.value[2],
              wins: entry.value[0],
              losses: entry.value[1],
              draws: entry.value[2],
              gamesBack: '',
            ))
        .toList()
      ..sort((a, b) {
        final wins = b.wins.compareTo(a.wins);
        return wins != 0 ? wins : a.losses.compareTo(b.losses);
      });
  }

  static Element? _nearestTable(Element? element) {
    var parent = element?.parent;
    while (parent != null) {
      if (parent.localName == 'table') return parent;
      parent = parent.parent;
    }
    return null;
  }

  static List<String> _tableHeaders(Element table) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return const [];
    final headerRow = rows.reduce((a, b) =>
        a.querySelectorAll('th').length >= b.querySelectorAll('th').length
            ? a
            : b);
    return headerRow
        .querySelectorAll('th')
        .map((cell) => normalizeNpbHeader(cell.text))
        .toList();
  }

  static bool isNpbLeagueStandingsHeaders(List<String> headers) {
    if (!headers.contains('チーム')) return false;
    if (!headers.any((header) => header.contains('勝利'))) return false;
    if (!headers.any((header) => header.contains('敗北'))) return false;
    if (!headers.any((header) => header.contains('勝率'))) return false;
    if (!headers.any((header) => header.contains('引分') || header.contains('ゲーム差'))) {
      return false;
    }
    return !headers.any((header) =>
        header.contains('打率') ||
        header.contains('防御率') ||
        header.contains('選手') ||
        header.contains('本塁打') ||
        header.contains('奪三振'));
  }

  static bool looksLikeTeamName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '-' || trimmed == '--') return false;
    if (RegExp(r'^[\d.]+$').hasMatch(trimmed)) return false;
    return RegExp(r'[\u3040-\u30ff\u3400-\u9fffA-Za-z]').hasMatch(trimmed);
  }

  static String normalizeNpbHeader(String text) {
    final compact = text.replaceAll(RegExp(r'[\s\u00a0\u3000・･]'), '');
    return compact
        .replaceAll(RegExp(r'選[^手]{0,3}手'), '選手')
        .replaceAll(RegExp(r'[|｜]'), 'ー');
  }

  static List<NpbStanding> _parseNpbStandings(Element table) {
    final result = <NpbStanding>[];
    final headers = _tableHeaders(table);
    int indexWhere(String text) =>
        headers.indexWhere((header) => header.contains(text));
    for (final row in table.querySelectorAll('tr')) {
      final cells = _cells(row);
      final teamIndex = indexWhere('チーム');
      final gamesIndex = indexWhere('試合');
      final winsIndex = indexWhere('勝利');
      final lossesIndex = indexWhere('敗北');
      final drawsIndex = indexWhere('引分');
      var behindIndex = indexWhere('ゲーム差');
      if (behindIndex < 0) behindIndex = headers.indexOf('差');
      if (teamIndex < 0 ||
          gamesIndex < 0 ||
          cells.length <= gamesIndex ||
          int.tryParse(cells[gamesIndex]) == null) {
        continue;
      }
      String at(int index) =>
          index >= 0 && index < cells.length ? cells[index] : '';
      result.add(NpbStanding(
        teamName: at(teamIndex),
        games: _integer(at(gamesIndex)),
        wins: _integer(at(winsIndex)),
        losses: _integer(at(lossesIndex)),
        draws: _integer(at(drawsIndex)),
        gamesBack: at(behindIndex) == '--' ? '-' : at(behindIndex),
      ));
    }
    return result;
  }

  static List<NpbPlayerRow> _parseNpbBatting(Element table) {
    final result = <NpbPlayerRow>[];
    final headers = _tableHeaders(table);
    int index(String name) => headers.indexWhere((header) => header == name);
    String value(List<String> cells, String name) {
      final i = index(name);
      return i >= 0 && i < cells.length ? cells[i] : '';
    }

    for (final row in table.querySelectorAll('tr')) {
      final cells = _cells(row);
      if (cells.length < 4 || int.tryParse(cells[0]) == null) continue;
      final playerIndex = index('選手');
      if (playerIndex < 0 || playerIndex >= cells.length) continue;
      final identity = parseNpbPlayerIdentity(cells, playerIndex);
      if (identity == null) continue;
      result.add(NpbPlayerRow(
          identity.$1,
          identity.$2,
          {
            'avg': _number(value(cells, '打率')),
            'gamesPlayed': _integer(value(cells, '試合')),
            if (index('打席') >= 0)
              'plateAppearances': _integer(value(cells, '打席')),
            'atBats': _integer(value(cells, '打数')),
            'runs': _integer(value(cells, '得点')),
            'hits': _integer(value(cells, '安打')),
            'doubles': _integer(value(cells, '二塁打')),
            'triples': _integer(value(cells, '三塁打')),
            'homeRuns': _integer(value(cells, '本塁打')),
            if (index('塁打') >= 0) 'totalBases': _integer(value(cells, '塁打')),
            'rbi': _integer(value(cells, '打点')),
            'stolenBases': _integer(value(cells, '盗塁')),
            if (index('盗塁刺') >= 0)
              'caughtStealing': _integer(value(cells, '盗塁刺')),
            if (index('犠打') >= 0) 'sacBunts': _integer(value(cells, '犠打')),
            if (index('四球') >= 0) 'baseOnBalls': _integer(value(cells, '四球')),
            if (index('死球') >= 0) 'hitByPitch': _integer(value(cells, '死球')),
            if (index('三振') >= 0) 'strikeOuts': _integer(value(cells, '三振')),
            if (index('併殺打') >= 0)
              'groundIntoDoublePlay': _integer(value(cells, '併殺打')),
            if (index('長打率') >= 0) 'slg': _number(value(cells, '長打率')),
            if (index('出塁率') >= 0) 'obp': _number(value(cells, '出塁率')),
          },
          phase: null));
    }
    return result;
  }

  static List<NpbPlayerRow> _parseNpbPitching(Element table) {
    final result = <NpbPlayerRow>[];
    final headers = _tableHeaders(table);
    int index(String name) => headers.indexWhere((header) => header == name);
    String value(List<String> cells, String name) {
      final i = index(name);
      return i >= 0 && i < cells.length ? cells[i] : '';
    }

    for (final row in table.querySelectorAll('tr')) {
      final cells = [..._cells(row)];
      if (cells.length < 4 || int.tryParse(cells[0]) == null) continue;
      final inningsIndex = index('投球回');
      if (inningsIndex >= 0 &&
          inningsIndex + 1 < cells.length &&
          cells[inningsIndex + 1].startsWith('.')) {
        cells[inningsIndex] =
            '${cells[inningsIndex]}${cells[inningsIndex + 1]}';
        cells.removeAt(inningsIndex + 1);
      }
      var playerIndex = index('選手');
      if (playerIndex < 0) playerIndex = index('投手');
      if (playerIndex < 0 || playerIndex >= cells.length) continue;
      final identity = parseNpbPlayerIdentity(cells, playerIndex);
      if (identity == null) continue;
      result.add(NpbPlayerRow(
          identity.$1,
          identity.$2,
          {
            'era': _number(value(cells, '防御率')),
            'gamesPitched': _integer(value(cells, '登板').isNotEmpty
                ? value(cells, '登板')
                : value(cells, '試合')),
            'wins': _integer(value(cells, '勝利')),
            'losses': _integer(value(cells, '敗北')),
            'saves': _integer(value(cells, 'セーブ')),
            if (index('ホールド') >= 0) 'holds': _integer(value(cells, 'ホールド')),
            if (index('ＨＰ') >= 0) 'holdPoints': _integer(value(cells, 'ＨＰ')),
            'completeGames': _integer(value(cells, '完投')),
            'shutouts': _integer(value(cells, '完封勝')),
            'inningsPitched': value(cells, '投球回').replaceAll(' ', ''),
            if (index('打者') >= 0) 'battersFaced': _integer(value(cells, '打者')),
            'strikeOuts': _integer(value(cells, '奪三振').isNotEmpty
                ? value(cells, '奪三振')
                : value(cells, '三振')),
            'runs': _integer(value(cells, '失点')),
            if (index('自責点') >= 0) 'earnedRuns': _integer(value(cells, '自責点')),
          },
          phase: null));
    }
    return result;
  }

  static void _parseNpbLeaders(Element table, NpbYearPage page) {
    const categories = <String, int>{
      '首位打者': 1,
      '最多安打': 2,
      '最多本塁打': 3,
      '最多打点': 4,
      '最多盗塁': 5,
      '最優秀防御率': 9,
      '最多勝利': 10,
      '最多奪三振': 11,
      '最多セーブ': 19,
    };
    for (final row in table.querySelectorAll('tr')) {
      final cells = _cells(row);
      if (cells.length < 2) continue;
      final entry = categories.entries
          .where((candidate) => cells[0].contains(candidate.key))
          .firstOrNull;
      if (entry == null) continue;
      final joined = cells.sublist(1).join(' ');
      final identity = parseNpbPlayerCell(joined);
      if (identity == null) continue;
      final number = RegExp(r'(?:^|\s)([.]?\d+(?:\.\d+)?)\s*$')
          .firstMatch(joined)
          ?.group(1);
      if (number == null) continue;
      final target =
          entry.value >= 9 ? page.pitchingLeaders : page.hittingLeaders;
      target.add(NpbPlayerRow(
        identity.$1,
        identity.$2,
        {'leader:${entry.value}': _number(number)},
      ));
    }
  }

  static (String, String)? parseNpbPlayerIdentity(
      List<String> cells, int playerIndex) {
    if (playerIndex < 0 || playerIndex >= cells.length) return null;
    final current = parseNpbPlayerCell(cells[playerIndex]);
    if (current != null) return current;
    if (playerIndex + 1 >= cells.length) return null;
    return parseNpbPlayerCell('${cells[playerIndex]} ${cells[playerIndex + 1]}');
  }

  static (String, String)? parseNpbPlayerCell(String raw) {
    final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final matches = RegExp(r'^(.*?)\s*[（(]([^()（）]+)[）)]').firstMatch(compact);
    if (matches == null) return null;
    final name = matches.group(1)!.trim();
    final team = matches.group(2)!.trim();
    return name.isEmpty || team.isEmpty ? null : (name, team);
  }

  static List<String> _cells(Element row) => row
      .querySelectorAll('th,td')
      .map((cell) => cell.text.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((text) => text.isNotEmpty)
      .toList();

  static List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : const {};

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static int _integer(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_text(value).replaceAll(',', '')) ??
        double.tryParse(_text(value).replaceAll(',', ''))?.toInt() ??
        0;
  }

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    final text = _text(value).replaceAll(',', '');
    if (text.startsWith('.')) return double.tryParse('0$text') ?? 0;
    return double.tryParse(text) ?? 0;
  }

  static DateTime? _date(dynamic value) => DateTime.tryParse(_text(value));
}

class SeasonLine {
  const SeasonLine({
    required this.playerId,
    required this.teamId,
    required this.leagueId,
    required this.name,
    required this.teamName,
    required this.values,
  });

  final int playerId;
  final int teamId;
  final int leagueId;
  final String name;
  final String teamName;
  final Map<String, dynamic> values;
}

class MlbRawLine {
  const MlbRawLine({
    required this.playerExternalId,
    required this.teamExternalId,
    required this.playerName,
    required this.teamName,
    required this.teamShortName,
    required this.birthDate,
    required this.values,
  });
  final String playerExternalId;
  final String teamExternalId;
  final String playerName;
  final String teamName;
  final String teamShortName;
  final DateTime? birthDate;
  final Map<String, dynamic> values;
}

class RankValue {
  const RankValue(this.line, this.value, this.count);
  final SeasonLine line;
  final double value;
  final int count;
}

class NpbYearPage {
  NpbYearPage(this.year, this.leagueId, {this.phase});
  final int year;
  final int leagueId;
  final String? phase;
  final List<NpbStanding> standings = [];
  final List<NpbPlayerRow> hitting = [];
  final List<NpbPlayerRow> pitching = [];
  final List<NpbPlayerRow> hittingLeaders = [];
  final List<NpbPlayerRow> pitchingLeaders = [];
  final Map<String, int> teamIdsByName = {};
}

class NpbStanding {
  const NpbStanding({
    required this.teamName,
    required this.games,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.gamesBack,
  });
  final String teamName;
  final int games;
  final int wins;
  final int losses;
  final int draws;
  final String gamesBack;
}

class NpbPlayerRow {
  const NpbPlayerRow(this.playerName, this.teamAlias, this.values,
      {this.phase});
  final String playerName;
  final String teamAlias;
  final Map<String, dynamic> values;
  final String? phase;
}

class NpbDetailedRankRow {
  const NpbDetailedRankRow(
      this.rank, this.playerName, this.teamAlias, this.value);
  final int rank;
  final String playerName;
  final String teamAlias;
  final double value;
}

class NpbSourceSpec {
  const NpbSourceSpec({
    required this.leagueId,
    required this.checkpointTag,
    required this.uri,
    this.phase,
    this.activeStatsBase,
  });
  final int leagueId;
  final String checkpointTag;
  final String uri;
  final String? phase;
  final String? activeStatsBase;
}

class HistoricalHttpException implements Exception {
  const HistoricalHttpException(this.statusCode, this.uri);
  final int statusCode;
  final Uri uri;

  @override
  String toString() => 'HTTP $statusCode: $uri';
}

class HistoricalNotYetAvailable implements Exception {
  const HistoricalNotYetAvailable();
}

class HistoricalGame {
  const HistoricalGame({
    required this.sourceKey,
    required this.externalId,
    required this.codeGame,
    required this.start,
    required this.homeTeamKey,
    required this.awayTeamKey,
    required this.scoreHome,
    required this.scoreAway,
    required this.state,
  });
  final String sourceKey;
  final String externalId;
  final String codeGame;
  final DateTime start;
  final String homeTeamKey;
  final String awayTeamKey;
  final int? scoreHome;
  final int? scoreAway;
  final String state;
}

class PostseasonImportResult {
  const PostseasonImportResult(this.rowCount, this.status);
  final int rowCount;
  final String status;
}
