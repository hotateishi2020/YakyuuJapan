import 'dart:convert';
import 'dart:io';
import 'InjuryResearch.dart';
import 'NpbResearchPolicy.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// 12球団の故障者リスト。復帰予定は「不明」「今期絶望」「全治N週間」などに揃える。
/// 球団発表と報道をChatGPT APIで調査する。
class InjuryList {
  static bool _busy = false;
  static const excludedHost = 'my-favorite-giants.net';

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
    final rows = await conn.execute("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='m_player'");
    final existing = rows.map((r) => '${r[0]}').toSet();
    for (final column in <String, String>{
      'txt_injury': "varchar(40) NOT NULL DEFAULT ''",
      'txt_position': "varchar(16) NOT NULL DEFAULT ''",
      'flg_injury': 'boolean NOT NULL DEFAULT FALSE',
    }.entries) {
      if (!existing.contains(column.key)) await conn.execute('ALTER TABLE m_player ADD COLUMN IF NOT EXISTS ${column.key} ${column.value}');
    }
    await conn.execute('CREATE TABLE IF NOT EXISTS t_player_injury_details (id_player integer PRIMARY KEY, payload jsonb NOT NULL)');
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

  /// Display requests only read registered data, including older schemas.
  static Future<List<Map<String, dynamic>>> read(Connection conn, {required List<int> leagueIds}) async {
    final ready = await conn.execute("SELECT to_regclass('public.t_player_injury_details') IS NOT NULL");
    final hasDetails = ready.first[0] == true;
    final rows = await conn.execute("""
      SELECT p.id AS id_player, p.name_full AS name_player, p.id_team,
        t.name_short AS name_team, t.color_back, t.color_font, t.id_league,
        p.txt_injury AS return_period, ${hasDetails ? 'd.payload' : 'NULL::jsonb'} AS injury_info
      FROM m_player p JOIN m_team t ON t.id=p.id_team
      ${hasDetails ? 'LEFT JOIN t_player_injury_details d ON d.id_player=p.id' : ''}
      WHERE COALESCE(p.flg_injury, false) AND NOT COALESCE(p.flg_delete, false)
        AND t.id_league=ANY(\$1::int[])
        ${hasDetails ? "AND COALESCE(d.payload->>'source_url','') NOT LIKE '%my-favorite-giants.net%'" : ''}
      ORDER BY t.id_league, t.id, p.name_full, p.id
    """, parameters: [leagueIds]);
    return [for (final row in rows) (() {
      final map = row.toColumnMap();
      final raw = map.remove('injury_info');
      final info = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      return <String, dynamic>{...map, for(final key in ['injury','injured_at','return_at','estimated','checked_at']) if(info.containsKey(key)) key: info[key], 'return_at': info['return_at'] ?? map['return_period']};
    })()];
  }

  /// Remove only records attributable to the discontinued source.
  static Future<int> removeExcludedSource(Connection conn) async {
    await ensureSchema(conn);
    return conn.runTx((tx) async {
      final removed = await tx.execute("DELETE FROM t_player_injury_details WHERE payload->>'source_url' LIKE '%my-favorite-giants.net%' RETURNING id_player");
      if (removed.isNotEmpty) {
        await tx.execute("UPDATE m_player SET flg_injury=false,txt_injury='',updat=NOW() WHERE id=ANY(\$1::int[])", parameters: [removed.map((r) => r[0] as int).toList()]);
      }
      return removed.length;
    });
  }

  static Future<int> sync(Connection conn) async {
    if (_busy) return 0;
    _busy = true;
    final client = http.Client();
    var locked = false;
    try {
      final removed = await removeExcludedSource(conn);
      if (removed > 0) print('旧サイト由来の怪我人情報を除去: $removed件');
      final key = Platform.environment['OPENAI_API_KEY'] ?? '';
      final model = Platform.environment['OPENAI_INJURY_MODEL'] ?? Platform.environment['OPENAI_RESEARCH_MODEL'] ?? '';
      if (key.isEmpty || model.isEmpty) {
        print('怪我人API調査保留: OPENAI_API_KEY と OPENAI_INJURY_MODEL（またはOPENAI_RESEARCH_MODEL）が未設定');
        return 0;
      }
      locked = (await conn.execute('SELECT pg_try_advisory_lock(78264319)')).first[0] == true;
      if (!locked) return 0;
      await conn.execute('CREATE TABLE IF NOT EXISTS t_injury_research_run (run_day date PRIMARY KEY, checked_at timestamptz NOT NULL DEFAULT NOW())');
      final now = researchJst(DateTime.now().toUtc());
      final day = researchDate(now);
      if ((await conn.execute('SELECT 1 FROM t_injury_research_run WHERE run_day=\$1::date', parameters: [day])).isNotEmpty) return 0;
      final current = await read(conn, leagueIds: [1,2]);
      final events = await InjuryResearch.query(client, key: key, model: model, day: day,
        current: [for(final p in current) {'team':p['name_team'],'name':p['name_player']}]);
      final accepted = <Map<String, dynamic>>[];
      final pages = <String, String>{};
      for (final event in events) {
        final url = '${event['source_url']}';
        if (!injurySource(url)) throw const FormatException('調査結果に対象外サイト');
        pages[url] ??= await InjuryResearch.source(client, url);
        if (!InjuryResearch.validate(event, pages[url]!, now)) throw const FormatException('怪我人情報の根拠を確認できません');
        accepted.add(event);
      }
      final roster = await conn.execute("SELECT p.id,p.name_full AS name,t.name_short AS team FROM m_player p JOIN m_team t ON t.id=p.id_team WHERE t.id_league IN (1,2) AND NOT COALESCE(p.flg_delete,false)");
      var updated = 0;
      await conn.runTx((tx) async {
        for (final event in accepted) {
          final matches = roster.where((r) => compactName('${r[1]}') == compactName('${event['name']}') &&
            _needlesFor('${event['team']}').any((n) => '${r[2]}'.contains(n))).toList();
          if (matches.isEmpty) continue;
          final injured = event['status'] == 'injured';
          final period = periodLabel('${event['return_at'] ?? '不明'}');
          for (final row in matches) {
            final old = await tx.execute("SELECT payload->>'source_as_of' FROM t_player_injury_details WHERE id_player=\$1 FOR UPDATE", parameters: [row[0]]);
            if (old.isNotEmpty && '${old.first[0] ?? ''}'.compareTo('${event['source_as_of']}') > 0) continue;
            await tx.execute("UPDATE m_player SET flg_injury=\$2,txt_injury=\$3,updat=NOW() WHERE id=\$1", parameters: [row[0], injured, injured ? period : '']);
            await tx.execute('INSERT INTO t_player_injury_details(id_player,payload) VALUES (\$1,\$2::jsonb) ON CONFLICT(id_player) DO UPDATE SET payload=EXCLUDED.payload', parameters: [row[0],jsonEncode({
              ...event, 'return_at': period, 'provider': 'openai_research',
              'checked_at': DateTime.now().toUtc().toIso8601String(),
            })]);
            updated++;
          }
        }
        await tx.execute('INSERT INTO t_injury_research_run(run_day) VALUES (\$1::date) ON CONFLICT DO NOTHING',parameters:[day]);
      });
      return updated;
    } finally {
      if (locked) await conn.execute('SELECT pg_advisory_unlock(78264319)');
      client.close();
      _busy = false;
    }
  }
}
