import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/PlayerCountry.dart';

/// Enrich existing snapshots without rebuilding scores, predictions or stats.
Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.single);
  await Postgres.withConnection((conn) async {
    final ids = await conn.execute('''
      SELECT DISTINCT id FROM (
        SELECT payload->>'id_player' AS id FROM v_stats_player WHERE int_year=\$1
        UNION
        SELECT p->>'id_player' FROM v_games_details g
        CROSS JOIN LATERAL jsonb_array_elements(COALESCE(g.payload->'player_hands','[]'::jsonb)) p
        WHERE g.int_year=\$1 AND g.code='form'
      ) players WHERE id ~ '^[0-9]+\$'
    ''', parameters: [year]);
    final rows = [
      for (final id in ids)
        <String, dynamic>{'id_player': int.parse('${id[0]}')}
    ];
    await attachPlayerCountries(conn, year, rows);
    final countries = {
      for (final r in rows.where((r) => r.containsKey('emoji_display_country')))
        '${r['id_player']}': Map<String, dynamic>.from(r)..remove('id_player')
    };
    final encoded = jsonEncode(countries);
    await conn.runTx((tx) async {
      await tx.execute(
          '''UPDATE v_stats_player SET payload=payload || (\$2::jsonb -> (payload->>'id_player'))
        WHERE int_year=\$1 AND \$2::jsonb ? (payload->>'id_player')''',
          parameters: [year, encoded]);
      await tx.execute(
          '''UPDATE v_games_details g SET payload=jsonb_set(payload,'{player_hands}',
        (SELECT jsonb_agg(p || COALESCE(\$2::jsonb -> (p->>'id_player'),'{}'::jsonb) ORDER BY ord)
          FROM jsonb_array_elements(g.payload->'player_hands') WITH ORDINALITY AS players(p,ord)))
        WHERE int_year=\$1 AND code='form' AND jsonb_array_length(COALESCE(payload->'player_hands','[]'::jsonb))>0''',
          parameters: [year, encoded]);
    });
    print('国旗スナップショット更新: $year / ${countries.length} 選手');
  });
  exit(0);
}
