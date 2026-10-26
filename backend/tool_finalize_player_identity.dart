import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    // A merged NPB/MLB record also retains the old official English display name.
    await conn.execute(r'''UPDATE m_player p SET name_en=o.name_en
   FROM (SELECT merged_into_player_id id,min(nullif(name_en,'')) name_en
     FROM m_player WHERE merged_into_player_id IS NOT NULL GROUP BY 1) o
   WHERE p.id=o.id AND coalesce(p.name_en,'')='' AND o.name_en IS NOT NULL''');
    // Incomplete legacy placeholders remain review candidates, not guessed merges.
    await conn.execute(r'''INSERT INTO t_player_identity_review(review_key,evidence)
   SELECT 'remaining:'||p.id_team||':'||player_identity_key(p.name_full),
     jsonb_build_object('name',min(p.name_full),'team_id',p.id_team,
       'candidate_ids',jsonb_agg(p.id ORDER BY p.id),'reason','remaining same-team normalized-name collision; needs source evidence')
   FROM m_player p WHERE NOT coalesce(p.flg_delete,false)
     AND p.id_team IN(SELECT id_team FROM t_team_strength WHERE int_year=2026)
     AND (EXISTS(SELECT 1 FROM m_player_career c WHERE c.id_player=p.id AND c.int_year=2026 AND NOT coalesce(c.flg_delete,false))
       OR NOT EXISTS(SELECT 1 FROM m_player_career c WHERE c.id_player=p.id AND NOT coalesce(c.flg_delete,false)))
   GROUP BY p.id_team,player_identity_key(p.name_full) HAVING count(*)>1
     AND count(DISTINCT p.identity_sources->>'mlb')<=1
     AND count(DISTINCT CASE WHEN p.identity_sources->>'npb' ~ '^[0-9]+$' THEN p.identity_sources->>'npb' END)<=1
   ON CONFLICT(review_key) DO UPDATE SET evidence=excluded.evidence,updated_at=now()''');
    await conn.execute(r'''UPDATE t_player_identity_review r SET status='resolved',updated_at=now()
    WHERE status='pending' AND r.evidence ? 'yahoo_id'
      AND 1=(SELECT count(*) FROM m_player p WHERE NOT coalesce(p.flg_delete,false)
        AND p.identity_sources->>'yahoo_mlb'=r.evidence->>'yahoo_id'
        AND p.identity_sources ? 'mlb')''');
    final english = await conn.execute(r'''SELECT DISTINCT payload->>'name_player' name
   FROM v_stats_player WHERE int_year=2026 AND (payload->>'id_league')::int IN(3,4)
   AND payload->>'name_player' ~ '[A-Za-z]' AND payload->>'name_player' !~ '[ぁ-んァ-ヶ一-龯]'
   ORDER BY 1''');
    final reviews = await conn.execute("SELECT review_key,evidence,status FROM t_player_identity_review WHERE status='pending' ORDER BY review_key");
    File('data/player-identity-pending-review.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(reviews.map((r) => r.toColumnMap()).toList())}\n');
    print(jsonEncode({'remaining_english_ranking_names': english.map((r) => r[0]).toList(), 'pending_review_groups': reviews.length}));
  });
  exit(0);
}
