-- Canonical, owner-scoped Lichess Study references. These rows deliberately
-- contain no mirrored chapter body: progress only points back to the canonical
-- source and to the version of metadata the user last saw.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;

create or replace function private.is_safe_study_display_snapshot(
  p_snapshot jsonb
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $function$
  select
    p_snapshot is not null
    and pg_catalog.jsonb_typeof(p_snapshot) = 'object'
    and pg_catalog.octet_length(p_snapshot::text) <= 2048
    and (p_snapshot - array['title', 'author_username', 'attribution']) = '{}'::jsonb
    and (
      not (p_snapshot ? 'title')
      or (
        pg_catalog.jsonb_typeof(p_snapshot -> 'title') = 'string'
        and pg_catalog.char_length(p_snapshot ->> 'title') between 1 and 240
        and (p_snapshot ->> 'title') = pg_catalog.btrim(p_snapshot ->> 'title')
      )
    )
    and (
      not (p_snapshot ? 'author_username')
      or (
        pg_catalog.jsonb_typeof(p_snapshot -> 'author_username') = 'string'
        and pg_catalog.char_length(p_snapshot ->> 'author_username') between 1 and 80
        and (p_snapshot ->> 'author_username') = pg_catalog.btrim(p_snapshot ->> 'author_username')
      )
    )
    and (
      not (p_snapshot ? 'attribution')
      or (
        pg_catalog.jsonb_typeof(p_snapshot -> 'attribution') = 'string'
        and pg_catalog.char_length(p_snapshot ->> 'attribution') between 1 and 320
        and (p_snapshot ->> 'attribution') = pg_catalog.btrim(p_snapshot ->> 'attribution')
      )
    );
$function$;

create table public.user_study_bookmarks (
  user_id uuid not null references auth.users(id) on delete cascade,
  lichess_study_id text not null,
  lichess_chapter_id text,
  last_ply integer,
  content_version text,
  display_snapshot jsonb not null default '{}'::jsonb,
  bookmarked_at timestamptz not null default pg_catalog.now(),
  progress_updated_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (user_id, lichess_study_id),
  constraint user_study_bookmarks_canonical_study_id
    check (lichess_study_id ~ '^[A-Za-z0-9]{8}$'),
  constraint user_study_bookmarks_canonical_chapter_id
    check (
      lichess_chapter_id is null
      or lichess_chapter_id ~ '^[A-Za-z0-9]{1,64}$'
    ),
  constraint user_study_bookmarks_last_ply_nonnegative
    check (last_ply is null or last_ply between 0 and 1000000),
  constraint user_study_bookmarks_progress_pair
    check (
      (lichess_chapter_id is null and last_ply is null)
      or (lichess_chapter_id is not null and last_ply is not null)
    ),
  constraint user_study_bookmarks_content_version_safe
    check (
      content_version is null
      or content_version ~ '^sha256:[0-9a-f]{64}$'
    ),
  constraint user_study_bookmarks_display_snapshot_safe
    check (private.is_safe_study_display_snapshot(display_snapshot)),
  constraint user_study_bookmarks_progress_timestamp_consistent
    check (
      (last_ply is null and progress_updated_at is null)
      or (last_ply is not null and progress_updated_at is not null)
    )
);

comment on table public.user_study_bookmarks is
  'Owner-scoped canonical Lichess Study bookmark and progress references; never mirrored Study content.';

create index user_study_bookmarks_recent_activity_idx
  on public.user_study_bookmarks (
    user_id,
    progress_updated_at desc nulls last,
    bookmarked_at desc
  );

create or replace function private.stamp_user_study_bookmark()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_now timestamptz := pg_catalog.statement_timestamp();
begin
  if tg_op = 'INSERT' then
    new.bookmarked_at := v_now;
    new.updated_at := v_now;
    if new.last_ply is not null then
      new.progress_updated_at := v_now;
    else
      new.progress_updated_at := null;
    end if;
    return new;
  end if;

  -- Canonical identity is immutable. Moving a bookmark is a delete + insert.
  new.user_id := old.user_id;
  new.lichess_study_id := old.lichess_study_id;
  new.bookmarked_at := old.bookmarked_at;
  new.updated_at := v_now;

  if new.lichess_chapter_id is distinct from old.lichess_chapter_id
    or new.last_ply is distinct from old.last_ply
    or new.content_version is distinct from old.content_version
  then
    new.progress_updated_at := case
      when new.last_ply is null then null
      else v_now
    end;
  else
    new.progress_updated_at := old.progress_updated_at;
  end if;

  return new;
end;
$function$;

create trigger stamp_user_study_bookmark
before insert or update on public.user_study_bookmarks
for each row execute function private.stamp_user_study_bookmark();

alter table public.user_study_bookmarks enable row level security;

revoke all on table public.user_study_bookmarks
from public, anon, authenticated;

grant select, insert, update, delete on table public.user_study_bookmarks
to authenticated;

create policy "Users can read their own Study bookmarks"
  on public.user_study_bookmarks
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy "Users can create their own Study bookmarks"
  on public.user_study_bookmarks
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy "Users can update their own Study bookmarks"
  on public.user_study_bookmarks
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "Users can remove their own Study bookmarks"
  on public.user_study_bookmarks
  for delete
  to authenticated
  using (user_id = (select auth.uid()));
