import 'dart:io';
import 'package:postgres/postgres.dart';

class StadiumImagePaths {
  const StadiumImagePaths({this.inside = '', this.outside = '', this.generated = false});
  final bool generated;
  final String inside;
  final String outside;
}

/// 添付した球場画像。`m_stadium.path_image_inside` / `path_image_outside` に書く。
class StadiumImages {
  static const _root = 'backend/assets/images/stadiums';

  static const _regional = <String, String>{
    '札幌ドーム': 'regional-001-generated.jpg',
    '札幌市円山球場': 'regional-002-generated.jpg',
    '北見市営球場': 'regional-003-generated.jpg',
    '釧路市民球場': 'regional-004-generated.jpg',
    '帯広の森野球場': 'regional-005-generated.jpg',
    '花咲スポーツ公園硬式野球場': 'regional-006-generated.jpg',
    '夕張鹿の谷球場': 'regional-007-generated.jpg',
    '小樽桜ヶ丘球場': 'regional-008-generated.jpg',
    '室蘭新日鐵球場': 'regional-009-generated.jpg',
    '千代台公園野球場': 'regional-010-generated.jpg',
    '青森市営野球場': 'regional-011-generated.jpg',
    '青森県総合運動公園野球場': 'regional-012-generated.jpg',
    '弘前市運動公園野球場': 'regional-013-generated.jpg',
    '八戸市長根野球場': 'regional-014-generated.jpg',
    '盛岡南公園野球場': 'regional-015-generated.jpg',
    '花巻市営球場': 'regional-016-generated.jpg',
    '希望ヶ丘球場': 'regional-017-generated.jpg',
    '石巻水押球場': 'regional-018-generated.jpg',
    '評定河原野球場': 'regional-019-generated.jpg',
    '秋田県営手形野球場': 'regional-020-generated.jpg',
    '秋田市営八橋球場': 'regional-021-generated.jpg',
    '秋田県立野球場': 'regional-022-generated.jpg',
    '山形市総合スポーツセンター野球場': 'regional-023-generated.jpg',
    '山形県野球場': 'regional-024-generated.jpg',
    '米沢市営野球場': 'regional-025-generated.jpg',
    '酒田市営光ヶ丘野球場': 'regional-026-generated.jpg',
    '信夫ヶ丘球場': 'regional-027-generated.jpg',
    '福島県営あづま球場': 'regional-028-generated.jpg',
    '会津総合運動公園あいづ球場': 'regional-029-generated.jpg',
    '郡山総合運動場開成山野球場': 'regional-030-generated.jpg',
    '平市営球場': 'regional-031-generated.jpg',
    'いわきグリーンスタジアム': 'regional-032-generated.jpg',
    '茨城県営球場': 'regional-033-generated.jpg',
    '水戸市民球場': 'regional-034-generated.jpg',
    '日立会瀬球場': 'regional-035-generated.jpg',
    'ひたちなか市民球場': 'regional-036-generated.jpg',
    '土浦市営球場': 'regional-037-generated.jpg',
    '宇都宮総合球場': 'regional-038-generated.jpg',
    '宇都宮清原球場': 'regional-039-generated.jpg',
    '足利市営球場': 'regional-040-generated.jpg',
    '鹿沼御殿山球場': 'regional-041-generated.jpg',
    '大田原市営球場': 'regional-042-generated.jpg',
    '群馬県立敷島公園野球場': 'regional-043-generated.jpg',
    '高崎城南球場': 'regional-044-generated.jpg',
    '桐生球場': 'regional-045-generated.jpg',
    '太田市営東山球場': 'regional-046-generated.jpg',
    '沼田町公園球場': 'regional-047-generated.jpg',
    '埼玉県営大宮公園野球場': 'regional-048-generated.jpg',
    '川越初雁公園野球場': 'regional-049-generated.jpg',
    '浦和市営球場': 'regional-050-generated.jpg',
    '千葉県営野球場': 'regional-051-generated.jpg',
    '市川国府台球場': 'regional-052-generated.jpg',
    '銚子市営球場': 'regional-053-generated.jpg',
    '木更津市営野球場': 'regional-054-generated.jpg',
    '昭島市営球場': 'regional-055-generated.jpg',
    '八王子市営球場': 'regional-056-generated.jpg',
    '福生グラウンド': 'regional-057-generated.jpg',
    '神奈川県立保土ヶ谷野球場': 'regional-058-generated.jpg',
    '横須賀市営追浜球場': 'regional-059-generated.jpg',
    '相模原市立相模原球場': 'regional-060-generated.jpg',
    '茅ヶ崎市営球場': 'regional-061-generated.jpg',
    '平塚球場': 'regional-062-generated.jpg',
    '新潟市営鳥屋野野球場': 'regional-063-generated.jpg',
    '新潟県立鳥屋野潟公園野球場': 'regional-064-generated.jpg',
    '長岡市営悠久山野球場': 'regional-065-generated.jpg',
    '柏崎市佐藤池野球場': 'regional-066-generated.jpg',
    '三条市総合運動公園市民球場': 'regional-067-generated.jpg',
    '上越市営球場': 'regional-068-generated.jpg',
    '富山県営富山野球場': 'regional-069-generated.jpg',
    '富山市民球場': 'regional-070-generated.jpg',
    '高岡市営城光寺野球場': 'regional-071-generated.jpg',
    '石川県立野球場': 'regional-072-generated.jpg',
    '小松末広野球場': 'regional-073-generated.jpg',
    '福井県営球場': 'regional-074-generated.jpg',
    '敦賀市総合運動公園野球場': 'regional-075-generated.jpg',
    '山梨県営甲府飯田球場': 'regional-076-generated.jpg',
    '山梨県営甲府総合球場': 'regional-077-generated.jpg',
    '小瀬スポーツ公園野球場': 'regional-078-generated.jpg',
    '長野県営野球場': 'regional-079-generated.jpg',
    '南長野運動公園野球場': 'regional-080-generated.jpg',
    '松本市営球場': 'regional-081-generated.jpg',
    '松本市野球場': 'regional-082-generated.jpg',
    '上田市営野球場': 'regional-083-generated.jpg',
    '下諏訪町営球場': 'regional-084-generated.jpg',
    '飯田市営今宮球場': 'regional-085-generated.jpg',
    '市営岡谷球場': 'regional-086-generated.jpg',
    '伊那市営野球場': 'regional-087-generated.jpg',
    '岐阜県営長良川球場': 'regional-088-generated.jpg',
    '多治見市営球場': 'regional-089-generated.jpg',
    '静岡県草薙総合運動場硬式野球場': 'regional-090-generated.jpg',
    '沼津市営野球場': 'regional-091-generated.jpg',
    '島田球場': 'regional-092-generated.jpg',
    '磐田城山球場': 'regional-093-generated.jpg',
    '浜松球場': 'regional-094-generated.jpg',
    '豊橋市民球場': 'regional-095-generated.jpg',
    '豊川いなり外苑球場': 'regional-096-generated.jpg',
    '刈谷市営グラウンド': 'regional-097-generated.jpg',
    '挙母球場': 'regional-098-generated.jpg',
    '一宮市営球場': 'regional-099-generated.jpg',
    '津市営球場': 'regional-100-generated.jpg',
    '伊勢市営倉田山野球場': 'regional-101-generated.jpg',
    '松阪市営球場': 'regional-102-generated.jpg',
    '四日市市営球場': 'regional-103-generated.jpg',
    '滋賀県立彦根球場': 'regional-104-generated.jpg',
    '皇子山総合運動公園野球場': 'regional-105-generated.jpg',
    '西京極総合運動公園野球場': 'regional-106-generated.jpg',
    '福知山市民球場': 'regional-107-generated.jpg',
    '堺大浜球場': 'regional-108-generated.jpg',
    '神戸総合運動公園野球場': 'regional-109-generated.jpg',
    '明石公園野球場': 'regional-110-generated.jpg',
    '姫路市立姫路球場': 'regional-111-generated.jpg',
    '奈良市営球場': 'regional-112-generated.jpg',
    '奈良県立橿原球場': 'regional-113-generated.jpg',
    '和歌山県営紀三井寺球場': 'regional-114-generated.jpg',
    '米子市民球場': 'regional-115-generated.jpg',
    '倉吉市営野球場': 'regional-116-generated.jpg',
    '松江市営野球場': 'regional-117-generated.jpg',
    '浜田市設野球場': 'regional-118-generated.jpg',
    '島根県立浜山公園野球場': 'regional-119-generated.jpg',
    '岡山県営球場': 'regional-120-generated.jpg',
    '倉敷市営球場': 'regional-121-generated.jpg',
    '岡山県倉敷スポーツ公園野球場': 'regional-122-generated.jpg',
    '津山市営球場': 'regional-123-generated.jpg',
    '広島総合グランド野球場': 'regional-124-generated.jpg',
    '福山市竹ヶ端運動公園野球場': 'regional-125-generated.jpg',
    '広島県立びんご運動公園野球場': 'regional-126-generated.jpg',
    '御建公園野球場': 'regional-127-generated.jpg',
    '呉市二河野球場': 'regional-128-generated.jpg',
    'みよし運動公園野球場': 'regional-129-generated.jpg',
    '西京スタジアム': 'regional-130-generated.jpg',
    '岩国市民球場': 'regional-131-generated.jpg',
    '新南陽球場': 'regional-132-generated.jpg',
    '小野田市営球場': 'regional-133-generated.jpg',
    '厚狭球場': 'regional-134-generated.jpg',
    '徳山市営球場': 'regional-135-generated.jpg',
    '宇部市野球場': 'regional-136-generated.jpg',
    '下関球場': 'regional-137-generated.jpg',
    '徳島県営蔵本球場': 'regional-138-generated.jpg',
    '徳島県営鳴門球場': 'regional-139-generated.jpg',
    '香川県営野球場': 'regional-140-generated.jpg',
    '松山中央公園野球場': 'regional-141-generated.jpg',
    '今治市営球場': 'regional-142-generated.jpg',
    '高知市営球場': 'regional-143-generated.jpg',
    '北九州市民球場': 'regional-144-generated.jpg',
    '八幡桃園球場': 'regional-145-generated.jpg',
    '八幡大谷球場': 'regional-146-generated.jpg',
    '大牟田延命球場': 'regional-147-generated.jpg',
    'みどりの森県営球場': 'regional-148-generated.jpg',
    '杵島炭鉱グラウンド': 'regional-149-generated.jpg',
    '長崎県営野球場': 'regional-150-generated.jpg',
    '佐世保野球場': 'regional-151-generated.jpg',
    '島原市営球場': 'regional-152-generated.jpg',
    '熊本水前寺野球場': 'regional-153-generated.jpg',
    '藤崎台県営野球場': 'regional-154-generated.jpg',
    '大洲総合運動公園硬式野球場': 'regional-155-generated.jpg',
    '宮崎県総合運動公園硬式野球場': 'regional-156-generated.jpg',
    '宮崎市営球場': 'regional-157-generated.jpg',
    '都城市営球場': 'regional-158-generated.jpg',
    '鴨池市民球場': 'regional-159-generated.jpg',
    '鹿児島県立鴨池野球場': 'regional-160-generated.jpg',
    '那覇市営奥武山野球場': 'regional-161-generated.jpg',
    '台北市立天母棒球場': 'regional-162-generated.jpg',
  };

  static const _farm = <String, String>{
    'ジャイアンツタウンスタジアム': 'farm-01-generated.png',
    'ヤクルト戸田球場': 'farm-02-generated.png',
    'ファイターズ鎌ケ谷スタジアム': 'farm-03-generated.png',
    '横須賀スタジアム': 'farm-04-generated.png',
    '森林どりスタジアム泉': 'farm-05-generated.png',
    'ロッテ浦和球場': 'farm-06-generated.png',
    'CAR3219フィールド': 'farm-07-generated.png',
    'タマホーム スタジアム筑後': 'farm-08-generated.png',
    '杉本商事バファローズスタジアム舞洲': 'farm-09-generated.png',
    'ナゴヤ球場': 'farm-10-generated.png',
    '日鉄鋼板SGLスタジアム尼崎': 'farm-11-generated.png',
    '広島東洋カープ由宇練習場': 'farm-12-generated.png',
  };

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
    (['citizens', 'シチズンズ'], 'inside/mlb-21-citizens.jpg', 'outside/mlb-19-citizens.png'),
    (['citi field', 'シティ'], 'inside/mlb-24-citi.jpg', 'outside/mlb-18-citi.png'),
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

  static String _generatedPath(String view, String filename) {
    final replacement = filename.replaceFirst(RegExp(r'\.[^.]+$'), '-v2.png');
    final path = '$_root/$view/$replacement';
    final exists = File(path).existsSync() || File(path.replaceFirst('backend/', '')).existsSync() || File('public/assets/$path').existsSync() || File('backend/public/assets/$path').existsSync();
    return exists ? path : '$_root/$view/$filename';
  }

  static StadiumImagePaths lookup(String name) {
    final n = _norm(name);
    if (n.isEmpty) return const StadiumImagePaths();
    for (final entry in {..._regional, ..._farm}.entries) {
      if (n == _norm(entry.key)) {
        return StadiumImagePaths(inside: _generatedPath('inside', entry.value),
            outside: _generatedPath('outside', entry.value), generated: true);
      }
    }
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
