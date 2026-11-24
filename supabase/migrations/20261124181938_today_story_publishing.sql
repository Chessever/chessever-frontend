begin;

-- Draft edits never alter the public snapshot. Publishing and withdrawing
-- lock the draft revision, so two editors cannot overwrite one another.
create table public.today_story_drafts (
  id uuid primary key,
  revision integer not null check (revision > 0),
  story jsonb not null check (jsonb_typeof(story) = 'object' and octet_length(story::text) <= 1048576),
  updated_at timestamptz not null default now(),
  updated_by uuid not null
);

create table public.today_story_publications (
  id uuid not null references public.today_story_drafts(id),
  revision integer not null check (revision > 0),
  story jsonb not null,
  mode text not null check (mode in ('standalone', 'append', 'replace', 'hide')),
  collection_slug text,
  priority integer not null check (priority between 0 and 1000),
  starts_at timestamptz not null,
  ends_at timestamptz,
  superseded_at timestamptz,
  published_at timestamptz not null default now(),
  primary key (id, revision),
  check (ends_at is null or ends_at > starts_at),
  check ((mode = 'standalone') = (collection_slug is null))
);

create index today_story_drafts_updated_idx on public.today_story_drafts (updated_at desc);
create index today_story_publications_window_idx on public.today_story_publications (starts_at, ends_at);

alter table public.today_story_drafts enable row level security;
alter table public.today_story_publications enable row level security;

revoke all on public.today_story_drafts, public.today_story_publications from public, anon, authenticated;
grant select, insert, update, delete on public.today_story_drafts, public.today_story_publications to service_role;
grant select on public.today_story_publications to anon, authenticated;

create policy today_story_read_active on public.today_story_publications
  for select to anon, authenticated
  using (starts_at <= statement_timestamp()
    and (ends_at is null or ends_at > statement_timestamp())
    and (superseded_at is null or superseded_at > statement_timestamp()));

create function public.admin_today_story_v1(
  p_operation text,
  p_id uuid,
  p_expected_revision integer,
  p_actor uuid,
  p_story jsonb default null
) returns jsonb
language plpgsql security invoker set search_path = ''
as $$
declare
  draft public.today_story_drafts;
  active public.today_story_publications;
  published jsonb;
  spec jsonb;
  mode_value text;
  collection_value text;
  priority_value integer;
  starts_value timestamptz;
  ends_value timestamptz;
  publication_time timestamptz := statement_timestamp();
begin
  if p_actor is null or p_id is null or p_operation is null or
      p_operation not in ('save', 'publish', 'withdraw') then
    raise exception 'Invalid story operation' using errcode = '22023';
  end if;

  if p_operation = 'save' and p_expected_revision is null then
    if jsonb_typeof(p_story) is distinct from 'object' then
      raise exception 'Expected a story draft' using errcode = '22023';
    end if;
    insert into public.today_story_drafts (id, revision, story, updated_by)
      values (p_id, 1, p_story, p_actor) returning * into draft;
    return jsonb_build_object('draft', to_jsonb(draft), 'publication', null, 'publications', '[]'::jsonb);
  end if;

  select * into draft from public.today_story_drafts where id = p_id for update;
  if not found then
    raise exception 'Story no longer exists' using errcode = 'P0002';
  end if;
  if draft.revision is distinct from p_expected_revision then
    raise exception 'Story changed. Reload it before continuing.' using errcode = '55000';
  end if;

  if p_operation = 'save' and jsonb_typeof(p_story) is distinct from 'object' then
    raise exception 'Expected a story draft' using errcode = '22023';
  end if;

  if p_operation = 'publish' then
    -- The admin worker resolves referenced items and builds public game
    -- previews for this snapshot. The draft retains the author's inputs.
    spec := coalesce(p_story, draft.story);
    mode_value := spec->>'mode';
    collection_value := nullif(btrim(spec->>'collectionSlug'), '');
    priority_value := coalesce((spec->>'priority')::int, 100);
    starts_value := coalesce(nullif(spec->>'startsAt', '')::timestamptz, publication_time);
    ends_value := nullif(spec->>'endsAt', '')::timestamptz;

    if mode_value is null or mode_value not in ('standalone', 'append', 'replace', 'hide')
      or (mode_value = 'standalone') <> (collection_value is null)
      or (mode_value = 'standalone' and coalesce(length(btrim(spec->>'title')), 0) = 0)
      or coalesce(length(collection_value), 0) > 160
      or priority_value not between 0 and 1000
      or (ends_value is not null and ends_value <= greatest(starts_value, publication_time))
      or jsonb_typeof(spec->'slides') is distinct from 'array' then
      raise exception 'Invalid story placement or schedule' using errcode = '22023';
    end if;

    if jsonb_array_length(spec->'slides') > 12
      or (mode_value = 'hide' and jsonb_array_length(spec->'slides') <> 0)
      or (mode_value <> 'hide' and jsonb_array_length(spec->'slides') = 0)
      or exists (
        select from jsonb_array_elements(spec->'slides') slide
        where jsonb_typeof(slide) <> 'object' or coalesce(slide->>'kind', '') not in
          ('collection_game', 'game', 'pgn', 'image', 'announcement', 'news', 'event', 'puzzle', 'video', 'short')
      ) then
      raise exception 'Each published story needs valid slides' using errcode = '22023';
    end if;

    delete from public.today_story_publications where id = p_id and starts_at > publication_time;
    update public.today_story_publications
      set superseded_at = greatest(starts_value, publication_time)
      where id = p_id and starts_at <= publication_time
        and (ends_at is null or ends_at > publication_time)
        and (superseded_at is null or superseded_at > publication_time);
    insert into public.today_story_publications
      (id, revision, story, mode, collection_slug, priority, starts_at, ends_at, published_at)
      values (p_id, draft.revision + 1, spec, mode_value, collection_value,
        priority_value, starts_value, ends_value, publication_time);
  elsif p_operation = 'withdraw' then
    delete from public.today_story_publications where id = p_id;
  end if;

  update public.today_story_drafts set
    story = case when p_operation = 'save' then p_story else story end,
    revision = revision + 1, updated_at = publication_time, updated_by = p_actor
    where id = p_id returning * into draft;
  select * into active from public.today_story_publications
    where id = p_id order by revision desc limit 1;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.revision desc), '[]'::jsonb) into published
    from public.today_story_publications p where p.id = p_id
      and (p.superseded_at is null or p.superseded_at > publication_time);
  return jsonb_build_object('draft', to_jsonb(draft), 'publication',
    case when active.id is not null then to_jsonb(active) end, 'publications', published);
end;
$$;

revoke all on function public.admin_today_story_v1(text, uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.admin_today_story_v1(text, uuid, integer, uuid, jsonb) to service_role;

-- The Gamebase catalogue is already in the app for cover metadata. Only
-- public slugs, counts and timestamps come back as inputs. Lineup policy,
-- editorial decisions and the publication clock are server-side.
create function public.get_today_stories_v1(
  p_catalog jsonb,
  p_rotation integer,
  p_has_missed_chances boolean
) returns jsonb
language sql stable security invoker set search_path = ''
as $$
  with catalog as materialized (
    select c.slug, max(c.updated_at) as updated_at
    from jsonb_to_recordset(case when jsonb_typeof(p_catalog) = 'array' then
      case when jsonb_array_length(p_catalog) <= 1500 then p_catalog else '[]'::jsonb end
      else '[]'::jsonb end) as c(slug text, game_count integer, updated_at timestamptz)
    where length(c.slug) between 1 and 160 and c.game_count > 0
    group by c.slug
  ), available as materialized (
    select distinct on (coalesce('collection:' || p.collection_slug, p.id::text)) p.*
    from public.today_story_publications p
    where p.starts_at <= statement_timestamp() and (p.ends_at is null or p.ends_at > statement_timestamp())
      and (p.superseded_at is null or p.superseded_at > statement_timestamp())
      and (p.mode in ('standalone', 'hide') or exists (
        select from catalog c where c.slug = p.collection_slug
      ))
    order by coalesce('collection:' || p.collection_slug, p.id::text),
      p.priority, p.published_at desc, p.id
  ), editorial as materialized (
    select p.*, row_number() over (order by p.priority, p.published_at desc, p.id) as sequence
    from available p where p.mode <> 'hide'
    order by p.priority, p.published_at desc, p.id
    limit (6 - case when p_has_missed_chances then 1 else 0 end)
  ), automatic as materialized (
    select * from catalog c where not exists (
      select from available p where p.collection_slug = c.slug
    )
  ), room as (
    select (6 - case when p_has_missed_chances then 1 else 0 end - count(*))::int as total
    from editorial
  ), recent as materialized (
    select slug, row_number() over (order by updated_at desc, slug) as sequence
    from automatic where updated_at >= statement_timestamp() - interval '7 days'
    order by updated_at desc, slug
    limit (select least(total, 3) from room)
  ), archive_pool as (
    select a.slug, row_number() over (order by a.updated_at desc nulls last, a.slug) - 1 as n,
      count(*) over () as size
    from automatic a where not exists (select from recent r where r.slug = a.slug)
  ), archive_room as (
    select total - (select count(*)::int from recent) as slots from room
  ), archive as (
    select slug, case when size <= slots then n else
      mod(n - mod(greatest(coalesce(p_rotation, 0), 0)::bigint * slots, size) + size, size) end as sequence
    from archive_pool cross join archive_room where slots > 0
    order by sequence
    limit (select slots from archive_room)
  ), entries as (
    select 0 as group_rank, 0::bigint as sequence, jsonb_build_object('kind', 'missed_chances') as entry
      where p_has_missed_chances
    union all
    select 1, sequence, jsonb_strip_nulls(jsonb_build_object('kind', 'editorial', 'id', id,
      'revision', revision, 'mode', mode, 'collectionSlug', collection_slug,
      'title', story->>'title', 'coverUrl', story->>'coverUrl')) from editorial
    union all
    select 2, sequence, jsonb_build_object('kind', 'collection', 'collectionSlug', slug) from recent
    union all
    select 3, sequence, jsonb_build_object('kind', 'collection', 'collectionSlug', slug) from archive
  )
  select coalesce(jsonb_agg(entry order by group_rank, sequence), '[]'::jsonb) from entries;
$$;

revoke all on function public.get_today_stories_v1(jsonb, integer, boolean) from public, anon, authenticated;
grant execute on function public.get_today_stories_v1(jsonb, integer, boolean) to anon, authenticated, service_role;

-- The app supplies playability and a watched bit for these candidates only.
-- Neither a user identifier nor the rest of their watch history is needed.
create function public.pick_today_story_game_v1(p_candidates jsonb, p_preferred_id text)
returns text
language sql immutable security invoker set search_path = ''
as $$
  select value->>'id'
  from jsonb_array_elements(case when jsonb_typeof(p_candidates) = 'array' then
    case when jsonb_array_length(p_candidates) <= 32 then p_candidates else '[]'::jsonb end
    else '[]'::jsonb end) with ordinality as c(value, n)
  where length(value->>'id') between 1 and 200
  order by (value->>'id' is not distinct from p_preferred_id) desc,
    (value->'watched' = 'true'::jsonb) asc nulls first, n
  limit 1;
$$;

revoke all on function public.pick_today_story_game_v1(jsonb, text) from public, anon, authenticated;
grant execute on function public.pick_today_story_game_v1(jsonb, text) to anon, authenticated, service_role;

commit;
