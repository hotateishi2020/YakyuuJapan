import 'dart:io';
import 'tools/Postgres.dart';

/// 添付表の MVP・沢村賞を対象タイトルと予想選手、結果に登録する。
///
///   cd backend && dart run tool_import_awards.dart
Future<void> main() async {
  const mvp = <int, Map<int, Map<int, String>>>{
    2021: {
      1: {1: '岡本和真', 2: '山本由伸'},
      2: {1: '岡本和真', 2: '山本由伸'},
    },
    2022: {
      1: {1: '大瀬良大地', 2: '佐々木朗希'},
      2: {1: '村上宗隆', 2: '田中将大'},
    },
    2023: {
      1: {1: '大竹耕太郎', 2: '佐々木朗希'},
      2: {1: '今永昇太', 2: '山本由伸'},
    },
    2024: {
      1: {1: '岡本和真', 2: 'モイネロ'},
      2: {1: '村上頌樹', 2: 'エスピノーザ'},
    },
  };
  const mvpResult = <int, Map<int, String>>{
    2021: {1: '村上宗隆', 2: '山本由伸'},
    2022: {1: '村上宗隆', 2: '山本由伸'},
    2024: {1: '菅野智之', 2: '近藤健介'},
  };
  const sawamura = <int, Map<int, String>>{
    2021: {1: '山本由伸', 2: '山本由伸'},
    2022: {1: '佐々木朗希', 2: '田中将大'},
    2023: {1: '佐々木朗希', 2: '山本由伸'},
  };
  const sawamuraResult = <int, String>{
    2021: '山本由伸',
    2022: '山本由伸',
  };

  await Postgres.withConnection((conn) async {
    Future<int> ensureStat(String title, bool pitcher, String shortest, int index) async {
      final found = await conn.execute(
        '''
        SELECT id FROM m_stats
        WHERE title = \$1 AND COALESCE(flg_delete, FALSE) = FALSE
        ORDER BY id
        LIMIT 1
        ''',
        parameters: [title],
      );
      if (found.isNotEmpty) return found.first.toColumnMap()['id'] as int;
      final inserted = await conn.execute(
        '''
        INSERT INTO m_stats (
          title, flg_pitcher, flg_positive, flg_delete, int_index, code_display, title_shortest,
          crtpgm, updpgm, crtat, updat
        )
        VALUES (\$1, \$2, TRUE, FALSE, \$3, 'INTEGER', \$4, 'award', 'award', NOW(), NOW())
        RETURNING id
        ''',
        parameters: [title, pitcher, index, shortest],
      );
      return inserted.first.toColumnMap()['id'] as int;
    }

    final mvpId = await ensureStat('MVP', false, 'MVP', 0);
    final sawamuraId = await ensureStat('沢村賞', true, '沢村', 0);
    print('stats MVP=$mvpId 沢村賞=$sawamuraId');

    Future<({int id, int teamId})?> findPlayer(String name, int leagueId, int year) async {
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
            replace(replace(COALESCE(p.name_full, ''), '　', ''), ' ', '') = \$2
            OR concat(p.name_last, p.name_first) = \$2
            OR p.name_last = \$2
          )
        ORDER BY CASE WHEN s.int_year = \$3 THEN 0 ELSE 1 END, p.id
        LIMIT 1
        ''',
        parameters: [leagueId, name.replaceAll(RegExp(r'[\s　]+'), ''), year],
      );
      if (rows.isEmpty) return null;
      final map = rows.first.toColumnMap();
      return (id: map['id'] as int, teamId: map['id_team'] as int);
    }

    final settings = await conn.execute('''
      SELECT id, int_year
      FROM t_predict_setting
      WHERE COALESCE(flg_delete, FALSE) = FALSE
        AND int_year BETWEEN 2021 AND 2024
      ORDER BY int_year, id
    ''');
    final settingOf = <int, int>{};
    for (final row in settings) {
      final map = row.toColumnMap();
      settingOf.putIfAbsent(map['int_year'] as int, () => map['id'] as int);
    }

    Future<void> ensureTitle(int settingId, int statsId, String title) async {
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
    }

    await conn.execute(
      'DELETE FROM t_predict_player WHERE id_stats IN (\$1, \$2) AND year BETWEEN 2021 AND 2024',
      parameters: [mvpId, sawamuraId],
    );
    await conn.execute(
      'DELETE FROM t_stats_player WHERE id_stats IN (\$1, \$2) AND int_year BETWEEN 2021 AND 2024',
      parameters: [mvpId, sawamuraId],
    );

    final missing = <String>[];
    var picks = 0;
    var results = 0;

    Future<void> addPick(int year, int settingId, int userId, int leagueId, int statsId, String name) async {
      final player = await findPlayer(name, leagueId, year);
      if (player == null) {
        missing.add('$year user=$userId league=$leagueId $name');
        return;
      }
      await conn.execute(
        '''
        INSERT INTO t_predict_player
          (year, id_user, id_league, id_stats, id_player, id_team, id_predict_setting, flg_delete)
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, FALSE)
        ''',
        parameters: [year, userId, leagueId, statsId, player.id, player.teamId, settingId],
      );
      picks++;
    }

    Future<void> addResult(int year, int leagueId, int statsId, String name) async {
      final player = await findPlayer(name, leagueId, year);
      if (player == null) {
        missing.add('$year result league=$leagueId $name');
        return;
      }
      await conn.execute(
        '''
        INSERT INTO t_stats_player
          (int_year, id_league, id_stats, id_player, id_team, int_rank, stats, cnt_play, flg_delete, crtat, updat)
        VALUES (\$1, \$2, \$3, \$4, \$5, 1, 1, 1, FALSE, NOW(), NOW())
        ''',
        parameters: [year, leagueId, statsId, player.id, player.teamId],
      );
      results++;
    }

    for (final year in [2021, 2022, 2023, 2024]) {
      final settingId = settingOf[year];
      if (settingId == null) {
        missing.add('$year の予想設定がありません');
        continue;
      }
      if (mvp.containsKey(year)) await ensureTitle(settingId, mvpId, 'MVP');
      if (sawamura.containsKey(year)) await ensureTitle(settingId, sawamuraId, '沢村賞');
      final byUser = mvp[year];
      if (byUser != null) {
        for (final userId in byUser.keys) {
          for (final leagueId in byUser[userId]!.keys) {
            await addPick(year, settingId, userId, leagueId, mvpId, byUser[userId]![leagueId]!);
          }
        }
      }
      final mvpWinner = mvpResult[year];
      if (mvpWinner != null) {
        for (final leagueId in mvpWinner.keys) {
          await addResult(year, leagueId, mvpId, mvpWinner[leagueId]!);
        }
      }
      final sawa = sawamura[year];
      if (sawa != null) {
        for (final userId in sawa.keys) {
          await addPick(year, settingId, userId, 0, sawamuraId, sawa[userId]!);
        }
      }
      final sawaWinner = sawamuraResult[year];
      if (sawaWinner != null) await addResult(year, 0, sawamuraId, sawaWinner);
    }

    print('picks=$picks results=$results');
    if (missing.isNotEmpty) {
      print('MISSING ${missing.length}');
      for (final line in missing) {
        print('  $line');
      }
    }
  });
  exit(0);
}
