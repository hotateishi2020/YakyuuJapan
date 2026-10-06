import 'dart:io';
import 'tools/Postgres.dart';

/// 添付の 2021–2025 NPB 予想を DB に登録する。
/// 2019–2020 は画像が無いのでスキップ。2026 は触れない。
///
///   cd backend && dart run tool_import_predictions.dart
Future<void> main() async {
  const batting = ['本塁打', '打点', '打率', '出塁率', '盗塁'];
  const pitchingHold = ['防御率', '奪三振', 'ホールド', 'セーブ', '最多勝'];
  const pitchingHp = ['防御率', '奪三振', '中継ぎ', 'セーブ', '最多勝'];

  const years = <int, _YearPred>{
    2025: _YearPred(
      players: {
        1: {
          1: ['佐藤輝明', '岡本和真', '吉川尚輝', '岡本和真', '近本光司', '東克樹', '井上温大', '大勢', '岩崎優', '山﨑伊織'],
          2: ['万波中正', '山川穂高', '周東佑京', '太田椋', '西川愛也', 'モイネロ', 'モイネロ', '松本裕樹', '田中正義', '九里亜蓮'],
        },
        2: {
          1: ['岡本和真', '佐藤輝明', '牧秀悟', '近本光司', '若林楽人', '柳裕也', 'デュプランティエ', '清水達也', 'マルティネス', '東克樹'],
          2: ['山川穂高', '浅村栄斗', '西川龍馬', '浅村栄斗', '周東佑京', '今井達也', '伊藤大海', '河野竜生', '平良海馬', '隅田知一郎'],
        },
      },
      standings: {
        1: {
          1: ['巨人', 'DeNA', '阪神', 'ヤクルト', '広島', '中日'],
          2: ['ソフトバンク', '日本ハム', '楽天', 'ロッテ', 'オリックス', '西武'],
        },
        2: {
          1: ['DeNA', '巨人', '広島', '阪神', '中日', 'ヤクルト'],
          2: ['日本ハム', 'ソフトバンク', 'ロッテ', '西武', '楽天', 'オリックス'],
        },
      },
      champions: {1: 'ソフトバンク', 2: '日本ハム'},
      holdTitle: 'ホールド',
    ),
    2024: _YearPred(
      players: {
        1: {
          1: ['岡本和真', '村上宗隆', '牧秀悟', '宮﨑敏朗', '近本光司', '村上頌樹', '戸郷翔征', '西舘勇陽', 'マルティネス', '菅野智之'],
          2: ['山川穂高', '山川穂高', '近藤健介', '柳田悠岐', '周東佑京', 'モイネロ', 'モイネロ', '松本裕樹', 'オスナ', 'モイネロ'],
        },
        2: {
          1: ['村上宗隆', '村上宗隆', '牧秀悟', '村上宗隆', '近本光司', '戸郷翔征', '戸郷翔征', 'バルドナード', '栗林良吏', '村上頌樹'],
          2: ['セデーニョ', '山川穂高', '近藤健介', '近藤健介', '周東佑京', '今井達也', '佐々木朗希', '松本裕樹', '田中正義', '大津亮介'],
        },
      },
      standings: {
        1: {
          1: ['巨人', 'ヤクルト', '阪神', 'DeNA', '中日', '広島'],
          2: ['ソフトバンク', '日本ハム', '西武', 'オリックス', 'ロッテ', '楽天'],
        },
        2: {
          1: ['阪神', '巨人', '広島', 'DeNA', 'ヤクルト', '中日'],
          2: ['ソフトバンク', 'オリックス', '日本ハム', '西武', 'ロッテ', '楽天'],
        },
      },
      champions: {1: 'ソフトバンク', 2: 'ソフトバンク'},
      holdTitle: 'ホールド',
    ),
    2023: _YearPred(
      players: {
        1: {
          1: ['村上宗隆', '村上宗隆', '宮﨑敏朗', '宮﨑敏朗', '中野拓夢', '大竹耕太郎', 'バウアー', '清水昇', '山崎康晃', '大竹耕太郎'],
          2: ['柳田悠岐', '柳田悠岐', '柳田悠岐', '近藤健介', '周東佑京', '佐々木朗希', '佐々木朗希', 'ペルドモ', '松井裕樹', '山本由伸'],
        },
        2: {
          1: ['岡本和真', '岡本和真', '宮﨑敏朗', '村上宗隆', '中野拓夢', '大竹耕太郎', '今永昇太', '清水昇', 'マルティネス', '今永昇太'],
          2: ['浅村栄斗', '柳田悠岐', '近藤健介', '近藤健介', '周東佑京', '佐々木朗希', '佐々木朗希', 'ペルドモ', '松井裕樹', '山本由伸'],
        },
      },
      standings: {
        1: {
          1: ['阪神', 'DeNA', '巨人', '広島', 'ヤクルト', '中日'],
          2: ['オリックス', 'ソフトバンク', 'ロッテ', '西武', '日本ハム', '楽天'],
        },
        2: {
          1: ['DeNA', '阪神', '広島', '巨人', 'ヤクルト', '中日'],
          2: ['オリックス', 'ロッテ', 'ソフトバンク', '楽天', '西武', '日本ハム'],
        },
      },
      champions: {1: '阪神', 2: 'オリックス'},
      holdTitle: '中継ぎ',
    ),
    2022: _YearPred(
      players: {
        1: {
          1: ['佐藤輝明', '西川龍馬', '坂倉将吾', '牧秀悟', '山田哲人', '九里亜蓮', '菅野智之', '今村信貴', '大勢', '大瀬良大地'],
          2: ['山川穂高', '柳田悠岐', '吉田正尚', '吉田正尚', '西川遥輝', '佐々木朗希', '佐々木朗希', '又吉克樹', '松井裕樹', '千賀滉大'],
        },
        2: {
          1: ['村上宗隆', '村上宗隆', '牧秀悟', '村上宗隆', '塩見泰隆', '青柳晃洋', '高橋奎二', 'ロドリゲス', 'マクガフ', '大瀬良大地'],
          2: ['山川穂高', '山川穂高', '吉田正尚', '吉田正尚', '高部瑛人', '田中将大', '佐々木朗希', '平良海馬', '松井裕樹', '田中将大'],
        },
      },
      standings: {
        1: {
          1: ['広島', '巨人', 'DeNA', '中日', '阪神', 'ヤクルト'],
          2: ['ソフトバンク', '西武', '楽天', 'オリックス', '日本ハム', 'ロッテ'],
        },
        2: {
          1: ['ヤクルト', '巨人', '広島', '中日', '阪神', 'DeNA'],
          2: ['楽天', '西武', 'ソフトバンク', 'オリックス', 'ロッテ', '日本ハム'],
        },
      },
      champions: {1: 'ソフトバンク', 2: '楽天'},
      holdTitle: '中継ぎ',
    ),
    2021: _YearPred(
      players: {
        1: {
          1: ['岡本和真', '岡本和真', 'ウィーラー', '鈴木誠也', '近本光司', '森下暢仁', '柳裕也', '清水昇', 'スアレス', '九里亜蓮'],
          2: ['柳田悠岐', 'マーティン', '吉田正尚', '吉田正尚', '源田壮亮', '山本由伸', '山本由伸', '平良海馬', '松井裕樹', '山本由伸'],
        },
        2: {
          1: ['村上宗隆', '岡本和真', '佐野恵太', 'マルテ', '塩見泰隆', '青柳晃洋', '柳裕也', '清水昇', 'スアレス', '青柳晃洋'],
          2: ['マーティン', 'マーティン', '吉田正尚', '吉田正尚', '源田壮亮', '山本由伸', '山本由伸', '平良海馬', '松井裕樹', '山本由伸'],
        },
      },
      standings: {},
      champions: {},
      holdTitle: '中継ぎ',
    ),
  };

  await Postgres.withConnection((conn) async {
    final statsRows = await conn.execute(
      "SELECT id, title FROM m_stats WHERE COALESCE(flg_delete, FALSE) = FALSE",
    );
    final statsByTitle = <String, int>{};
    for (final row in statsRows) {
      final map = row.toColumnMap();
      statsByTitle['${map['title']}'] = map['id'] as int;
    }
    int statsId(String title) {
      const aliases = {
        '中継ぎ': ['HP', 'ホールドポイント', 'ホールド'],
        'ホールド': ['ホールド', 'HP'],
        '最多勝': ['最多勝', '勝利'],
      };
      for (final name in [title, ...?aliases[title]]) {
        final id = statsByTitle[name];
        if (id != null) return id;
      }
      throw StateError('m_stats に「$title」がありません: $statsByTitle');
    }

    final teamRows = await conn.execute('''
      SELECT id, name_short, name_shortest, name_full, id_league
      FROM m_team
      WHERE id_league IN (1, 2) AND COALESCE(flg_delete, FALSE) = FALSE
    ''');
    final teams = [
      for (final row in teamRows) row.toColumnMap(),
    ];

    Map<String, dynamic>? findTeam(String name, int leagueId) {
      final needle = _normTeam(name);
      for (final team in teams) {
        if ((team['id_league'] as int) != leagueId) continue;
        final names = [
          '${team['name_short']}',
          '${team['name_shortest']}',
          '${team['name_full']}',
        ].map(_normTeam);
        if (names.contains(needle)) return team;
      }
      return null;
    }

    Future<({int id, int teamId})?> findPlayer(String name, int leagueId, int year) async {
      final aliases = _playerAliases(name);
      for (final alias in aliases) {
        final rows = await conn.execute(
          '''
          SELECT p.id, p.id_team, p.name_full, t.id_league
          FROM m_player p
          JOIN m_team t ON t.id = p.id_team
          WHERE t.id_league = \$1
            AND COALESCE(p.flg_delete, FALSE) = FALSE
            AND (
              replace(replace(p.name_full, '　', ''), ' ', '') = \$2
              OR concat(p.name_last, p.name_first) = \$2
              OR p.name_last = \$2
            )
          ORDER BY p.id
          LIMIT 8
          ''',
          parameters: [leagueId, alias],
        );
        if (rows.isNotEmpty) {
          final map = rows.first.toColumnMap();
          return (id: map['id'] as int, teamId: map['id_team'] as int);
        }
      }
      // 所属が変わっている選手は、当時の成績行から探す。
      for (final alias in aliases) {
        final rows = await conn.execute(
          '''
          SELECT p.id, COALESCE(s.id_team, p.id_team) AS id_team
          FROM m_player p
          LEFT JOIN t_stats_player s
            ON s.id_player = p.id AND s.int_year = \$3 AND s.id_league = \$1
          JOIN m_team t ON t.id = COALESCE(s.id_team, p.id_team)
          WHERE t.id_league = \$1
            AND COALESCE(p.flg_delete, FALSE) = FALSE
            AND (
              p.name_full = \$2
              OR concat(p.name_last, p.name_first) = \$2
            )
          ORDER BY s.int_year DESC NULLS LAST, p.id
          LIMIT 1
          ''',
          parameters: [leagueId, alias, year],
        );
        if (rows.isNotEmpty) {
          final map = rows.first.toColumnMap();
          return (id: map['id'] as int, teamId: map['id_team'] as int);
        }
      }
      return null;
    }

    Future<({int id, int teamId})?> findPlayerAnyNpb(String name, int preferLeague) async {
      final aliases = _playerAliases(name);
      for (final alias in aliases) {
        final rows = await conn.execute(
          '''
          SELECT p.id, p.id_team
          FROM m_player p
          JOIN m_team t ON t.id = p.id_team
          WHERE t.id_league IN (1, 2)
            AND COALESCE(p.flg_delete, FALSE) = FALSE
            AND (
              replace(replace(p.name_full, '　', ''), ' ', '') = \$1
              OR concat(p.name_last, p.name_first) = \$1
              OR p.name_last = \$1
            )
          ORDER BY CASE WHEN t.id_league = \$2 THEN 0 ELSE 1 END, p.id
          LIMIT 1
          ''',
          parameters: [alias, preferLeague],
        );
        if (rows.isNotEmpty) {
          final map = rows.first.toColumnMap();
          return (id: map['id'] as int, teamId: map['id_team'] as int);
        }
      }
      return null;
    }

    final missing = <String>[];
    var playerInserts = 0;
    var teamInserts = 0;

    for (final entry in years.entries) {
      final year = entry.key;
      final pred = entry.value;
      final pitching = pred.holdTitle == 'ホールド' ? pitchingHold : pitchingHp;
      final playerTitles = [...batting, ...pitching];

      await conn.execute('DELETE FROM t_predict_player WHERE year = \$1', parameters: [year]);
      await conn.execute('DELETE FROM t_predict_team WHERE int_year = \$1', parameters: [year]);

      for (final userId in const [1, 2]) {
        final byLeague = pred.players[userId]!;
        for (final leagueId in const [1, 2]) {
          final names = byLeague[leagueId]!;
          if (names.length != playerTitles.length) {
            throw StateError('$year user=$userId league=$leagueId names=${names.length}');
          }
          for (var i = 0; i < names.length; i++) {
            final title = playerTitles[i];
            final idStats = statsId(title == '中継ぎ' ? 'HP' : title);
            final player = await findPlayer(names[i], leagueId, year) ??
                await findPlayerAnyNpb(names[i], leagueId);
            if (player == null) {
              missing.add('$year user=$userId $title ${names[i]} (league $leagueId)');
              continue;
            }
            await conn.execute(
              '''
              INSERT INTO t_predict_player
                (year, id_user, id_league, id_stats, id_player, id_team)
              VALUES (\$1, \$2, \$3, \$4, \$5, \$6)
              ''',
              parameters: [year, userId, leagueId, idStats, player.id, player.teamId],
            );
            playerInserts++;
          }
        }

        final ranks = pred.standings[userId];
        if (ranks == null) continue;
        for (final leagueId in const [1, 2]) {
          final teamNames = ranks[leagueId]!;
          for (var i = 0; i < teamNames.length; i++) {
            final team = findTeam(teamNames[i], leagueId);
            if (team == null) {
              missing.add('$year user=$userId rank ${i + 1} ${teamNames[i]} (league $leagueId)');
              continue;
            }
            final champion = pred.champions[userId] != null &&
                _normTeam(pred.champions[userId]!) == _normTeam(teamNames[i]);
            await conn.execute(
              '''
              INSERT INTO t_predict_team
                (int_year, id_user, id_team, int_rank, flg_champion)
              VALUES (\$1, \$2, \$3, \$4, \$5)
              ''',
              parameters: [year, userId, team['id'], i + 1, champion],
            );
            teamInserts++;
          }
        }
      }
      print('year $year done');
    }

    print('inserted players=$playerInserts teams=$teamInserts');
    if (missing.isNotEmpty) {
      print('MISSING ${missing.length}:');
      for (final line in missing) {
        print('  $line');
      }
    }

    final counts = await conn.execute('''
      SELECT year, COUNT(*) FROM t_predict_player GROUP BY year ORDER BY year
    ''');
    print('t_predict_player by year:');
    for (final row in counts) {
      print(row.toColumnMap());
    }
    final teamCounts = await conn.execute('''
      SELECT int_year, COUNT(*) FROM t_predict_team GROUP BY int_year ORDER BY int_year
    ''');
    print('t_predict_team by year:');
    for (final row in teamCounts) {
      print(row.toColumnMap());
    }
  });
  exit(0);
}

class _YearPred {
  final Map<int, Map<int, List<String>>> players;
  final Map<int, Map<int, List<String>>> standings;
  final Map<int, String> champions;
  final String holdTitle;

  const _YearPred({
    required this.players,
    required this.standings,
    required this.champions,
    required this.holdTitle,
  });
}

String _normTeam(String name) {
  return name
      .replaceAll('　', '')
      .replaceAll(' ', '')
      .replaceAll('日ハム', '日本ハム')
      .replaceAll('横浜DeNA', 'DeNA')
      .replaceAll('横浜', 'DeNA');
}

List<String> _playerAliases(String name) {
  const aliases = {
    '周東右京': ['周東佑京'],
    '周東佑京': ['周東佑京', '周東右京'],
    '山﨑伊織': ['山﨑伊織', '山崎伊織'],
    '山崎伊織': ['山﨑伊織', '山崎伊織'],
    '山崎康晃': ['山崎康晃', '山﨑康晃'],
    '宮﨑敏朗': ['宮﨑敏郎', '宮崎敏郎', '宮﨑敏朗'],
    '山本・宮城': ['山本由伸'],
    '高部瑛人': ['髙部瑛斗', '高部瑛斗', '髙部瑛人'],
    'ウィーラー': ['ウィーラー'],
  };
  final extra = aliases[name] ?? const <String>[];
  return {name, ...extra}.toList();
}
