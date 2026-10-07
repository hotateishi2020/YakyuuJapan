import 'package:postgres/postgres.dart';

class StadiumImagePaths {
  const StadiumImagePaths({this.inside = '', this.outside = ''});
  final String inside;
  final String outside;
}

/// 添付した球場画像。`m_stadium.path_image_inside` / `path_image_outside` に書く。
class StadiumImages {
  static const _root = 'backend/assets/images/stadiums';

  static const _npb = <(List<String>, String, String)>[
    (['エスコン', 'escon', '北海道ボールパーク'], 'inside/npb-01-escon.jpg', 'outside/npb-01-escon.png'),
    (['楽天モバイル', 'モバイルパーク', '楽天生命', 'kobo'], 'inside/npb-02-miyagi.jpg', 'outside/npb-02-miyagi.png'),
    (['ベルーナ', '西武ドーム', 'メットライフ', 'プリンスドーム'], 'inside/npb-03-belluna.jpg', 'outside/npb-03-belluna.png'),
    (['zozo', 'マリン', '千葉マリン'], 'inside/npb-06-chiba.jpg', 'outside/npb-04-zozo.png'),
    (['神宮'], 'inside/npb-05-jingu.jpg', 'outside/npb-05-jingu.png'),
    (['東京ドーム'], 'inside/npb-04-tokyo.jpg', 'outside/npb-06-tokyo.png'),
    (['横浜'], 'inside/npb-07-yokohama.jpg', 'outside/npb-07-yokohama.png'),
    (['バンテリン', 'ナゴヤドーム'], 'inside/npb-08-nagoya.jpg', 'outside/npb-08-nagoya.png'),
    (['京セラ', '大阪ドーム'], 'inside/npb-09-osaka.jpg', 'outside/npb-09-osaka.png'),
    (['甲子園'], 'inside/npb-10-koshien.jpg', 'outside/npb-10-koshien.png'),
    (['マツダ'], 'inside/npb-11-hiroshima.jpg', 'outside/npb-11-hiroshima.png'),
    (['paypay', 'みずほ', 'ヤフオク', '福岡ドーム', 'yahoo'], 'inside/npb-12-fukuoka.jpg', 'outside/npb-12-fukuoka.png'),
  ];

  static const _mlb = <(List<String>, String, String)>[
    (['yankee', 'ヤンキー'], 'inside/mlb-25-yankee.jpg', 'outside/mlb-01-yankee.png'),
    (['fenway', 'フェンウェイ'], 'inside/mlb-01-fenway.jpg', 'outside/mlb-02-fenway.png'),
    (['rogers', 'ロジャーズ'], 'inside/mlb-06-rogers.jpg', 'outside/mlb-03-rogers.png'),
    (['steinbrenner', 'スタインブレナー', 'tropicana', 'トロピカーナ'], 'inside/mlb-11-tropicana.jpg', 'outside/mlb-04-steinbrenner.png'),
    (['camden', 'oriole', 'カムデン', 'オリオール'], 'inside/mlb-08-camden.jpg', 'outside/mlb-05-camden.png'),
    (['progressive', 'プログレッシブ'], 'inside/mlb-09-progressive.jpg', 'outside/mlb-06-progressive.png'),
    (['comerica', 'コメリカ'], 'inside/mlb-15-comerica.jpg', 'outside/mlb-07-comerica.png'),
    (['kauffman', 'カウフマン'], 'inside/mlb-05-kauffman.jpg', 'outside/mlb-08-kauffman.png'),
    (['target', 'ターゲット'], 'inside/mlb-26-target.jpg', 'outside/mlb-09-target.png'),
    (['rate field', 'レート'], 'inside/mlb-07-rate.jpg', 'outside/mlb-10-rate.png'),
    (['daikin', 'ダイキン', 'ミニッツメイド'], 'inside/mlb-14-daikin.jpg', 'outside/mlb-11-daikin.png'),
    (['globe life', 'グローブライフ', 'グローブ・ライフ'], 'inside/mlb-29-globe-life.jpg', 'outside/mlb-12-globe-life.png'),
    (['angel', 'エンゼル'], 'inside/mlb-04-angel.jpg', 'outside/mlb-13-angel.png'),
    (['t-mobile', 'tmobile', 'tモバイル'], 'inside/mlb-13-tmobile.jpg', 'outside/mlb-14-tmobile.png'),
    (['sutter', 'サッター'], 'inside/mlb-30-sutter-health.jpg', 'outside/mlb-15-sutter.png'),
    (['truist', 'トゥルイスト', 'トゥルーイスト'], 'inside/mlb-28-truist.jpg', 'outside/mlb-16-truist.png'),
    (['loandepot', 'loan depot', 'ローンデポ', 'マーリンズパーク'], 'inside/mlb-27-loandepot.jpg', 'outside/mlb-17-loandepot.png'),
    (['citi', 'シティ'], 'inside/mlb-24-citi.jpg', 'outside/mlb-18-citi.png'),
    (['citizens', 'シチズンズ'], 'inside/mlb-21-citizens.jpg', 'outside/mlb-19-citizens.png'),
    (['nationals park', 'ナショナルズパーク', 'ナショナルズ・パーク'], 'inside/mlb-23-nationals.jpg', 'outside/mlb-20-nationals.png'),
    (['wrigley', 'リグレー'], 'inside/mlb-02-wrigley.jpg', 'outside/mlb-21-wrigley.png'),
    (['great american', 'グレートアメリカン'], 'inside/mlb-19-great-american.jpg', 'outside/mlb-22-great-american.png'),
    (['american family', 'アメリカンファミリー'], 'inside/mlb-17-american-family.jpg', 'outside/mlb-23-american-family.png'),
    (['busch', 'ブッシュ'], 'inside/mlb-22-busch.jpg', 'outside/mlb-24-busch.png'),
    (['pnc', 'pncパーク'], 'inside/mlb-18-pnc.jpg', 'outside/mlb-25-pnc.png'),
    (['dodger', 'ドジャー'], 'inside/mlb-03-dodger.jpg', 'outside/mlb-26-dodger.png'),
    (['petco', 'ペトコ'], 'inside/mlb-20-petco.jpg', 'outside/mlb-27-petco.png'),
    (['oracle', 'オラクル'], 'inside/mlb-16-oracle.jpg', 'outside/mlb-28-oracle.png'),
    (['chase', 'チェイス'], 'inside/mlb-12-chase.jpg', 'outside/mlb-29-chase.png'),
    (['coors', 'クアーズ'], 'inside/mlb-10-coors.jpg', 'outside/mlb-30-coors.png'),
  ];

  static String _norm(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\u3000・･·.\-ー−]'), '')
        .replaceAll('stadium', '')
        .replaceAll('field', '')
        .replaceAll('park', '')
        .replaceAll('スタジアム', '')
        .replaceAll('フィールド', '')
        .replaceAll('パーク', '');
  }

  static StadiumImagePaths lookup(String name) {
    final n = _norm(name);
    if (n.isEmpty) return const StadiumImagePaths();
    for (final entry in [..._npb, ..._mlb]) {
      for (final needle in entry.$1) {
        if (n.contains(_norm(needle))) {
          final inside = entry.$2.endsWith('/') ? '' : '$_root/${entry.$2}';
          final outside = '$_root/${entry.$3}';
          return StadiumImagePaths(inside: inside, outside: outside);
        }
      }
    }
    return const StadiumImagePaths();
  }

  static Future<Set<String>> _columnNames(Connection conn) async {
    final rows = await conn.execute(
      '''
        SELECT column_name::text
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'm_stadium'
      ''',
    );
    return {for (final row in rows) '${row[0]}'.toLowerCase()};
  }

  static Future<void> ensureColumns(Connection conn) async {
    final have = await _columnNames(conn);
    if (have.contains('path_image_inside') && have.contains('path_image_outside')) {
      return;
    }
    await conn.execute("SET lock_timeout = '2s'");
    try {
      if (!have.contains('path_image_inside')) {
        await conn.execute(
          "ALTER TABLE m_stadium ADD COLUMN IF NOT EXISTS path_image_inside VARCHAR(255) NOT NULL DEFAULT ''",
        );
      }
      if (!have.contains('path_image_outside')) {
        await conn.execute(
          "ALTER TABLE m_stadium ADD COLUMN IF NOT EXISTS path_image_outside VARCHAR(255) NOT NULL DEFAULT ''",
        );
      }
    } finally {
      try {
        await conn.execute("SET lock_timeout = '0'");
      } catch (_) {}
    }
  }

  static Future<int> seed(Connection conn) async {
    await ensureColumns(conn);
    final rows = await conn.execute(
      'SELECT id, name_short, name_full FROM m_stadium WHERE COALESCE(flg_delete, FALSE) = FALSE',
    );
    final values = <String>[];
    final params = <Object?>[];
    var i = 1;
    for (final row in rows) {
      final map = row.toColumnMap();
      final id = map['id'] as int;
      final paths = lookup('${map['name_short'] ?? ''} ${map['name_full'] ?? ''}');
      if (paths.inside.isEmpty && paths.outside.isEmpty) continue;
      values.add('(\$$i::int, \$${i + 1}::text, \$${i + 2}::text)');
      params.addAll([id, paths.inside, paths.outside]);
      i += 3;
    }
    if (values.isEmpty) return 0;
    await conn.execute(
      '''
        UPDATE m_stadium AS s
        SET path_image_inside = CASE WHEN v.inside = '' THEN s.path_image_inside ELSE v.inside END,
            path_image_outside = CASE WHEN v.outside = '' THEN s.path_image_outside ELSE v.outside END,
            updat = NOW()
        FROM (VALUES ${values.join(', ')}) AS v(id, inside, outside)
        WHERE s.id = v.id
          AND (
            s.path_image_inside IS DISTINCT FROM CASE WHEN v.inside = '' THEN s.path_image_inside ELSE v.inside END
            OR s.path_image_outside IS DISTINCT FROM CASE WHEN v.outside = '' THEN s.path_image_outside ELSE v.outside END
          )
      ''',
      parameters: params,
    );
    return values.length;
  }
}
