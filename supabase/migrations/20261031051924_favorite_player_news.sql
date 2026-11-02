-- LOCAL ONLY. No sends/backfill until separately approved schema/service/app rollout.
-- Native News only. Editorial eligibility is explicit and stored on the SAME row
-- as content/publication, not inferred from body/event/standings player links.
BEGIN;
ALTER TABLE public.news ADD COLUMN IF NOT EXISTS player_news_subjects jsonb NOT NULL DEFAULT '[]';
-- Existing rows (including drafts) are deliberately ineligible at rollout. Only
-- new rows created after activation may produce a first-publication notification.
ALTER TABLE public.news ADD COLUMN IF NOT EXISTS player_news_publication_seen boolean NOT NULL DEFAULT true;


CREATE TABLE public.favorite_player_news_publications (
 news_id bigint PRIMARY KEY REFERENCES public.news(id) ON DELETE CASCADE,
 fide_ids text[] NOT NULL,
 published_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.favorite_player_news_publications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.favorite_player_news_publications FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.favorite_player_news_publications TO service_role;

-- A strict, versioned top paragraph is both visible editorial disclosure and an
-- exact identity binding. Old inline links (including incidental participants)
-- have NO push meaning. Missing/conflicting metadata fails the entire article.
CREATE FUNCTION public.favorite_player_news_subject_ids(p_subjects jsonb,p_content text)
RETURNS text[] LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $$
DECLARE s jsonb; ids text[] := '{}'; fid text; label text; role text; top_line text; link text;
BEGIN
 IF jsonb_typeof(p_subjects) IS DISTINCT FROM 'array' THEN RETURN '{}'; END IF;
 IF jsonb_array_length(p_subjects) NOT BETWEEN 1 AND 20 THEN RETURN '{}'; END IF;
 top_line:=split_part(replace(coalesce(p_content,''),E'\r\n',E'\n'),E'\n',1);
 IF left(top_line,length('Players involved: '))<>'Players involved: ' THEN RETURN '{}'; END IF;
 FOR s IN SELECT value FROM jsonb_array_elements(p_subjects) LOOP
  fid:=s->>'fide_id'; label:=s->>'name'; role:=s->>'role';
  IF jsonb_typeof(s) IS DISTINCT FROM 'object' OR fid IS NULL OR fid !~ '^[1-9][0-9]{0,14}$'
   OR label IS NULL OR length(label) NOT BETWEEN 1 AND 120 OR label<>btrim(label) OR label ~ '[\[\]()<>\r\n]'
   OR role IS NULL OR role NOT IN ('subject','quotation') OR fid=ANY(ids) THEN RETURN '{}'; END IF;
  link:='['||label||'](/player/'||fid||')';
  IF position(link IN top_line)=0 OR cardinality(string_to_array(top_line,'](/player/'||fid||')'))<>2 THEN RETURN '{}'; END IF;
  ids:=array_append(ids,fid);
 END LOOP;
 RETURN ids;
END $$;
REVOKE ALL ON FUNCTION public.favorite_player_news_subject_ids(jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.favorite_player_news_subject_ids(jsonb,text) TO service_role;

CREATE FUNCTION public.queue_favorite_player_news() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE ids text[];
BEGIN
 IF (NEW.player_news_subjects<>'[]'::jsonb OR (TG_OP='UPDATE' AND OLD.player_news_subjects<>'[]'::jsonb))
    AND coalesce(auth.role(),'')<>'service_role' THEN
  RAISE EXCEPTION 'Player News subject eligibility requires editorial service authority' USING ERRCODE='42501';
 END IF;
 IF TG_OP='INSERT' THEN NEW.player_news_publication_seen:=false;
 ELSE NEW.player_news_publication_seen:=OLD.player_news_publication_seen; END IF;
 IF NEW.status='published' AND NOT NEW.player_news_publication_seen
    AND (NEW.published_at IS NULL OR NEW.published_at<=now()) THEN
  -- Future rows are activated by the existing dispatcher's bounded service RPC
  -- only when due. Consume due/invalid/ineligible transitions exactly once.
  NEW.player_news_publication_seen:=true;
  ids:=public.favorite_player_news_subject_ids(NEW.player_news_subjects,NEW.content);
  -- A future-dated published row becomes publicly visible when its date passes.
  -- An edit AFTER that moment must not add retrospective eligibility before
  -- the next dispatcher tick: require its pre-edit subjects/header as well.
  IF TG_OP='UPDATE' AND OLD.status='published' AND OLD.published_at<=now()
     AND (ids IS DISTINCT FROM public.favorite_player_news_subject_ids(OLD.player_news_subjects,OLD.content)
          OR NEW.published_at IS DISTINCT FROM OLD.published_at) THEN ids:='{}'; END IF;
  IF NEW.published_at IS NOT NULL AND NEW.published_at<=now()
    -- Publication predating creation is an imported old article, never a new
    -- transition. Protected publish-now stamps both fields together; scheduled
    -- articles retain their actual due time. This is not an age/freshness window.
    AND NEW.published_at>=NEW.created_at AND cardinality(ids)>0
    AND coalesce(auth.role(),'')='service_role'
    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(NEW.player_news_subjects) s WHERE
      (SELECT count(*) FROM public.chess_players cp WHERE cp.fideid=(s->>'fide_id')::bigint)<>1
      OR NOT EXISTS(SELECT 1 FROM public.chess_players cp WHERE cp.fideid=(s->>'fide_id')::bigint
       AND ARRAY(SELECT v FROM unnest(regexp_split_to_array(lower(btrim(replace(cp.name,',',' '))), '\s+')) v ORDER BY v)
         = ARRAY(SELECT v FROM unnest(regexp_split_to_array(lower(btrim(replace(s->>'name',',',' '))), '\s+')) v ORDER BY v))) THEN
   INSERT INTO public.favorite_player_news_publications(news_id,fide_ids,published_at)
    VALUES(NEW.id,ids,NEW.published_at) ON CONFLICT DO NOTHING;
  END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.queue_favorite_player_news() FROM PUBLIC;
-- Deferred referential checks permit the BEFORE trigger to create publication
-- rows for an INSERT while keeping the seen flag wholly trigger-owned.
ALTER TABLE public.favorite_player_news_publications DROP CONSTRAINT favorite_player_news_publications_news_id_fkey;
ALTER TABLE public.favorite_player_news_publications ADD FOREIGN KEY(news_id) REFERENCES public.news(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
CREATE TRIGGER queue_favorite_player_news BEFORE INSERT OR UPDATE ON public.news
 FOR EACH ROW EXECUTE FUNCTION public.queue_favorite_player_news();

CREATE INDEX IF NOT EXISTS news_due_favorite_player_publication_idx ON public.news(published_at,id)
 WHERE status='published' AND NOT player_news_publication_seen;
CREATE FUNCTION public.activate_due_favorite_player_news(p_limit int DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE touched integer;
BEGIN
 WITH due AS (SELECT id FROM public.news WHERE status='published' AND NOT player_news_publication_seen
   AND published_at<=now() ORDER BY published_at,id
   LIMIT greatest(1,least(coalesce(p_limit,100),200)) FOR UPDATE SKIP LOCKED)
 UPDATE public.news n SET player_news_publication_seen=true FROM due WHERE n.id=due.id;
 GET DIAGNOSTICS touched=ROW_COUNT;
 RETURN touched;
END $$;
REVOKE ALL ON FUNCTION public.activate_due_favorite_player_news(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_due_favorite_player_news(integer) TO service_role;

-- The preferred notification service consumes this durable publication ledger
-- from its existing scheduled tick, even when notification_outbox is idle.
-- Recipient ownership/category/dedupe lives in admin_portal, not the client mirror.
COMMIT;
