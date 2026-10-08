import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// 12球団の故障者リスト。復帰予定は「不明」「今期絶望」「全治N週間」などに揃える。
/// https://www.my-favorite-giants.net/npb/IL.htm
class InjuryList {
  static const pageUrl = 'https://www.my-favorite-giants.net/npb/IL.htm';

  static const _teamNeedles = <String, List<String>>{
    '巨人': ['ジャイアンツ', '巨人'],
    '読売': ['ジャイアンツ', '巨人'],
    '阪神': ['阪神'],
    '中日': ['中日'],
    '広島': ['広島', 'カープ'],
    'ヤクルト': ['ヤクルト'],
    'DeNA': ['DeNA', 'ベイスターズ'],
    '横浜': ['DeNA', 'ベイスターズ', '横浜'],
    'オリックス': ['オリックス'],
    'ロッテ': ['ロッテ', 'マリーンズ'],
    '楽天': ['楽天', 'イーグルス'],
    'ソフトバンク': ['ソフトバンク', 'ホークス'],
    '日本ハム': ['日本ハム', 'ファイターズ'],
    '西武': ['西武', 'ライオンズ'],
  };

  static List<String> _needlesFor(String team) {
    final hits = <String>[];
    for (final entry in _teamNeedles.entries) {
      if (team.contains(entry.key)) hits.addAll(entry.value);
    }
    if (hits.isNotEmpty) return hits.toSet().toList();
    return [team];
  }

  static Future<void> ensureSchema(Connection conn) async {
    await conn.execute("ALTER TABLE m_player ADD COLUMN IF NOT EXISTS txt_injury varchar(40) NOT NULL DEFAULT ''");
    await conn.execute("ALTER TABLE m_player ADD COLUMN IF NOT EXISTS txt_position varchar(16) NOT NULL DEFAULT ''");
    await conn.execute('ALTER TABLE m_player ADD COLUMN IF NOT EXISTS flg_injury boolean NOT NULL DEFAULT FALSE');
  }

  static String compactName(String raw) {
    return raw.replaceAll(RegExp(r'[■\s　]'), '').trim();
  }

  /// 表の「復帰予定・全治」を短い期間表記にする。
  static String periodLabel(String raw) {
    final text = raw.replaceAll(RegExp(r'\s+'), '').trim();
    if (text.isEmpty) return '不明';
    if (text.contains('今季絶望') || text.contains('今期絶望')) return '今期絶望';
    final weekRange = RegExp(r'全治(\d+)[〜～~\-ー](\d+)週間').firstMatch(text);
    if (weekRange != null) return '全治${weekRange.group(1)}〜${weekRange.group(2)}週間';
    final weeks = RegExp(r'全治(\d+)週間').firstMatch(text);
    if (weeks != null) return '全治${weeks.group(1)}週間';
    final monthRange = RegExp(r'全治(\d+)[〜～~\-ー](\d+)ヶ?月').firstMatch(text);
    if (monthRange != null) return '全治${monthRange.group(1)}〜${monthRange.group(2)}ヶ月';
    final months = RegExp(r'全治(\d+)ヶ?月').firstMatch(text);
    if (months != null) return '全治${months.group(1)}ヶ月';
    if (text.contains('不明')) return '不明';
    if (text.contains('長期')) return '長期見込';
    return text.length > 20 ? text.substring(0, 20) : text;
  }

  static List<({String team, String name, String position, String period})> parseHtml(String html) {
    final doc = parse(html);
    final rows = <({String team, String name, String position, String period})>[];
    var team = '';
    for (final tr in doc.querySelectorAll('tr')) {
      final cells = tr.querySelectorAll('td');
      if (cells.isEmpty) continue;
      if (cells.first.classes.contains('team')) {
        final label = cells.first.text.trim();
        if (label.isNotEmpty) team = label;
        continue;
      }
      final name = compactName(tr.querySelector('td.name')?.text ?? '');
      if (name.isEmpty) continue;
      final position = (tr.querySelector('td.pos')?.text ?? '').trim();
      final period = periodLabel(cells.last.text);
      rows.add((team: team, name: name, position: position, period: period));
    }
    return rows;
  }

  static Future<int> sync(Connection conn) async {
    await ensureSchema(conn);
    http.Response res;
    try {
      res = await http.get(Uri.parse(pageUrl)).timeout(const Duration(seconds: 30));
    } catch (e) {
      print('故障者リスト取得失敗: $e');
      return 0;
    }
    if (res.statusCode != 200) {
      print('故障者リストHTTP ${res.statusCode}');
      return 0;
    }
    final entries = parseHtml(res.body);
    if (entries.isEmpty) {
      print('故障者リストが空のため更新を見送る');
      return 0;
    }

    await conn.execute('''
      UPDATE m_player p
      SET flg_injury = FALSE,
          txt_injury = '',
          updat = NOW()
      FROM m_team t
      WHERE p.id_team = t.id
        AND t.id_league IN (1, 2)
        AND COALESCE(p.flg_injury, FALSE) = TRUE
    ''');

    final roster = await conn.execute('''
      SELECT
        p.id,
        regexp_replace(COALESCE(p.name_full, ''), '[[:space:]]', '', 'g') AS name,
        COALESCE(t.name_full, '') AS name_full,
        COALESCE(t.name_short, '') AS name_short,
        COALESCE(t.name_shortest, '') AS name_shortest
      FROM m_player p
      JOIN m_team t ON t.id = p.id_team
      WHERE t.id_league IN (1, 2)
        AND COALESCE(p.flg_delete, FALSE) = FALSE
    ''');

    var updated = 0;
    for (final entry in entries) {
      final needles = _needlesFor(entry.team);
      final matches = roster.where((row) {
        final map = row.toColumnMap();
        if ('${map['name']}' != entry.name) return false;
        final blob = '${map['name_full']} ${map['name_short']} ${map['name_shortest']}';
        return needles.any(blob.contains);
      }).toList();
      final targets = matches.isNotEmpty
          ? matches
          : roster.where((row) => '${row.toColumnMap()['name']}' == entry.name).toList();
      if (targets.length != 1 && matches.isEmpty) {
        print('故障者の選手を一意にできない: ${entry.team} ${entry.name}');
        continue;
      }
      for (final row in (matches.isNotEmpty ? matches : targets)) {
        final id = row.toColumnMap()['id'];
        await conn.execute(
          '''
            UPDATE m_player
            SET flg_injury = TRUE,
                txt_injury = \$2::varchar,
                updat = NOW()
            WHERE id = \$1::int
          ''',
          parameters: [id, entry.period],
        );
        updated++;
      }
    }
    print('故障者の登録数$updated');
    return updated;
  }
}
