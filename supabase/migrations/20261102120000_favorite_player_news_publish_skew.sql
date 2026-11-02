-- Favorite-player News: tolerate publisher clock skew at first publication.
--
-- 2026-11-01: five of six eligible articles never reached
-- favorite_player_news_publications, so no push went out (#708 alone had 974
-- opted-in followers). The publisher sends published_at from its own clock a
-- moment before the INSERT, while created_at defaults to the database's now(),
-- so published_at<created_at by 0.4-12 s and the trigger read every one as an
-- imported old article. Only that guard changes; the function is otherwise
-- identical to 20261031051924_favorite_player_news.sql. No backfill.
CREATE OR REPLACE FUNCTION public.queue_favorite_player_news()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    -- Publication well before creation is an imported old article, never a new
    -- transition. A publisher stamping published_at from its own clock just
    -- before the insert (Hermes: 0.4-12 s before created_at's now()) is a new
    -- publication, not an import, so allow a short skew. Protected publish-now
    -- stamps both fields together; scheduled articles retain their due time.
    AND NEW.published_at>=NEW.created_at-interval '5 minutes' AND cardinality(ids)>0
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
END $function$;
