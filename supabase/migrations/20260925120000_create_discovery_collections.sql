-- Discovery › Collection: curated sets of annotated games, uploaded by the
-- ChessEver team (a GM's annotated games from one event, or the games of a
-- book). Read by everyone, written only with the service role (see
-- docs/collections.md and scripts/collections/upload_collection.py).
--
-- Additive only: two new tables, their read policies and indexes. Nothing
-- existing is touched. Idempotent, so replaying it is harmless.

create table if not exists public.discovery_collections (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  -- 'event': games from one tournament; 'book': games from a book.
  kind text not null default 'event' check (kind in ('event', 'book')),
  title text not null,
  -- One line under the title: "Saint Louis · October 2025", a book's
  -- publisher and year.
  subtitle text,
  -- The annotator, or the book's author.
  author text,
  -- The About tab: who the author is and what the collection is about.
  -- Plain text; blank lines separate paragraphs.
  about text,
  cover_url text,
  sort_order integer not null default 0,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.discovery_collection_games (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null
    references public.discovery_collections (id) on delete cascade,
  sort_order integer not null default 0,
  -- The whole game as uploaded: headers, moves, comments, NAGs, variations.
  pgn text not null,
  -- Copied from the PGN headers so lists and the Players tab never parse.
  white text,
  black text,
  white_elo integer,
  black_elo integer,
  white_title text,
  black_title text,
  white_fed text,
  black_fed text,
  white_fide_id bigint,
  black_fide_id bigint,
  result text,
  event text,
  round text,
  played_on text,
  eco text,
  opening text,
  annotator text,
  created_at timestamptz not null default now()
);

create index if not exists discovery_collection_games_collection_idx
  on public.discovery_collection_games (collection_id, sort_order);

create index if not exists discovery_collections_published_idx
  on public.discovery_collections (published, sort_order);

alter table public.discovery_collections enable row level security;
alter table public.discovery_collection_games enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'discovery_collections'
      and policyname = 'Published collections are readable by everyone'
  ) then
    create policy "Published collections are readable by everyone"
      on public.discovery_collections
      for select
      to anon, authenticated
      using (published);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'discovery_collection_games'
      and policyname = 'Games of published collections are readable by everyone'
  ) then
    create policy "Games of published collections are readable by everyone"
      on public.discovery_collection_games
      for select
      to anon, authenticated
      using (
        exists (
          select 1
          from public.discovery_collections c
          where c.id = discovery_collection_games.collection_id
            and c.published
        )
      );
  end if;
end
$$;

grant select on public.discovery_collections to anon, authenticated;
grant select on public.discovery_collection_games to anon, authenticated;
