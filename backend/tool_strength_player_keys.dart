import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app/TeamStrength.dart';
import 'tools/Postgres.dart';

/// 既存の戦力成績を変えず、全表示行の選手キーだけを補完する。
/// dart run tool_strength_player_keys.dart [year]
Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.single);
  final original = await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''
      SELECT code_org, id_team, payload FROM t_team_strength
      WHERE int_year = \$1 ORDER BY code_org, id_team
    ''', parameters: [year]);
    return [
      for (final row in rows)
        {
          'org': row[0],
          'id_team': row[1],
          'payload': row[2] is String ? jsonDecode(row[2] as String) : row[2],
        },
    ];
  });
  if (original.isEmpty) throw StateError('登録済み戦力データがありません: $year');
  final backup = File('${Directory.systemTemp.path}/koko-strength-player-keys-$year-${DateTime.now().millisecondsSinceEpoch}.json');
  await backup.writeAsString(jsonEncode(original));
  final updates = <Map<String, dynamic>>[];
  final client = http.Client();
  var aliasesCount = 0;
  try {
    for (final record in original) {
      final payload = Map<String, dynamic>.from(record['payload'] as Map);
      final aliases = <String, String>{};
      if (record['org'] == 'npb') {
        final source = npbStrengthSources[payload['name_team']];
        if (source == null) throw StateError('NPB球団対応がありません');
        final url = 'https://npb.jp/bis/$year/stats/idp1_${source.$2}.html';
        final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException('投手名簿取得失敗 ${response.statusCode}', uri: Uri.parse(url));
        }
        final official = parseNpbPitchers(utf8.decode(response.bodyBytes));
        if (official.isEmpty) {
          throw StateError('公式投手名簿が空です: ${payload['name_team']}');
        }
        final position = (payload['positions'] as List).where((row) => row['slot'] == 'P').single;
        final starterNames = (position['players'] as List).map((row) => '${row['name']}');
        aliases.addAll(npbStrengthPlayerAliases(official, starterNames));
        final knownPitchers = (payload['pitchers'] as Map).values.expand((group) => group as List).map((row) => '${row['name']}').toSet();
        if (aliases.values.any((name) => !knownPitchers.contains(name))) {
          throw StateError('保存済み投手と公式名簿の一致を確認できません: ${payload['name_team']}');
        }
        aliasesCount += aliases.length;
      }
      final keyed = withStrengthPlayerKeys(payload, playerAliases: aliases);
      final pitchers = (keyed['pitchers'] as Map).values.expand((group) => group as List);
      final players = ['batting_order', 'positions'].expand((field) => keyed[field] as List).expand((group) => group['players'] as List);
      if ([...pitchers, ...players].any((row) => '${row['player_key'] ?? ''}'.isEmpty)) {
        throw StateError('選手キーのない行があります: ${payload['name_team']}');
      }
      updates.add({...record, 'next_payload': keyed});
    }
  } finally {
    client.close();
  }
  await Postgres.withConnection((conn) async {
    await conn.execute('BEGIN');
    try {
      final result = await conn.execute('''
        UPDATE t_team_strength AS target
        SET payload = source.next_payload
        FROM jsonb_to_recordset(\$2::jsonb)
          AS source(org text, id_team integer, payload jsonb, next_payload jsonb)
        WHERE target.int_year = \$1 AND target.code_org = source.org
          AND target.id_team = source.id_team AND target.payload = source.payload
      ''', parameters: [year, jsonEncode(updates)]);
      if (result.affectedRows != updates.length) {
        throw StateError('処理中に成績が更新されたため中止します');
      }
      await conn.execute('COMMIT');
      print(jsonEncode({'updated': result.affectedRows, 'npb_aliases': aliasesCount, 'backup': backup.path}));
    } catch (_) {
      await conn.execute('ROLLBACK');
      rethrow;
    }
  });
  exit(0);
}
