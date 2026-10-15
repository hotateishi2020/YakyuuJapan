import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/LowerLevelUsage.dart';
import 'app/StrengthUsage.dart';
import 'app/TeamStrength.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.first);
  final client = http.Client();
  try {
    final games = await LowerLevelUsage.fetch(client, year);
    final rows = await Postgres.withConnection((c) => c.execute(
        "SELECT payload FROM t_team_strength WHERE code_org='npb' AND int_year=\$1",
        parameters: [year]));
    final teams = [
      for (final r in rows)
        usageMap(r[0] is String ? jsonDecode(r[0] as String) : r[0])
    ];
    await LowerLevelUsage.save(year, teams, games,
        {for (final e in npbStrengthSources.entries) e.key: e.value.$2});
    if (args.length > 1) {
      final supplement =
          usageMap(jsonDecode(await File(args[1]).readAsString()));
      if (usageInt(supplement['year']) != year)
        throw FormatException('補足記録の年度が一致しません');
      final known = {
        for (final t in teams)
          for (final p in usageMaps(t['roster'])) '${p['source_player_id']}'
      };
      for (final level in [3, 4]) {
        final extra = usageMaps(supplement['$level']);
        for (final game in extra) {
          final url = Uri.tryParse('${game['game_key']}');
          if (url?.scheme != 'https') throw FormatException('公式出典URLが必要です');
          for (final p in usageMaps(game['players'])) {
            if (!known.contains('${p['source_player_id']}'))
              throw FormatException('名簿にない選手ID');
          }
        }
        if (extra.isNotEmpty) {
          await LowerLevelUsage.save(year, teams, extra,
              {for (final e in npbStrengthSources.entries) e.key: e.value.$2},
              level: level, coverage: 'verified_partial');
          print('$level軍の確認済み${extra.length}試合を補足しました');
        }
      }
    }
    // Merge into the current payload atomically, without replacing other metrics.
    await Postgres.withConnection((c) => c.execute(
        '''UPDATE t_team_strength t SET payload=jsonb_set(t.payload,'{roster}',
      (SELECT jsonb_agg(p || COALESCE((SELECT s.payload FROM t_strength_player_status s
       WHERE s.code_org=t.code_org AND s.int_year=t.int_year AND s.id_team=t.id_team AND s.player_key=p->>'player_key'),'{}'::jsonb))
       FROM jsonb_array_elements(t.payload->'roster') p))
      WHERE t.code_org='npb' AND t.int_year=\$1''',
        parameters: [year]));
    print('2軍${games.length}試合・${teams.length}球団の起用情報を登録しました');
    exit(0);
  } catch (e) {
    stderr.writeln('下部組織起用情報取得失敗: $e');
    exit(1);
  } finally {
    client.close();
  }
}
