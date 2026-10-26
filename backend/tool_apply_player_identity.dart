import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'tools/Postgres.dart';
import 'app/DB/m_player_career.dart';
import 'app/DisplaySnapshot.dart';
import 'app/PlayerIdentity.dart';

/// Applies only an evidence-backed, reviewable plan; archives all changed rows.
Future<void> main(List<String> args) async {
  final planPath = args.where((a) => a.startsWith('--plan=')).firstOrNull?.substring(7) ?? 'data/player-identity-plan.json';
  final plan = jsonDecode(File(planPath).readAsStringSync()) as Map;
  final groups = List<Map<String, dynamic>>.from((plan['groups'] as List).map((p) => Map<String, dynamic>.from(p)));
  if (!args.contains('--apply') && !args.contains('--check')) {
    print('Dry run: ${groups.length} identities, ${groups.fold<int>(0, (n, p) => n + (p['merge_ids'] as List).length)} aliases to merge. Use --apply.');
    return;
  }
  final runId = DateTime.now().toUtc().toIso8601String();
  await Postgres.withConnection((conn) async {
    try {
      await conn.runTx((tx) async {
        await tx.execute("SET LOCAL lock_timeout='5s'");
        await tx.execute("SELECT pg_advisory_xact_lock(hashtext('koko-player-registration'))");
        await tx.execute('CREATE TEMP TABLE identity_plan(payload jsonb) ON COMMIT DROP');
        await tx.execute('INSERT INTO identity_plan SELECT value FROM jsonb_array_elements(\$1::jsonb)', parameters: [jsonEncode(groups)]);
        await tx.execute('''CREATE TEMP TABLE identity_map ON COMMIT DROP AS
     SELECT (payload->>'canonical_id')::int new_id, value::int old_id
     FROM identity_plan CROSS JOIN LATERAL jsonb_array_elements_text(payload->'merge_ids')''');
        await tx.execute('CREATE UNIQUE INDEX ON identity_map(old_id)');
        await tx.execute('CREATE TEMP TABLE identity_affected ON COMMIT DROP AS SELECT old_id id FROM identity_map UNION SELECT new_id FROM identity_map UNION SELECT (payload->>\'canonical_id\')::int FROM identity_plan');
        final locked = await tx.execute('SELECT p.id FROM m_player p JOIN identity_affected a ON a.id=p.id FOR UPDATE');
        final expected = groups.expand((p) => [p['canonical_id'], ...(p['merge_ids'] as List)]).toSet();
        if (locked.length != expected.length) {
          throw StateError('Identity plan is stale: missing IDs');
        }
        final stale = await tx.execute('SELECT p.id FROM m_player p JOIN identity_affected a ON a.id=p.id WHERE p.merged_into_player_id IS NOT NULL');
        if (stale.isNotEmpty) {
          throw StateError('Plan already applied or changed; rebuild the plan');
        }
        await tx.execute('''CREATE TABLE IF NOT EXISTS t_player_identity_migration_backup(
     run_id text,table_name text,rows jsonb NOT NULL,PRIMARY KEY(run_id,table_name))''');
        final references = await tx.execute("""SELECT c.table_name,c.column_name FROM information_schema.columns c
     JOIN information_schema.tables t ON t.table_name=c.table_name AND t.table_schema=c.table_schema AND t.table_type='BASE TABLE'
     WHERE c.table_schema='public' AND c.data_type='integer'
     AND (c.column_name IN ('id_player','id_player_fav','id_batter','id_pitcher','id_player_enter','id_player_exit')
       OR c.column_name IN ('id_pitcher_home','id_pitcher_away','id_pitcher_win','id_pitcher_lose','id_pitcher_save'))
     ORDER BY c.table_name,c.column_name""");
        final refs = <String, List<String>>{};
        for (final r in references) {
          refs.putIfAbsent('${r[0]}', () => []).add('${r[1]}');
        }
        for (final entry in {
          'm_player': ['id'],
          ...refs
        }.entries) {
          final where = entry.value.map((c) => '$c IN (SELECT id FROM identity_affected)').join(' OR ');
          await tx.execute('INSERT INTO t_player_identity_migration_backup SELECT \$1,\$2,coalesce(jsonb_agg(to_jsonb(t)),\'[]\'::jsonb) FROM ${entry.key} t WHERE $where', parameters: [runId, entry.key]);
        }
        await tx.execute('''INSERT INTO t_player_identity_merge(old_id,canonical_id,evidence,original_player)
     SELECT m.old_id,m.new_id,p.payload->'evidence',to_jsonb(old)
     FROM identity_map m JOIN m_player old ON old.id=m.old_id
     JOIN identity_plan p ON (p.payload->>'canonical_id')::int=m.new_id''');
        for (final split in plan['role_splits'] as List? ?? []) {
          await splitConfusedRoles(tx, Map<String, dynamic>.from(split));
        }
        // Deduplicate tables with natural/composite keys before redirecting foreign IDs.
        final uniqueKeys = <String, List<String>>{
          't_player_season_usage': ['int_year'],
          't_player_detail_snapshot': ['int_year'],
          't_player_art': ['fingerprint'],
          't_player_art_roster': [],
          't_player_injury_details': [],
          't_stats_player_latest': ['id_league', 'id_stats', 'id_team'],
          't_stats_player': ['int_year', 'id_league', 'id_stats', 'id_team'],
        };
        for (final entry in uniqueKeys.entries) {
          if (!refs.containsKey(entry.key)) continue;
          final partition = ['coalesce(m.new_id,t.id_player)', ...entry.value.map((c) => 't.$c')].join(',');
          await tx.execute('''WITH duplicates AS (
       SELECT t.ctid,row_number() OVER(PARTITION BY $partition
         ORDER BY (m.old_id IS NULL) DESC,t.ctid) n
       FROM ${entry.key} t LEFT JOIN identity_map m ON m.old_id=t.id_player
       WHERE t.id_player IN(SELECT id FROM identity_affected))
       DELETE FROM ${entry.key} t USING duplicates d WHERE t.ctid=d.ctid AND d.n>1''');
        }
        // A two-way player has batting and pitching blocks. Select each complete block
        // independently; never add duplicated season or game totals together.
        final careerFields = m_player_career().toMap().keys.toList();
        final pitchingStart = careerFields.indexOf('int_pitching');
        final batting = careerFields.sublist(careerFields.indexOf('int_games'), pitchingStart);
        final pitching = careerFields.sublist(pitchingStart);
        await consolidate(tx, 'm_player_career', ['int_year', 'id_team'], batting, pitching, 'int_appearance', 'double_inning');
        await consolidate(tx, 't_game_summary', ['id_game'], ['int_batting', 'int_homerun', 'txt_homerun_total', 'int_hit3', 'int_hit2', 'int_hit1', 'int_fourball', 'int_dead_batting', 'int_sacrifice', 'int_rbi', 'int_steal_base', 'int_error', 'int_batting_order', 'code_position_from'], ['double_inning_pitch', 'int_pitch', 'int_hit', 'int_strike_out', 'int_four', 'int_dead_pitching', 'int_balk', 'int_runs', 'int_runs_earned', 'code_result_pitcher'], 'int_batting', 'double_inning_pitch');
        await tx.execute('DELETE FROM t_game_summary t USING identity_t_game_summary d WHERE t.id=d.id AND d.id<>d.keeper');
        for (final entry in refs.entries) {
          for (final column in entry.value) {
            await tx.execute('UPDATE ${entry.key} t SET $column=m.new_id FROM identity_map m WHERE t.$column=m.old_id');
          }
        }
        // Retired rows remain redirect records, so old bookmarks can be resolved.
        await tx.execute('''UPDATE m_player p SET flg_delete=true,merged_into_player_id=m.new_id,
      source_key=NULL,external_id=NULL,updat=now() FROM identity_map m WHERE p.id=m.old_id''');
        await tx.execute('''UPDATE m_player p SET
     name_patterns=p.name_patterns || ARRAY(SELECT jsonb_array_elements_text(q.payload->'patterns'))
       || ARRAY(SELECT unnest(old.name_patterns) FROM m_player old JOIN identity_map m ON m.old_id=old.id WHERE m.new_id=p.id),
     name_ja=coalesce(nullif(q.payload->>'name_ja',''),p.name_ja),
     name_en=coalesce(nullif(q.payload->>'name_en',''),p.name_en,
       (SELECT nullif(old.name_en,'') FROM m_player old JOIN identity_map m ON m.old_id=old.id WHERE m.new_id=p.id AND coalesce(old.name_en,'')<>'' ORDER BY old.id LIMIT 1)),
     id_team=coalesce((q.payload->>'team_id')::int,p.id_team),
     date_birth=coalesce((q.payload->>'birth_date')::timestamp,p.date_birth),
     identity_sources=p.identity_sources || coalesce((SELECT jsonb_object_agg(k,v)
       FROM m_player old JOIN identity_map m ON m.old_id=old.id
       CROSS JOIN LATERAL jsonb_each(old.identity_sources) AS source(k,v) WHERE m.new_id=p.id),'{}'::jsonb)
       || q.payload->'identity_sources',
     source_key=CASE WHEN q.payload->'identity_sources' ? 'mlb' THEN 'mlb' WHEN q.payload->'identity_sources' ? 'npb' THEN 'npb' ELSE p.source_key END,
     external_id=CASE WHEN q.payload->'identity_sources' ? 'mlb' THEN q.payload->'identity_sources'->>'mlb' WHEN q.payload->'identity_sources' ? 'npb' THEN q.payload->'identity_sources'->>'npb' ELSE p.external_id END,
     url=coalesce(nullif(q.payload->>'url',''),p.url),updat=now()
     FROM identity_plan q WHERE p.id=(q.payload->>'canonical_id')::int''');
        await tx.execute('UPDATE m_player p SET merged_into_player_id=m.new_id FROM identity_map m WHERE p.merged_into_player_id=m.old_id');
        await tx.execute('UPDATE t_player_identity_merge p SET canonical_id=m.new_id FROM identity_map m WHERE p.canonical_id=m.old_id');
        // Queue unresolved candidates with their evidence, without guessing/merging.
        final reviews = plan['review'] as List;
        await tx.execute(r'''INSERT INTO t_player_identity_review(review_key,evidence)
     SELECT 'migration:'||coalesce(value->>'yahoo_id',ordinality::text),value
     FROM jsonb_array_elements($1::jsonb) WITH ORDINALITY
     ON CONFLICT(review_key) DO UPDATE SET evidence=excluded.evidence,updated_at=now()''', parameters: [jsonEncode(reviews)]);
        print('Identity migration archived as $runId; groups=${groups.length}');
        if (args.contains('--check')) {
          throw StateError('IDENTITY_CHECK_ROLLBACK');
        }
      });
    } catch (error) {
      if (args.contains('--check') && '$error'.contains('IDENTITY_CHECK_ROLLBACK')) {
        print('Migration SQL checked; all changes rolled back.');
        return;
      }
      rethrow;
    }
    // Reusable saved roster payloads contain source IDs; localize without re-fetching.
    final payloads = await conn.execute("SELECT int_year,id_team,payload FROM t_team_strength WHERE code_org='mlb'");
    final localized = await PlayerIdentity.localize(conn, payloads.map((r) => r[2]).toList()) as List;
    await conn.execute(r'''UPDATE t_team_strength t SET payload=d.payload
    FROM jsonb_to_recordset($1::jsonb) AS d(int_year int,id_team int,payload jsonb)
    WHERE t.code_org='mlb' AND t.int_year=d.int_year AND t.id_team=d.id_team''', parameters: [
      jsonEncode([
        for (var i = 0; i < payloads.length; i++) {'int_year': payloads[i][0], 'id_team': payloads[i][1], 'payload': localized[i]}
      ])
    ]);
    await conn.execute(r'''UPDATE t_player_identity_review r SET status='resolved',updated_at=now()
      WHERE status='pending' AND 1=(SELECT count(DISTINCT coalesce(p.merged_into_player_id,p.id))
        FROM jsonb_array_elements_text(coalesce(r.evidence->'candidate_ids',r.evidence->'ids','[]'::jsonb)) x
        JOIN m_player p ON p.id=x::int)''');
    await DisplaySnapshot.refreshPlayers(conn, DateTime.now().year);
  });
  exit(0);
}

Future<void> consolidate(TxSession tx, String table, List<String> keyColumns, List<String> batting, List<String> pitching, String battingCount, String pitchingCount) async {
  final keys = ['coalesce(m.new_id,t.id_player)', ...keyColumns.map((c) => 't.$c')].join(',');
  final keyNames = ['canonical', ...keyColumns].join(',');
  await tx.execute('''CREATE TEMP TABLE identity_$table ON COMMIT DROP AS
   SELECT t.*,coalesce(m.new_id,t.id_player) canonical,
     first_value(t.id) OVER(PARTITION BY $keys ORDER BY (m.old_id IS NULL) DESC,t.id) keeper,
     row_number() OVER(PARTITION BY $keys ORDER BY coalesce(t.$battingCount,0) DESC,(m.old_id IS NULL) DESC,t.id) batting_order,
     row_number() OVER(PARTITION BY $keys ORDER BY coalesce(t.$pitchingCount,0) DESC,(m.old_id IS NULL) DESC,t.id) pitching_order
   FROM $table t LEFT JOIN identity_map m ON m.old_id=t.id_player
   WHERE t.id_player IN(SELECT id FROM identity_affected) AND NOT coalesce(t.flg_delete,false)''');
  final assignments = [...batting.map((f) => '$f=b.$f'), ...pitching.map((f) => '$f=p.$f')].join(',');
  await tx.execute('''UPDATE $table t SET $assignments
   FROM identity_$table b JOIN identity_$table p USING($keyNames)
   WHERE b.batting_order=1 AND p.pitching_order=1 AND t.id=b.keeper''');
  await tx.execute('''UPDATE $table t SET flg_delete=true FROM identity_$table d
    WHERE t.id=d.id AND d.id<>d.keeper''');
}

/// Old scrape rows whose name belonged to a batter but profile/season totals
/// belonged to a pitcher must be split by recorded role before merging IDs.
Future<void> splitConfusedRoles(TxSession tx, Map<String, dynamic> split) async {
  final old = split['old_id'] as int, pitcher = split['pitcher_id'] as int;
  final row = await tx.execute('SELECT url FROM m_player WHERE id=\$1', parameters: [old]);
  if (row.length != 1 || row.single[0] != split['incorrect_profile_url']) throw StateError('Role correction evidence changed: $old');
  final mixed = await tx.execute('SELECT id FROM m_player_career WHERE id_player=\$1 AND coalesce(int_appearance,0)>0 AND coalesce(int_pitching,0)>0 AND NOT coalesce(flg_delete,false)', parameters: [old]);
  final mixedGames = await tx.execute('SELECT id FROM t_game_summary WHERE id_player=\$1 AND coalesce(int_batting,0)>0 AND (coalesce(int_pitch,0)>0 OR coalesce(double_inning_pitch,0)>0) AND NOT coalesce(flg_delete,false)', parameters: [old]);
  if (mixed.isNotEmpty || mixedGames.isNotEmpty) throw StateError('Mixed role totals require individual review: $old');
  await tx.execute('UPDATE m_player_career old SET flg_delete=true WHERE old.id_player=\$1 AND coalesce(old.int_appearance,0)=0 AND EXISTS(SELECT 1 FROM m_player_career canonical WHERE canonical.id_player=\$2 AND canonical.int_year=old.int_year AND canonical.id_team=old.id_team AND NOT coalesce(canonical.flg_delete,false) AND coalesce(canonical.int_pitching,0)>0)', parameters: [old, pitcher]);
  await tx.execute('UPDATE m_player_career SET id_player=\$2 WHERE id_player=\$1 AND (coalesce(int_pitching,0)>0 OR coalesce(double_inning,0)>0) AND coalesce(int_appearance,0)=0', parameters: [old, pitcher]);
  for (final table in ['t_stats_player', 't_stats_player_latest', 't_predict_player']) {
    await tx.execute('UPDATE $table t SET id_player=\$2 FROM m_stats s WHERE t.id_player=\$1 AND s.id=t.id_stats AND s.flg_pitcher=true', parameters: [old, pitcher]);
  }
  await tx.execute('UPDATE t_game_summary SET id_player=\$2 WHERE id_player=\$1 AND coalesce(int_batting,0)=0 AND (coalesce(int_pitch,0)>0 OR coalesce(double_inning_pitch,0)>0)', parameters: [old, pitcher]);
  for (final column in ['id_pitcher_home', 'id_pitcher_away', 'id_pitcher_win', 'id_pitcher_lose', 'id_pitcher_save']) {
    await tx.execute('UPDATE t_game SET $column=\$2 WHERE $column=\$1', parameters: [old, pitcher]);
  }
  await tx.execute('UPDATE t_game_details SET id_pitcher=\$2 WHERE id_pitcher=\$1', parameters: [old, pitcher]);
  // Profile-derived caches can contain the other person's image/biography.
  // Originals have already been archived by this migration transaction.
  for (final table in ['t_player_detail_snapshot', 't_player_season_usage', 't_player_art', 't_player_art_roster', 't_player_injury_details']) {
    await tx.execute('DELETE FROM $table WHERE id_player=\$1', parameters: [old]);
  }
}
