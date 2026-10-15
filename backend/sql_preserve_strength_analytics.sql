-- Older refresh workers replace the entire JSON payload. Preserve independently
-- collected analytics when a refresh omits them or returns an empty result.
CREATE OR REPLACE FUNCTION preserve_strength_analytics() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE field text;
BEGIN
  FOREACH field IN ARRAY ARRAY['batting_stats', 'pitching_stats', 'contracts', 'fielding_metrics', 'defense_substitutions'] LOOP
    IF (NOT NEW.payload ? field OR NEW.payload->field IN ('null'::jsonb, '[]'::jsonb))
       AND jsonb_typeof(OLD.payload->field) = 'array'
       AND OLD.payload->field <> '[]'::jsonb THEN
      NEW.payload = jsonb_set(NEW.payload, ARRAY[field], OLD.payload->field);
    END IF;
  END LOOP;
  IF NOT NEW.payload ? 'metrics_updated_at' AND OLD.payload ? 'metrics_updated_at' THEN
    NEW.payload = jsonb_set(NEW.payload, '{metrics_updated_at}', OLD.payload->'metrics_updated_at');
  END IF;
  RETURN NEW;
END;
$$;
CREATE OR REPLACE TRIGGER preserve_strength_analytics_before_update
BEFORE UPDATE OF payload ON t_team_strength
FOR EACH ROW EXECUTE FUNCTION preserve_strength_analytics();
