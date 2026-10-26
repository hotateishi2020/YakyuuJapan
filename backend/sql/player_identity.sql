-- Run before deploying identity-aware readers/writers. Original names remain aliases.
ALTER TABLE m_player ADD COLUMN IF NOT EXISTS name_patterns text[] NOT NULL DEFAULT '{}';
ALTER TABLE m_player ADD COLUMN IF NOT EXISTS name_pattern_keys text[] NOT NULL DEFAULT '{}';
ALTER TABLE m_player ADD COLUMN IF NOT EXISTS name_ja text;
ALTER TABLE m_player ADD COLUMN IF NOT EXISTS name_en text;
ALTER TABLE m_player ADD COLUMN IF NOT EXISTS identity_sources jsonb NOT NULL DEFAULT '{}';
ALTER TABLE m_player ADD COLUMN IF NOT EXISTS merged_into_player_id integer;
CREATE TABLE IF NOT EXISTS t_player_identity_review (
  review_key text PRIMARY KEY, evidence jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending', updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS t_player_identity_merge (
  old_id integer PRIMARY KEY, canonical_id integer NOT NULL,
  evidence jsonb NOT NULL, original_player jsonb NOT NULL,
  archived_rows jsonb NOT NULL DEFAULT '{}', merged_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION player_identity_key(text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
 SELECT regexp_replace(translate(lower(normalize(coalesce($1,''), NFKC)),
  '髙﨑神塚濵濱邊邉齋齊áàâäãåéèêëíìîïóòôöõúùûüñç',
  '高崎神塚浜浜辺辺斎斉aaaaaaeeeeiiiiooooouuuunc'),
  '[[:space:]　・･.．,，‐‑–—_''’`*́̀̈̂̃-]', '', 'g')
$$;
CREATE OR REPLACE FUNCTION keep_player_name_patterns() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE old_patterns text[] := '{}';
BEGIN
  IF TG_OP='UPDATE' THEN
    old_patterns := coalesce(OLD.name_patterns,'{}') || ARRAY[OLD.name_full,OLD.name_ja,OLD.name_en];
    IF OLD.merged_into_player_id IS NOT NULL AND NOT coalesce(NEW.flg_delete,false) THEN
      RAISE EXCEPTION 'Merged player % must resolve to %', OLD.id, OLD.merged_into_player_id;
    END IF;
  END IF;
  NEW.name_patterns := ARRAY(SELECT DISTINCT btrim(n) FROM unnest(
    old_patterns || coalesce(NEW.name_patterns,'{}') || ARRAY[NEW.name_full,NEW.name_ja,NEW.name_en]) n
    WHERE coalesce(btrim(n),'')<>'' ORDER BY btrim(n));
  IF coalesce(NEW.name_ja,'')='' AND NEW.name_full ~ '[ぁ-んァ-ヶ一-龯]' THEN
    NEW.name_ja := NEW.name_full;
  END IF;
  IF coalesce(NEW.name_en,'')='' AND NEW.name_full ~ '^[A-Za-z]' AND NEW.name_full !~ '[ァ-ヶ一-龯]' THEN
    NEW.name_en := NEW.name_full;
  END IF;
  IF coalesce(NEW.name_ja,'')<>'' THEN NEW.name_full := NEW.name_ja; END IF;
  NEW.name_pattern_keys := ARRAY(SELECT DISTINCT player_identity_key(n)
    FROM unnest(NEW.name_patterns) n WHERE player_identity_key(n)<>'' ORDER BY 1);
  IF coalesce(NEW.source_key,'')<>'' AND coalesce(NEW.external_id,'')<>'' THEN
    NEW.identity_sources := coalesce(NEW.identity_sources,'{}') || jsonb_build_object(NEW.source_key,NEW.external_id);
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS keep_player_name_patterns ON m_player;
CREATE TRIGGER keep_player_name_patterns BEFORE INSERT OR UPDATE ON m_player
  FOR EACH ROW EXECUTE FUNCTION keep_player_name_patterns();
UPDATE m_player SET name_patterns=name_patterns WHERE cardinality(name_patterns)=0;
CREATE INDEX IF NOT EXISTS ix_player_name_patterns ON m_player USING gin(name_pattern_keys)
  WHERE NOT coalesce(flg_delete,false);
CREATE INDEX IF NOT EXISTS ix_player_identity_sources ON m_player USING gin(identity_sources)
  WHERE NOT coalesce(flg_delete,false);
-- Serialize the final check+insert in one transaction, including pooler clients.
CREATE OR REPLACE FUNCTION register_player_identity(
 incoming_name text, incoming_team integer, incoming_birth timestamp,
 incoming_source text, incoming_external text, incoming_url text) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE matches integer[]; created integer;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtext('koko-player-registration'));
 SELECT array_agg(id) INTO matches FROM m_player WHERE NOT coalesce(flg_delete,false)
 AND ((incoming_source IS NOT NULL AND incoming_external IS NOT NULL
       AND identity_sources->>incoming_source=incoming_external)
   OR (id_team=incoming_team AND player_identity_key(incoming_name)=ANY(name_pattern_keys)
       AND (incoming_birth IS NULL OR date_birth IS NULL OR date_birth=incoming_birth)
       AND (incoming_source IS NULL OR identity_sources->>incoming_source IS NULL
            OR identity_sources->>incoming_source LIKE 'name:%' OR incoming_external LIKE 'name:%'
            OR identity_sources->>incoming_source=incoming_external)));
 IF cardinality(matches)=1 THEN RETURN matches[1]; END IF;
 IF cardinality(matches)>1 THEN RETURN 0; END IF;
 -- A concurrent Japanese/English import must not create two identities.
 SELECT array_agg(id) INTO matches FROM m_player WHERE NOT coalesce(flg_delete,false)
   AND id_team=incoming_team AND incoming_birth IS NOT NULL AND date_birth=incoming_birth
   AND (incoming_source IS NULL OR identity_sources->>incoming_source IS NULL
     OR identity_sources->>incoming_source LIKE 'name:%');
 IF cardinality(matches)>0 THEN
   INSERT INTO t_player_identity_review(review_key,evidence)
   VALUES('register:'||incoming_team||':'||player_identity_key(incoming_name),
     jsonb_build_object('name',incoming_name,'candidate_ids',matches,'reason','concurrent identity requires profile verification'))
   ON CONFLICT(review_key) DO UPDATE SET evidence=excluded.evidence,updated_at=now();
   RETURN 0;
 END IF;
 INSERT INTO m_player(name_full,name_last,name_first,name_middle,id_team,date_birth,
   source_key,external_id,url,flg_delete,crtat,updat)
 VALUES(incoming_name,incoming_name,'','',incoming_team,incoming_birth,
   incoming_source,incoming_external,incoming_url,false,now(),now()) RETURNING id INTO created;
 RETURN created;
END $$;
-- Legacy bulk SQL must not multiply an INSERT by the size of m_player.
-- Modern writers resolve/return the existing ID before reaching this guard.
CREATE OR REPLACE FUNCTION prevent_duplicate_player_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE matches integer[];
BEGIN
 PERFORM pg_advisory_xact_lock(hashtext('koko-player-registration'));
 SELECT array_agg(p.id) INTO matches FROM m_player p
 WHERE NOT coalesce(p.flg_delete,false) AND (
   (NEW.source_key IS NOT NULL AND NEW.external_id IS NOT NULL
     AND p.identity_sources->>NEW.source_key=NEW.external_id)
   OR (p.id_team=NEW.id_team AND NEW.date_birth IS NOT NULL AND p.date_birth=NEW.date_birth
     AND (NEW.source_key IS NULL OR p.identity_sources->>NEW.source_key IS NULL
       OR p.identity_sources->>NEW.source_key LIKE 'name:%'))
   OR (p.id_team=NEW.id_team AND player_identity_key(NEW.name_full)=ANY(p.name_pattern_keys)
     AND (NEW.date_birth IS NULL OR p.date_birth IS NULL OR NEW.date_birth=p.date_birth)
     AND (NEW.source_key IS NULL OR p.identity_sources->>NEW.source_key IS NULL
       OR p.identity_sources->>NEW.source_key LIKE 'name:%' OR NEW.external_id LIKE 'name:%'
       OR p.identity_sources->>NEW.source_key=NEW.external_id)));
 IF cardinality(matches)>0 THEN
   INSERT INTO t_player_identity_review(review_key,evidence)
   VALUES('insert:'||NEW.id_team||':'||player_identity_key(NEW.name_full),
     jsonb_build_object('name',NEW.name_full,'candidate_ids',matches,'reason','legacy duplicate INSERT prevented'))
   ON CONFLICT(review_key) DO UPDATE SET evidence=excluded.evidence,updated_at=now();
   RETURN NULL;
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS zz_prevent_duplicate_player_insert ON m_player;
CREATE TRIGGER zz_prevent_duplicate_player_insert BEFORE INSERT ON m_player
 FOR EACH ROW EXECUTE FUNCTION prevent_duplicate_player_insert();
CREATE UNIQUE INDEX IF NOT EXISTS ux_player_identity_mlb
 ON m_player((identity_sources->>'mlb'))
 WHERE NOT coalesce(flg_delete,false) AND identity_sources ? 'mlb';
CREATE UNIQUE INDEX IF NOT EXISTS ux_player_identity_npb
 ON m_player((identity_sources->>'npb'))
 WHERE NOT coalesce(flg_delete,false) AND identity_sources->>'npb' ~ '^[0-9]+$';
