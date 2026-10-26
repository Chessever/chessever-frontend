-- Partner news: articles from publications ChessEver partners with, shown in
-- the app's Feed and on chessever.com under the partner's own name and
-- linking back to the partner. RookReview is the first.
--
-- Every ten minutes pg_cron starts `partner-news-sync`, which reads each
-- enabled source's RSS feed, converts the articles to the apps' markdown and
-- upserts them here (upsert_partner_news). An article keeps its row when it
-- falls off the feed. Hide one by setting its status to 'hidden' (the sync
-- never publishes it again); take a whole partner off every surface by
-- setting its source's `enabled` to false.
--
-- Kept apart from `news` on purpose: `news` is ChessEver's own reporting,
-- and every surface that reads it (older app builds, the sitemap, JSON-LD)
-- presents its rows as ChessEver's.
--
-- Additive: two new tables, their functions and one cron job. Nothing
-- existing is changed.

begin;

create table public.partner_news_sources (
  -- Also the apps' key for the partner's name and mark.
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]{0,39}$'),
  name text not null check (length(btrim(name)) > 0),
  -- Article links must be https on this site.
  site_url text not null check (site_url ~ '^https://[^/]+$'),
  feed_url text not null check (feed_url ~ '^https://'),
  -- Hosts besides the site that pictures may come from.
  asset_hosts text[] not null default '{}',
  enabled boolean not null default true,
  last_attempt_at timestamptz,
  last_success_at timestamptz,
  last_error text,
  last_item_count integer,
  consecutive_failures integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.partner_news (
  id bigint generated always as identity primary key,
  source_id text not null references public.partner_news_sources(id) on delete cascade,
  guid text not null check (length(guid) between 1 and 512),
  -- The article on the partner's site.
  url text not null check (url ~ '^https://'),
  title text not null check (length(btrim(title)) between 1 and 400),
  summary text not null default '',
  -- Markdown, converted from the feed by partner-news-sync.
  content text not null check (length(content) between 1 and 200000),
  image_url text check (image_url is null or image_url ~ '^https://'),
  status text not null default 'published' check (status in ('published', 'hidden')),
  published_at timestamptz not null,
  -- What the article read like last time, so an unchanged one is skipped.
  content_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_id, guid)
);

create index partner_news_published_idx
  on public.partner_news (published_at desc, id desc)
  where status = 'published';

alter table public.partner_news_sources enable row level security;
alter table public.partner_news enable row level security;

-- The read policy asks this rather than the sources table, which stays
-- private (it holds sync errors).
create function public.partner_news_source_enabled(p_source_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (select enabled from public.partner_news_sources where id = p_source_id),
    false
  )
$$;

create policy "Published partner news is publicly readable"
  on public.partner_news
  for select
  to anon, authenticated
  using (status = 'published' and public.partner_news_source_enabled(source_id));

revoke all on public.partner_news_sources from public, anon, authenticated;
grant select, insert, update, delete on public.partner_news_sources to service_role;
revoke all on public.partner_news from public, anon, authenticated;
grant select on public.partner_news to anon, authenticated;
grant select, insert, update, delete on public.partner_news to service_role;

-- One feed's articles, as partner-news-sync parsed them: new ones are
-- inserted, changed ones replaced, unchanged ones untouched (their
-- updated_at holds still for the apps' change check). Status is never
-- written, so a hidden article stays hidden. Records the success on the
-- source.
create function public.upsert_partner_news(p_source_id text, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_received integer;
  v_inserted integer := 0;
  v_updated integer := 0;
begin
  if not exists (select 1 from public.partner_news_sources where id = p_source_id) then
    raise exception 'unknown partner news source: %', p_source_id;
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'p_items must be a JSON array';
  end if;
  v_received := jsonb_array_length(p_items);

  with incoming as (
    select distinct on (guid) *
    from (
      select
        btrim(item->>'guid') as guid,
        btrim(item->>'url') as url,
        btrim(item->>'title') as title,
        coalesce(btrim(item->>'summary'), '') as summary,
        item->>'content' as content,
        nullif(btrim(item->>'image_url'), '') as image_url,
        (item->>'published_at')::timestamptz as published_at,
        position
      from jsonb_array_elements(p_items) with ordinality as e(item, position)
    ) raw
    where coalesce(guid, '') <> ''
      and coalesce(url, '') <> ''
      and coalesce(title, '') <> ''
      and coalesce(content, '') <> ''
      and published_at is not null
    order by guid, position
  ),
  hashed as (
    select
      incoming.*,
      md5(concat_ws(
        chr(31),
        url,
        title,
        summary,
        content,
        coalesce(image_url, ''),
        extract(epoch from published_at)::text
      )) as content_hash
    from incoming
  ),
  written as (
    insert into public.partner_news as existing (
      source_id, guid, url, title, summary, content, image_url,
      published_at, content_hash
    )
    select
      p_source_id, guid, url, title, summary, content, image_url,
      published_at, content_hash
    from hashed
    on conflict (source_id, guid) do update set
      url = excluded.url,
      title = excluded.title,
      summary = excluded.summary,
      content = excluded.content,
      image_url = excluded.image_url,
      published_at = excluded.published_at,
      content_hash = excluded.content_hash,
      updated_at = now()
    where existing.content_hash is distinct from excluded.content_hash
    returning (xmax = 0) as inserted
  )
  select
    count(*) filter (where inserted),
    count(*) filter (where not inserted)
  into v_inserted, v_updated
  from written;

  update public.partner_news_sources
  set last_attempt_at = now(),
      last_success_at = now(),
      last_error = null,
      last_item_count = v_received,
      consecutive_failures = 0,
      updated_at = now()
  where id = p_source_id;

  return jsonb_build_object(
    'received', v_received,
    'inserted', v_inserted,
    'updated', v_updated
  );
end;
$$;

create function public.record_partner_news_failure(p_source_id text, p_error text)
returns void
language sql
security definer
set search_path to 'public'
as $$
  update public.partner_news_sources
  set last_attempt_at = now(),
      last_error = left(coalesce(p_error, 'unknown error'), 500),
      consecutive_failures = consecutive_failures + 1,
      updated_at = now()
  where id = p_source_id
$$;

create function public.kick_partner_news_sync()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_url text;
  v_token text;
  v_headers jsonb := jsonb_build_object('Content-Type', 'application/json');
begin
  if not exists (select 1 from public.partner_news_sources where enabled) then
    return;
  end if;
  v_url := public.get_vault_secret('partner_news_sync_url');
  if v_url is null or v_url = '' then
    v_url := 'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/partner-news-sync';
  end if;
  v_token := public.get_vault_secret('live_dispatch_token');
  if v_token is not null and v_token <> '' then
    v_headers := v_headers || jsonb_build_object('x-stream-token', v_token);
  end if;
  begin
    perform net.http_post(
      url := v_url,
      body := '{}'::jsonb,
      headers := v_headers,
      timeout_milliseconds := 60000
    );
  exception when others then
    null;
  end;
end;
$$;

revoke execute on function public.partner_news_source_enabled(text) from public;
revoke execute on function public.upsert_partner_news(text, jsonb) from public, anon, authenticated;
revoke execute on function public.record_partner_news_failure(text, text) from public, anon, authenticated;
revoke execute on function public.kick_partner_news_sync() from public, anon, authenticated;
grant execute on function public.partner_news_source_enabled(text) to anon, authenticated, service_role;
grant execute on function public.upsert_partner_news(text, jsonb) to service_role;
grant execute on function public.record_partner_news_failure(text, text) to service_role;
grant execute on function public.kick_partner_news_sync() to service_role;

insert into public.partner_news_sources (id, name, site_url, feed_url, asset_hosts)
values (
  'rookreview',
  'RookReview',
  'https://rookreview.com',
  'https://rookreview.com/feed.xml',
  array['rookreview.b-cdn.net']
);

-- Every ten minutes, off the minute the other jobs bunch up on.
select cron.schedule(
  'partner-news-sync',
  '4-59/10 * * * *',
  $$select public.kick_partner_news_sync()$$
);

commit;
