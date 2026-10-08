import 'package:html/dom.dart';
import 'package:postgres/postgres.dart';

import '../tools/Postgres.dart';
import 'DB/m_country.dart';
import 'DB/m_place_birth.dart';

/// 出身地テキストから国・出身地（県/州）を解決し、m_country / m_place_birth / m_player へ反映する。
class BirthPlaceRegistry {
  static const japanName = '日本';
  static const japanEmoji = '🇯🇵';

  static const _countryEmojis = <String, String>{
    '日本': '🇯🇵',
    'アメリカ': '🇺🇸',
    '米国': '🇺🇸',
    'カナダ': '🇨🇦',
    'メキシコ': '🇲🇽',
    'ドミニカ共和国': '🇩🇴',
    'ドミニカ': '🇩🇴',
    'ベネズエラ': '🇻🇪',
    'キューバ': '🇨🇺',
    'プエルトリコ': '🇵🇷',
    'コロンビア': '🇨🇴',
    'パナマ': '🇵🇦',
    'ニカラグア': '🇳🇮',
    'ホンジュラス': '🇭🇳',
    'ブラジル': '🇧🇷',
    'キュラソー': '🇨🇼',
    'アルバ': '🇦🇼',
    '韓国': '🇰🇷',
    '台湾': '🇹🇼',
    '中国': '🇨🇳',
    'オーストラリア': '🇦🇺',
    'オランダ': '🇳🇱',
    'ドイツ': '🇩🇪',
    'イタリア': '🇮🇹',
    '南アフリカ': '🇿🇦',
  };

  /// Yahoo 選手ページの `dt 出身地` を読む。
  static String? extractFromProfile(Document doc) {
    for (final dt in doc.querySelectorAll('dt')) {
      final label = dt.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!label.contains('出身')) continue;
      final value = dt.nextElementSibling?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  /// Yahoo の `生年月日（満年齢）` → `1998年8月17日（28歳）` を DateTime にする。
  static DateTime? extractBirthDate(Document doc) {
    for (final dt in doc.querySelectorAll('dt')) {
      final label = dt.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!label.contains('生年月日')) continue;
      final value = dt.nextElementSibling?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      final parsed = parseBirthDateText(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static DateTime? parseBirthDateText(String raw) {
    final m = RegExp(r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日').firstMatch(raw);
    if (m == null) return null;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  static Future<void> applyBirthDate(Connection conn, int playerId, DateTime? birth) async {
    if (playerId <= 0 || birth == null) return;
    final ymd =
        '${birth.year.toString().padLeft(4, '0')}-${birth.month.toString().padLeft(2, '0')}-${birth.day.toString().padLeft(2, '0')}';
    await conn.execute(
      '''
        UPDATE m_player
        SET date_birth = \$1::date,
            updat = NOW()
        WHERE id = \$2::int
          AND date_birth IS DISTINCT FROM \$1::date
      ''',
      parameters: [ymd, playerId],
    );
  }

  /// 選手に出身地を反映。未登録の国・県/州は作成する。既に両方入っている選手はスキップ。
  static Future<void> applyToPlayer(Connection conn, int playerId, String? birthplaceRaw) async {
    if (playerId <= 0) return;
    final text = (birthplaceRaw ?? '').trim();
    if (text.isEmpty) return;

    final existing = await conn.execute(
      '''
        SELECT id_country, id_place_birth
        FROM m_player
        WHERE id = \$1::int
        LIMIT 1
      ''',
      parameters: [playerId],
    );
    if (existing.isEmpty) return;
    final row = existing.first.toColumnMap();
    final hasCountry = row['id_country'] != null && '${row['id_country']}' != '0';
    final hasPlace = row['id_place_birth'] != null && '${row['id_place_birth']}' != '0';
    if (hasCountry && hasPlace) return;

    final parsed = parse(text);
    int? countryId = hasCountry ? int.tryParse('${row['id_country']}') : null;
    int? placeId = hasPlace ? int.tryParse('${row['id_place_birth']}') : null;

    if (!hasCountry && parsed.countryName != null) {
      countryId = await ensureCountry(conn, parsed.countryName!);
    }
    if (!hasPlace && parsed.placeName != null && countryId != null && countryId > 0) {
      placeId = await ensurePlace(conn, parsed.placeName!, countryId);
    }

    if (countryId == null && placeId == null) return;
    await conn.execute(
      '''
        UPDATE m_player
        SET id_country = COALESCE(\$1::int, id_country),
            id_place_birth = COALESCE(\$2::int, id_place_birth),
            updat = NOW()
        WHERE id = \$3::int
      ''',
      parameters: [countryId, placeId, playerId],
    );
  }

  /// プロフィール HTML から出身地を取り、選手へ反映する。
  static Future<void> applyFromProfile(Connection conn, int playerId, Document doc) async {
    await applyToPlayer(conn, playerId, extractFromProfile(doc));
  }

  static bool _nameWidthReady = false;

  static Future<void> ensureSchema(Connection conn) async {
    if (_nameWidthReady) return;
    await conn.execute('ALTER TABLE m_country ALTER COLUMN name TYPE varchar(80)');
    _nameWidthReady = true;
  }

  static Future<int> ensureCountry(Connection conn, String rawName) async {
    await ensureSchema(conn);
    final name = _normalizeCountryName(rawName);
    if (name.isEmpty) return 0;
    final found = await conn.execute(
      '''
        SELECT id FROM m_country
        WHERE name = \$1::text
          AND COALESCE(flg_delete, FALSE) = FALSE
        LIMIT 1
      ''',
      parameters: [name],
    );
    if (found.isNotEmpty) {
      final id = found.first.toColumnMap()['id'] as int;
      final emoji = _countryEmojis[name] ?? '';
      if (emoji.isNotEmpty) {
        await conn.execute(
          '''
            UPDATE m_country
            SET emoji = CASE WHEN COALESCE(emoji, '') = '' THEN \$1::text ELSE emoji END,
                updat = NOW()
            WHERE id = \$2::int
          ''',
          parameters: [emoji, id],
        );
      }
      return id;
    }
    final country = m_country()
      ..name = name
      ..emoji = _countryEmojis[name] ?? ''
      ..crtpgm = 'BirthPlaceRegistry'
      ..updpgm = 'BirthPlaceRegistry'
      ..crtenv = 'BirthPlaceRegistry'
      ..updenv = 'BirthPlaceRegistry';
    return Postgres.insert(conn, country);
  }

  static Future<int> ensurePlace(Connection conn, String rawName, int countryId) async {
    final name = rawName.trim();
    if (name.isEmpty || countryId <= 0) return 0;
    final found = await conn.execute(
      '''
        SELECT id FROM m_place_birth
        WHERE name = \$1::text
          AND id_country = \$2::int
          AND COALESCE(flg_delete, FALSE) = FALSE
        LIMIT 1
      ''',
      parameters: [name, countryId],
    );
    if (found.isNotEmpty) return found.first.toColumnMap()['id'] as int;
    final place = m_place_birth()
      ..name = name
      ..id_country = countryId
      ..crtpgm = 'BirthPlaceRegistry'
      ..updpgm = 'BirthPlaceRegistry'
      ..crtenv = 'BirthPlaceRegistry'
      ..updenv = 'BirthPlaceRegistry';
    return Postgres.insert(conn, place);
  }

  /// 「日本」「沖縄県」「カリフォルニア州」などを国名と出身地名に分ける。
  static ({String? countryName, String? placeName}) parse(String raw) {
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return (countryName: null, placeName: null);

    // 「カリフォルニア州, アメリカ」や「沖縄県 / 日本」
    final parts = text.split(RegExp(r'[,，/／]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) {
      final left = parts[0];
      final right = parts[1];
      if (_looksLikePlace(left) && _isKnownCountry(right)) {
        return (countryName: _normalizeCountryName(right), placeName: _stripPlaceSuffix(left));
      }
      if (_isKnownCountry(left) && _looksLikePlace(right)) {
        return (countryName: _normalizeCountryName(left), placeName: _stripPlaceSuffix(right));
      }
      if (_isKnownCountry(right)) {
        return (countryName: _normalizeCountryName(right), placeName: left);
      }
      if (_isKnownCountry(left)) {
        return (countryName: _normalizeCountryName(left), placeName: right);
      }
    }

    if (_isKnownCountry(text)) {
      return (countryName: _normalizeCountryName(text), placeName: null);
    }
    if (_looksLikeJapanPref(text)) {
      return (countryName: japanName, placeName: _stripPlaceSuffix(text));
    }
    if (_looksLikePlace(text)) {
      // 州名だけで国が不明なときはアメリカ扱い（MLB Yahoo の典型）。
      final place = _stripPlaceSuffix(text);
      final country = text.contains('州') || RegExp(r'[A-Za-z]').hasMatch(text) ? 'アメリカ' : null;
      return (countryName: country, placeName: place);
    }
    // 未知の国名として登録する。
    return (countryName: text, placeName: null);
  }

  static bool _isKnownCountry(String raw) {
    final name = _normalizeCountryName(raw);
    return _countryEmojis.containsKey(name);
  }

  static String _normalizeCountryName(String raw) {
    final t = raw.trim();
    if (t == '米国' || t.toLowerCase() == 'usa' || t.toLowerCase() == 'u.s.a.' || t.toLowerCase() == 'united states') {
      return 'アメリカ';
    }
    if (t == 'ドミニカ') return 'ドミニカ共和国';
    return t;
  }

  static const _japanPrefShort = {
    '北海道',
    '青森',
    '岩手',
    '宮城',
    '秋田',
    '山形',
    '福島',
    '茨城',
    '栃木',
    '群馬',
    '埼玉',
    '千葉',
    '東京',
    '神奈川',
    '新潟',
    '富山',
    '石川',
    '福井',
    '山梨',
    '長野',
    '岐阜',
    '静岡',
    '愛知',
    '三重',
    '滋賀',
    '京都',
    '大阪',
    '兵庫',
    '奈良',
    '和歌山',
    '鳥取',
    '島根',
    '岡山',
    '広島',
    '山口',
    '徳島',
    '香川',
    '愛媛',
    '高知',
    '福岡',
    '佐賀',
    '長崎',
    '熊本',
    '大分',
    '宮崎',
    '鹿児島',
    '沖縄',
  };

  static bool _looksLikeJapanPref(String text) {
    return RegExp(r'(都|道|府|県)$').hasMatch(text) || _japanPrefShort.contains(text);
  }

  static bool _looksLikePlace(String text) {
    if (_looksLikeJapanPref(text)) return true;
    if (RegExp(r'州$').hasMatch(text)) return true;
    // 英語の州・都市っぽい単語（国名リストに無いもの）
    if (RegExp(r"^[A-Za-z .'\-]+$").hasMatch(text) && !_isKnownCountry(text)) return true;
    return false;
  }

  static String _stripPlaceSuffix(String text) {
    final t = text.trim();
    if (t == '北海道' || _japanPrefShort.contains(t)) return t;
    return t.replaceFirst(RegExp(r'(都|道|府|県|州)$'), '');
  }
}
