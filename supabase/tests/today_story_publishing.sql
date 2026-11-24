begin;

do $$
declare
  actor constant uuid := '00000000-0000-4000-8000-000000000001';
  featured constant uuid := '00000000-0000-4000-8000-000000000002';
  hidden constant uuid := '00000000-0000-4000-8000-000000000003';
  scheduled constant uuid := '00000000-0000-4000-8000-000000000004';
  catalog jsonb;
  base jsonb;
  another jsonb;
  lineup jsonb;
  receipt jsonb;
  draft jsonb := '{"mode":"append","collectionSlug":"c1","title":"Weekend picks","priority":20,"slides":[{"kind":"news","newsId":42},{"kind":"image","imageUrl":"https://example.org/story.webp"},{"kind":"announcement","title":"Round two","body":"Starts at noon."}]}';
begin
  select jsonb_agg(jsonb_build_object('slug', 'c' || n, 'game_count', 2,
      'updated_at', now() - case when n <= 3 then interval '1 hour' * n else interval '1 day' * (10 + n) end))
    into catalog from generate_series(1, 9) n;
  base := public.get_today_stories_v1(catalog, 0, true);
  another := public.get_today_stories_v1(catalog, 1, true);
  if jsonb_array_length(base) <> 6 or base->0->>'kind' <> 'missed_chances'
    or base->1->>'collectionSlug' <> 'c1' or base->3->>'collectionSlug' <> 'c3'
    or another->4->>'collectionSlug' = base->4->>'collectionSlug' then
    raise exception 'automatic roster or rotation is incorrect: % %', base, another;
  end if;

  receipt := public.admin_today_story_v1('save', featured, null, actor, draft);
  if receipt->'draft'->>'revision' <> '1' or public.get_today_stories_v1(catalog, 0, true) <> base then
    raise exception 'draft leaked into the public lineup';
  end if;
  perform public.admin_today_story_v1('publish', featured, 1, actor);
  perform public.admin_today_story_v1('save', featured, 2, actor, jsonb_set(draft, '{title}', '"New draft"'));
  if (select story->>'title' from public.today_story_publications where id = featured) <> 'Weekend picks' then
    raise exception 'saving a draft modified its published version';
  end if;
  begin
    perform public.admin_today_story_v1('publish', featured, 2, actor);
    raise exception 'stale publishing request succeeded';
  exception when sqlstate '55000' then null;
  end;

  perform public.admin_today_story_v1('save', hidden, null, actor,
    '{"mode":"hide","collectionSlug":"c2","slides":[]}');
  perform public.admin_today_story_v1('publish', hidden, 1, actor);
  lineup := public.get_today_stories_v1(catalog, 0, true);
  if lineup->1->>'kind' <> 'editorial' or lineup->1->>'mode' <> 'append'
    or lineup->1->>'id' <> featured::text or jsonb_array_length(lineup) <> 6
    or jsonb_path_exists(lineup, '$[*] ? (@.collectionSlug == "c2")') then
    raise exception 'editorial placement is incorrect: %', lineup;
  end if;

  perform public.admin_today_story_v1('save', scheduled, null, actor,
    jsonb_build_object('mode', 'standalone', 'title', 'Tomorrow', 'startsAt', now() + interval '1 day',
      'endsAt', now() + interval '2 days', 'slides', jsonb_build_array(jsonb_build_object('kind', 'short',
        'mediaUrl', 'https://example.org/preview.mp4', 'layers', jsonb_build_array(jsonb_build_object('kind', 'text', 'text', 'Tomorrow'))))));
  perform public.admin_today_story_v1('publish', scheduled, 1, actor);
  if public.get_today_stories_v1(catalog, 0, true) <> lineup then
    raise exception 'a scheduled publication is visible ahead of its window';
  end if;

  perform public.admin_today_story_v1('save', featured, 3, actor,
    jsonb_set(draft, '{startsAt}', to_jsonb(now() + interval '1 day')));
  perform public.admin_today_story_v1('publish', featured, 4, actor);
  if public.get_today_stories_v1(catalog, 0, true) <> lineup
    or (select count(*) from public.today_story_publications where id = featured) <> 2 then
    raise exception 'scheduling a replacement interrupted the current publication';
  end if;

  if public.pick_today_story_game_v1('[{"id":"old","watched":true},{"id":"new","watched":false}]', null) <> 'new'
    or public.pick_today_story_game_v1('[{"id":"old","watched":true},{"id":"new","watched":false}]', 'old') <> 'old' then
    raise exception 'automatic game preference is incorrect';
  end if;
  perform public.admin_today_story_v1('withdraw', featured, 5, actor);
  if exists(select from public.today_story_publications where id = featured) then
    raise exception 'withdrawing a publication left it visible';
  end if;
end;
$$;

set local role anon;

do $$
begin
  if has_table_privilege(current_user, 'public.today_story_drafts', 'select')
    or has_table_privilege(current_user, 'public.today_story_publications', 'insert')
    or has_function_privilege(current_user, 'public.admin_today_story_v1(text,uuid,integer,uuid,jsonb)', 'execute') then
    raise exception 'public role can read drafts or mutate editorial content';
  end if;
  if exists(select from public.today_story_publications where mode = 'standalone') then
    raise exception 'RLS exposes the scheduled draft';
  end if;
  if public.get_today_stories_v1('[]', 0, false) <> '[]'::jsonb then
    raise exception 'an anonymous request with no playable content should be empty';
  end if;
end;
$$;

rollback;
