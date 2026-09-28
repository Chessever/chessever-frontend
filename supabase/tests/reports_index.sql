-- Disposable PostgreSQL database only; creates public.games from scratch.
-- psql "$LOCAL_REPORTS_TEST_URL" -X -v ON_ERROR_STOP=1 -f supabase/tests/reports_index.sql
-- This is a SQL/plan regression test. The Dart tests validate parsed PGNs.
\set ON_ERROR_STOP on

create table public.games (
  id text primary key,
  last_move_time timestamptz,
  status text,
  pgn text
);

insert into public.games
select 'ordinary-' || lpad(n::text, 6, '0'),
       timestamptz '2026-09-28' - n * interval '1 minute',
       '1-0', repeat('1. e4 {An ordinary broadcast comment.} e5 ', 100)
from generate_series(1, 20000) n;

insert into public.games
select 'report-' || lpad(n::text, 3, '0'),
       case when n <= 128
         then timestamptz '2026-09-28' - (n / 2) * interval '1 day'
         else null end,
       '1-0', '1. e4 $247 {[%eval 0.2]} e5 1-0'
from generate_series(1, 136) n;

insert into public.games values
  ('legacy', '2000-01-01', '1/2-1/2', '1. e4 {[%chessever_annotation book_move] [%eval 0.2]} e5 1/2-1/2'),
  ('legacy-case', '1999-01-01', '0-1', '1. e4 {[% CHESSEVER_ANNOTATION best-move] [%eval #-3]} e5 0-1'),
  ('live', now(), '*', '1. e4 $247 {[%eval 0.2]} e5 *'),
  ('eval-only', now(), '1-0', '1. e4 {[%eval 0.2]} e5 1-0'),
  ('nag-only', now(), '1-0', '1. e4 $247 e5 1-0'),
  ('empty', now(), '1-0', null);

create table original_games as select id, last_move_time, status, md5(pgn) as pgn_hash from public.games;
analyze public.games;

-- This must fail before the concurrent index is installed: the previous query
-- had to search every PGN even to prove that no reports exist.
\ir ../manual/20260928152221_saved_reports_index_concurrently.sql
analyze public.games;

do $$
declare plan json;
begin
  execute $query$
    explain (analyze, buffers, format json)
    select id, last_move_time, pgn from public.games
    where status in ('1-0', '0-1', '1/2-1/2')
      and pgn like '%[\%eval %'
      and (pgn like '%$24%' or pgn ilike '%chessever_annotation%')
    order by last_move_time desc nulls last, id asc limit 30
  $query$ into plan;
  assert plan::text like '%games_saved_reports_page_idx%', 'Reports must use the partial index';
  assert plan::text not like '%Seq Scan%', 'Reports must not scan the game archive';
  assert not exists (
    (select id, last_move_time, status, md5(pgn) from games except select * from original_games)
    union all
    (select * from original_games except select id, last_move_time, status, md5(pgn) from games)
  ), 'Index creation must not change game data';
  raise notice 'First page uses the report index; all game data is unchanged.';
end;
$$;

-- Exercise parameterized queries repeatedly, as PostgREST does. The planner
-- must still pick the index after the prepared-plan threshold (five calls).
prepare reports_page(text[], text, text, text, integer) as
select id, last_move_time, pgn from public.games
where status = any($1) and pgn like $2 and (pgn like $3 or pgn ilike $4)
order by last_move_time desc nulls last, id asc limit $5;

do $$
declare plan json;
begin
  for attempt in 1..8 loop
    execute $query$
      explain (analyze, buffers, format json)
      execute reports_page('{1-0,0-1,1/2-1/2}', '%[\%eval %', '%$24%', '%chessever_annotation%', 30)
    $query$ into plan;
    assert plan::text like '%games_saved_reports_page_idx%', 'Prepared Reports query lost its index';
  end loop;
  raise notice 'Repeated parameterized queries keep using the report index.';
end;
$$;

do $$
declare
  row record;
  cursor_time timestamptz;
  cursor_id text;
  page_count integer;
  seen text[] := '{}';
  expected text[];
begin
  select array_agg(id order by last_move_time desc nulls last, id)
  into expected from public.games
  where status in ('1-0', '0-1', '1/2-1/2') and pgn like '%[\%eval %'
    and (pgn like '%$24%' or pgn ilike '%chessever_annotation%');
  loop
    page_count := 0;
    for row in
      select id, last_move_time from public.games
      where status in ('1-0', '0-1', '1/2-1/2') and pgn like '%[\%eval %'
        and (pgn like '%$24%' or pgn ilike '%chessever_annotation%')
        and (
          cursor_id is null
          or (cursor_time is not null and (
            last_move_time < cursor_time
            or (last_move_time = cursor_time and id > cursor_id)
            or last_move_time is null))
          or (cursor_time is null and last_move_time is null and id > cursor_id)
        )
      order by last_move_time desc nulls last, id limit 30
    loop
      seen := array_append(seen, row.id);
      cursor_id := row.id;
      cursor_time := row.last_move_time;
      page_count := page_count + 1;
    end loop;
    exit when page_count < 30;
  end loop;
  assert seen = expected, 'Cursor pages must have no missing, reordered, or duplicate reports';
  assert cardinality(seen) = 138, 'Include all reports, including old, tied, undated, and legacy rows';
  raise notice 'All 138 reports page in order, including timestamp ties and the undated tail.';
end;
$$;

-- Existing writers need no change: an ordinary UPDATE adds/removes a report
-- candidate atomically, and a live game only joins after it has finished.
update public.games set pgn = '1. e4 $247 {[%eval 0.2]} e5 1-0' where id = 'ordinary-000001';
update public.games set pgn = '1. e4 e5 1-0' where id = 'report-001';
update public.games set status = '1-0' where id = 'live';

do $$
declare ids text[];
begin
  select array_agg(id) into ids from public.games
  where status in ('1-0', '0-1', '1/2-1/2') and pgn like '%[\%eval %'
    and (pgn like '%$24%' or pgn ilike '%chessever_annotation%');
  assert 'ordinary-000001' = any(ids), 'Existing PGN writeback must add a report immediately';
  assert not ('report-001' = any(ids)), 'Replacing annotated PGN must remove stale membership';
  assert 'live' = any(ids), 'Finishing an annotated game must add it immediately';
  raise notice 'Existing PGN and status updates maintain report membership without triggers.';
end;
$$;
