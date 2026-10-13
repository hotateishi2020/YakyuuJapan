import 'dart:io';
import 'tools/Postgres.dart';

/// 2021〜2025 の日本一、沢村賞、リーグMVP、HP の結果を登録する。
///
///   cd backend && dart run tool_import_results.dart
Future<void> main() async {
  const japan = <int, String>{
    2021: 'ヤクルト',
    2022: 'オリックス',
    2023: '阪神',
    2024: 'DeNA',
    2025: 'ソフトバンク',
  };
  const mvp = <int, Map<int, String>>{
    2023: {1: '村上頌樹', 2: '山本由伸'},
    2025: {1: '佐藤輝明', 2: 'モイネロ'},
  };
  const sawamura = <int, String>{
    2023: '山本由伸',
    2025: '伊藤大海',
  };
  const hp = <int, Map<int, List<String>>>{
    2021: {1: ['清水昇'], 2: ['堀瑞輝']},
    2022: {1: ['湯浅京己'], 2: ['平良海馬']},
    2023: {1: ['島内颯太郎'], 2: ['ペルドモ']},
    2024: {1: ['桐敷拓馬', '松山晋也'], 2: ['河野竜生']},
    2025: {1: ['大勢'], 2: ['松本裕樹']},
  };

  await Postgres.withConnection((conn) async {
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS t_japan_champion (
        int_year INTEGER PRIMARY KEY,
        id_team INTEGER NOT NULL,
        flg_delete BOOLEAN NOT NULL DEFAULT FALSE,
        crtat TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updat TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    Future<int> statId(String title) async {
      final rows = await conn.execute(
        '''
        SELECT id FROM m_stats
        WHERE title = \$1 AND COALESCE(flg_delete, FALSE) = FALSE
        ORDER BY id LIMIT 1
        ''',
        parameters: [title],
      );
      if (rows.isEmpty) throw StateError('$title が m_stats にありません');
      return rows.first.toColumnMap()['id'] as int;
    }

    final mvpId = await statId('MVP');
    final sawamuraId = await statId('沢村賞');
    final hpId = await statId('HP');
    final missing = <String>[];

    Future<int?> findTeam(String name) async {
      final rows = await conn.execute(
        '''
        SELECT id, COALESCE(NULLIF(name_short, ''), name_shortest, '') AS label
        FROM m_team
        WHERE id_league IN (1, 2)
          AND COALESCE(flg_delete, FALSE) = FALSE
          AND (
            replace(replace(COALESCE(name_short, ''), '　', ''), ' ', '') = \$1
            OR replace(replace(COALESCE(name_shortest, ''), '　', ''), ' ', '') = \$1
          )
        ORDER BY id
        ''',
        parameters: [name],
      );
      if (rows.isEmpty) return null;
      return rows.first.toColumnMap()['id'] as int;
    }

    Future<({int id, int teamId})?> findPlayer(String name, int leagueId, int year) async {
      final alias = name.replaceAll(RegExp(r'[\s　]+'), '');
      final known = await conn.execute(
        '''
        SELECT s.id_player, s.id_team
        FROM t_stats_player s
        JOIN m_player p ON p.id = s.id_player
        WHERE s.int_year = \$1
          AND (\$2 = 0 OR s.id_league = \$2)
          AND s.int_rank = 1
          AND COALESCE(s.flg_delete, FALSE) = FALSE
          AND regexp_replace(COALESCE(p.name_full, ''), E'[\\s　]+', '', 'g') = \$3
        ORDER BY s.id
        LIMIT 1
        ''',
        parameters: [year, leagueId, alias],
      );
      if (known.isNotEmpty) {
        final map = known.first.toColumnMap();
        return (id: map['id_player'] as int, teamId: map['id_team'] as int);
      }
      final rows = await conn.execute(
        '''
        SELECT p.id, COALESCE(s.id_team, p.id_team) AS id_team
        FROM m_player p
        LEFT JOIN t_stats_player s
          ON s.id_player = p.id AND s.int_year = \$3 AND (\$1 = 0 OR s.id_league = \$1)
        JOIN m_team t ON t.id = COALESCE(s.id_team, p.id_team)
        WHERE (\$1 = 0 OR t.id_league = \$1)
          AND t.id_league IN (1, 2)
          AND COALESCE(p.flg_delete, FALSE) = FALSE
          AND (
            regexp_replace(COALESCE(p.name_full, ''), E'[\\s　]+', '', 'g') = \$2
            OR concat(p.name_last, p.name_first) = \$2
            OR p.name_last = \$2
          )
        ORDER BY CASE WHEN s.int_year = \$3 THEN 0 ELSE 1 END, p.id
        LIMIT 1
        ''',
        parameters: [leagueId, alias, year],
      );
      if (rows.isEmpty) return null;
      final map = rows.first.toColumnMap();
      return (id: map['id'] as int, teamId: map['id_team'] as int);
    }

    final settings = await conn.execute('''
      SELECT id, int_year
      FROM t_predict_setting
      WHERE COALESCE(flg_delete, FALSE) = FALSE
        AND int_year BETWEEN 2021 AND 2025
      ORDER BY int_year, id
    ''');
    final settingOf = <int, int>{};
    for (final row in settings) {
      final map = row.toColumnMap();
      settingOf.putIfAbsent(map['int_year'] as int, () => map['id'] as int);
    }

    Future<void> ensureTitle(int year, int statsId, String title) async {
      final settingId = settingOf[year];
      if (settingId == null) {
        missing.add('$year の予想設定がありません');
        return;
      }
      final exists = await conn.execute(
        '''
        SELECT id FROM t_predict_setting_details
        WHERE id_predict_setting = \$1
          AND txt_title = \$2
          AND COALESCE(flg_delete, FALSE) = FALSE
        LIMIT 1
        ''',
        parameters: [settingId, title],
      );
      if (exists.isNotEmpty) return;
      await conn.execute(
        '''
        INSERT INTO t_predict_setting_details
          (id_predict_setting, id_stats, txt_title, crtby, updby)
        VALUES (\$1, \$2, \$3, 0, 0)
        ''',
        parameters: [settingId, statsId, title],
      );
      print('title $year $title');
    }

    Future<void> addResult(int year, int leagueId, int statsId, String name) async {
      final player = await findPlayer(name, leagueId, year);
      if (player == null) {
        missing.add('$year league=$leagueId stats=$statsId $name');
        return;
      }
      final exists = await conn.execute(
        '''
        SELECT id FROM t_stats_player
        WHERE int_year = \$1 AND id_league = \$2 AND id_stats = \$3
          AND id_player = \$4 AND int_rank = 1
          AND COALESCE(flg_delete, FALSE) = FALSE
        LIMIT 1
        ''',
        parameters: [year, leagueId, statsId, player.id],
      );
      if (exists.isNotEmpty) return;
      await conn.execute(
        '''
        INSERT INTO t_stats_player
          (int_year, id_league, id_stats, id_player, id_team, int_rank, stats, cnt_play, flg_delete, crtat, updat)
        VALUES (\$1, \$2, \$3, \$4, \$5, 1, 1, 1, FALSE, NOW(), NOW())
        ''',
        parameters: [year, leagueId, statsId, player.id, player.teamId],
      );
      print('result $year L$leagueId $name');
    }

    for (final entry in japan.entries) {
      final teamId = await findTeam(entry.value);
      if (teamId == null) {
        missing.add('${entry.key} 日本一 ${entry.value}');
        continue;
      }
      await conn.execute(
        '''
        INSERT INTO t_japan_champion (int_year, id_team)
        VALUES (\$1, \$2)
        ON CONFLICT (int_year) DO UPDATE
          SET id_team = EXCLUDED.id_team, flg_delete = FALSE, updat = NOW()
        ''',
        parameters: [entry.key, teamId],
      );
      print('japan ${entry.key} ${entry.value}');
    }

    for (final year in mvp.keys) {
      await ensureTitle(year, mvpId, 'MVP');
      for (final leagueId in mvp[year]!.keys) {
        await addResult(year, leagueId, mvpId, mvp[year]![leagueId]!);
      }
    }
    for (final year in [2023, 2024, 2025]) {
      await ensureTitle(year, sawamuraId, '沢村賞');
    }
    for (final entry in sawamura.entries) {
      await addResult(entry.key, 0, sawamuraId, entry.value);
    }

    await conn.execute(
      'DELETE FROM t_stats_player WHERE id_stats = \$1 AND int_year BETWEEN 2021 AND 2025',
      parameters: [hpId],
    );
    for (final year in hp.keys) {
      for (final leagueId in hp[year]!.keys) {
        for (final name in hp[year]![leagueId]!) {
          await addResult(year, leagueId, hpId, name);
        }
      }
    }

    if (missing.isEmpty) {
      print('MISSING none');
    } else {
      for (final line in missing) {
        print('MISSING $line');
      }
    }
  });
  exit(0);
}
