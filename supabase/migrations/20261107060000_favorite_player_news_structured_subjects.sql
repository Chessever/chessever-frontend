-- Explicit editorial subjects, not visible article formatting, define eligibility.
-- Forward-only replacement: keep the signature for queue/transport callers.
-- p_content is intentionally unused. Neither headers nor incidental inline links
-- add or remove subjects. Canonical DB identity checks remain in queue/transport.
-- No row updates, backfill, preference changes or notification sends.
BEGIN;
CREATE OR REPLACE FUNCTION public.favorite_player_news_subject_ids(p_subjects jsonb,p_content text)
RETURNS text[] LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $$
DECLARE s jsonb; ids text[] := '{}'; fid text; label text; role text;
BEGIN
 IF jsonb_typeof(p_subjects) IS DISTINCT FROM 'array' THEN RETURN '{}'; END IF;
 IF jsonb_array_length(p_subjects) NOT BETWEEN 1 AND 20 THEN RETURN '{}'; END IF;
 FOR s IN SELECT value FROM jsonb_array_elements(p_subjects) LOOP
  fid:=s->>'fide_id'; label:=s->>'name'; role:=s->>'role';
  IF jsonb_typeof(s) IS DISTINCT FROM 'object' OR fid IS NULL OR fid !~ '^[1-9][0-9]{0,14}$'
   OR label IS NULL OR length(label) NOT BETWEEN 1 AND 120 OR label<>btrim(label) OR label ~ '[\[\]()<>\r\n]'
   OR role IS NULL OR role NOT IN ('subject','quotation') OR fid=ANY(ids) THEN RETURN '{}'; END IF;
  ids:=array_append(ids,fid);
 END LOOP;
 RETURN ids;
END $$;
-- CREATE OR REPLACE retains ownership and existing ACLs; restate the intended
-- private execution boundary without granting anon/authenticated access.
REVOKE ALL ON FUNCTION public.favorite_player_news_subject_ids(jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.favorite_player_news_subject_ids(jsonb,text) TO service_role;
COMMIT;
