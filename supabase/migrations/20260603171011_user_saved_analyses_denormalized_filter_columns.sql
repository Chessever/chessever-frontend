-- Denormalize the queryable PGN headers out of chess_game->'md' into typed,
-- indexable columns so filter/sort/paginate can run as plain SQL instead of
-- client-side over a paginated page. Mirrors the denormalization pattern used
-- by the gamebase `game` table. Source-agnostic: TWIC and broadcast saves both
-- write `md`, so this is the single uniform truth for every save path.

-- ---- helper extractors (IMMUTABLE, reused by trigger + backfill) ----------

-- Safe int from messy elo text ("2499" -> 2499, "", "unrated", null -> null).
create or replace function public.usa_md_int(p text)
returns int language sql immutable set search_path = '' as $$
  select nullif(regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g'), '')::int
$$;

-- PGN result token -> W/B/D (ongoing '*' -> null).
create or replace function public.usa_md_result(p text)
returns char(1) language sql immutable set search_path = '' as $$
  select case p
    when '1-0' then 'W'
    when '0-1' then 'B'
    when '1/2-1/2' then 'D'
    when '½-½' then 'D'
    when '0.5-0.5' then 'D'
    else null end
$$;

-- PGN date "YYYY.MM.DD" -> date; rejects placeholders like '????.??.??'.
create or replace function public.usa_md_date(p text)
returns date language sql immutable set search_path = '' as $$
  select case
    when coalesce(p, '') ~ '^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])$'
    then to_date(p, 'YYYY.MM.DD')
    else null end
$$;

-- Time-control category, mirroring the client _inferTimeControl: only exact
-- word matches classify; anything else (increments, paragraphs) -> null so the
-- filter never wrongly excludes an unclassifiable game. Prefers TcCategory.
create or replace function public.usa_md_tc(p_tc text, p_cat text)
returns text language sql immutable set search_path = '' as $$
  select case lower(trim(coalesce(nullif(p_cat, ''), p_tc, '')))
    when 'standard' then 'classical'
    when 'classical' then 'classical'
    when 'rapid' then 'rapid'
    when 'blitz' then 'blitz'
    when 'bullet' then 'blitz'
    else null end
$$;

-- ECO normalize ('?'/'UNKNOWN'/'' -> null).
create or replace function public.usa_md_eco(p text)
returns text language sql immutable set search_path = '' as $$
  select case when upper(trim(coalesce(p, ''))) in ('', '?', 'UNKNOWN')
    then null else trim(p) end
$$;

-- ---- columns --------------------------------------------------------------

alter table public.user_saved_analyses
  add column if not exists white_elo    int,
  add column if not exists black_elo    int,
  add column if not exists avg_elo      int,
  add column if not exists result       char(1),
  add column if not exists game_date    date,
  add column if not exists eco          text,
  add column if not exists time_control text,
  add column if not exists white_name   text,
  add column if not exists black_name   text,
  add column if not exists event        text;

-- ---- trigger (fires on insert + whenever chess_game changes) ---------------

create or replace function public.usa_set_filter_columns()
returns trigger language plpgsql set search_path = '' as $$
declare
  md jsonb := new.chess_game -> 'md';
  we int := public.usa_md_int(md ->> 'WhiteElo');
  be int := public.usa_md_int(md ->> 'BlackElo');
begin
  new.white_elo := we;
  new.black_elo := be;
  new.avg_elo := case
    when we is not null and be is not null then (we + be) / 2
    when we is not null then we
    else be end;
  new.result := public.usa_md_result(md ->> 'Result');
  new.game_date := coalesce(
    public.usa_md_date(md ->> 'Date'),
    public.usa_md_date(md ->> 'UTCDate'),
    public.usa_md_date(md ->> 'EventDate'));
  new.eco := public.usa_md_eco(md ->> 'ECO');
  new.time_control := public.usa_md_tc(md ->> 'TimeControl', md ->> 'TcCategory');
  new.white_name := nullif(trim(coalesce(md ->> 'White', '')), '');
  new.black_name := nullif(trim(coalesce(md ->> 'Black', '')), '');
  new.event := nullif(trim(coalesce(md ->> 'Event', '')), '');
  return new;
end;
$$;

drop trigger if exists trg_usa_set_filter_columns on public.user_saved_analyses;
create trigger trg_usa_set_filter_columns
  before insert or update of chess_game on public.user_saved_analyses
  for each row execute function public.usa_set_filter_columns();

-- ---- backfill existing rows (reuse the trigger, don't bump updated_at) ------

alter table public.user_saved_analyses
  disable trigger update_user_saved_analyses_updated_at;

update public.user_saved_analyses set chess_game = chess_game;

alter table public.user_saved_analyses
  enable trigger update_user_saved_analyses_updated_at;

-- ---- indexes (filter folder_id, then sort; trgm for name/event search) -----

create index if not exists idx_usa_folder_game_date
  on public.user_saved_analyses (folder_id, game_date desc nulls last);
create index if not exists idx_usa_folder_avg_elo
  on public.user_saved_analyses (folder_id, avg_elo desc nulls last);
create index if not exists idx_usa_folder_white_elo
  on public.user_saved_analyses (folder_id, white_elo desc nulls last);
create index if not exists idx_usa_folder_black_elo
  on public.user_saved_analyses (folder_id, black_elo desc nulls last);
create index if not exists idx_usa_white_name_trgm
  on public.user_saved_analyses using gin (lower(white_name) gin_trgm_ops);
create index if not exists idx_usa_black_name_trgm
  on public.user_saved_analyses using gin (lower(black_name) gin_trgm_ops);
create index if not exists idx_usa_event_trgm
  on public.user_saved_analyses using gin (lower(event) gin_trgm_ops);
