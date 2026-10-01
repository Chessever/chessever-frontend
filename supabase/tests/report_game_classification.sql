-- Run only on a disposable local PostgreSQL database, never a live backend.
\set ON_ERROR_STOP on
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role bypassrls; end if;
end; $$;
create table public.games (
  id text primary key, pgn text, status text, last_move_time timestamptz
);
alter table public.games enable row level security;
create policy visible_games on public.games for select
  using (id <> 'hidden');
grant select on public.games to anon, authenticated, service_role;
grant update on public.games to service_role;
insert into public.games values
  ('new', 'original PGN', '1-0', now()),
  ('old', 'legacy PGN', '0-1', now()),
  ('live', 'live PGN', '*', now()),
  ('hidden', 'private PGN', '1-0', now());
create table originals as select id, pgn, status, last_move_time from public.games;

\ir ../migrations/20260930183029_report_game_classification.sql
\ir ../migrations/20260930205935_report_game_classification_batch.sql
\ir ../manual/20260930183029_report_game_classification_index_concurrently.sql
-- Idempotent schema and function installation.
\ir ../migrations/20260930183029_report_game_classification.sql

do $$
declare payload jsonb := '{"version":1,"result":"1-0","tags":["comeback","miniature"],"primary":"comeback","moves":24}';
begin
  assert not exists (
    (select id, pgn, status, last_move_time from games except select * from originals)
    union all (select * from originals except select id, pgn, status, last_move_time from games)
  ), 'Migration changed existing game data';
  assert not exists (select 1 from games where report_game_classification is not null);
  assert not has_function_privilege('anon', 'store_report_game_classification(text,text,jsonb)', 'execute');
  assert not has_function_privilege('authenticated', 'store_report_game_classification(text,text,jsonb)', 'execute');
  assert has_function_privilege('service_role', 'store_report_game_classification(text,text,jsonb)', 'execute');
  assert not has_function_privilege('authenticated', 'report_games_needing_classification(integer)', 'execute');
  assert not has_function_privilege('anon', 'store_report_game_classifications(jsonb)', 'execute');
  assert not has_function_privilege('authenticated', 'store_report_game_classifications(jsonb)', 'execute');
  assert has_function_privilege('service_role', 'store_report_game_classifications(jsonb)', 'execute');
  assert public.store_report_game_classifications('[]') = '[]';
  assert public.store_report_game_classification('new', 'original PGN', payload) = 'updated';
  assert public.store_report_game_classification('new', 'original PGN', payload) = 'unchanged';
  assert public.store_report_game_classification('new', 'different PGN', payload) = 'stale';
  assert public.store_report_game_classification('missing', 'PGN', payload) = 'stale';
  assert public.store_report_game_classification('live', 'live PGN', payload) = 'stale';
  assert public.store_report_game_classification('old', 'legacy PGN', payload) = 'stale',
    'A mismatched result must not acquire labels';
  assert (select count(*) from public.report_games_by_type('comeback')) = 1;
  assert (select count(*) from public.report_games_by_type('miniature')) = 1;
  assert (select count(*) from public.report_games_by_type('marathon')) = 0;
  assert (select count(*) from public.report_games_by_type('unknown')) = 0;
  assert public.store_report_game_classification('hidden', 'private PGN', payload) = 'updated';
  begin
    perform public.store_report_game_classification('new', 'original PGN', '{"version":1,"tags":["fake"]}');
    raise exception 'unknown label accepted';
  exception when raise_exception then
    assert sqlerrm = 'unknown report game classification';
  end;
  update games set status = '0-1' where id = 'new';
  assert not exists (select 1 from public.report_games_by_type('comeback') where id = 'new');
  update games set status = '1-0', pgn = 'newer PGN' where id = 'new';
  assert not exists (select 1 from public.report_games_by_type('comeback') where id = 'new'),
    'Changed PGNs must not appear with stale labels';
end;
$$;

set role authenticated;
do $$
begin
  assert not exists (select 1 from public.report_games_by_type('comeback')),
    'The set-returning RPC must enforce caller RLS';
  assert (select count(*) from games) = 3, 'All reports keep existing read permissions';
end;
$$;
reset role;

-- Broadcast overrides must not change existing fields as a side effect of
-- optional metadata. Roll back their effects without changing the trigger.
create table trigger_effects (game_id text);
create function test_report_override() returns trigger language plpgsql as $$
begin
  if new.id = 'old' then
    new.pgn := 'override PGN';
    insert into public.trigger_effects values (new.id);
  end if;
  return new;
end;
$$;
create trigger test_report_override before update on public.games
  for each row execute function test_report_override();
do $$ begin
  assert public.store_report_game_classification('old', 'legacy PGN',
    '{"version":1,"result":"0-1","tags":["miniature"]}') = 'stale';
  assert (select pgn from games where id = 'old') = 'legacy PGN';
  assert (select report_game_classification from games where id = 'old') is null;
  assert not exists (select 1 from trigger_effects), 'Trigger effects must roll back';
end; $$;
drop trigger test_report_override on public.games;
drop function test_report_override();
drop table trigger_effects;

do $$
declare items jsonb;
begin
  items := jsonb_build_array(jsonb_build_object('p_game_id', 'old',
    'p_expected_pgn', 'legacy PGN', 'p_classification',
    jsonb_build_object('version',1,'result','0-1','tags',jsonb_build_array('miniature'))));
  assert public.store_report_game_classifications(items) = '["updated"]';
  assert public.store_report_game_classifications(items) = '["unchanged"]';
  -- A bad later item rolls the whole transaction back.
  items := jsonb_build_array(jsonb_build_object('p_game_id','old',
    'p_expected_pgn','legacy PGN','p_classification',
    jsonb_build_object('version',1,'result','0-1','tags',jsonb_build_array('marathon'))),
    jsonb_build_object('p_game_id','z-invalid','p_expected_pgn','pgn','p_classification','{}'::jsonb));
  begin
    perform public.store_report_game_classifications(items);
    raise exception 'invalid batch accepted';
  exception when raise_exception then
    assert sqlerrm = 'invalid report game classification';
  end;
  assert (select report_game_classification->'tags' from games where id='old') = '["miniature"]';
  begin
    perform public.store_report_game_classifications(
      (select jsonb_agg('{}'::jsonb) from generate_series(1,101)));
    raise exception 'oversized batch accepted';
  exception when raise_exception then
    assert sqlerrm = 'classification batch is too large';
  end;
end; $$;

-- A selective type query must inline and use its metadata index.
insert into public.games(id, pgn, status, report_game_classification)
select 'bulk-' || n, 'pgn-' || n, '1-0',
  jsonb_build_object('version', 1, 'result', '1-0', 'tags', jsonb_build_array(case when n % 1000 = 0 then 'marathon' else 'deadlock' end),
    'pgnHash', md5('pgn-' || n))
from generate_series(1, 10000) n;
analyze public.games;
do $$
declare plan json;
begin
  execute 'explain (analyze, format json) select id from public.report_games_by_type(''marathon'') limit 30' into plan;
  assert plan::text not like '%Function Scan%', 'RPC must inline for cursor/limit pushdown';
  assert plan::text like '%games_report_game_classification_idx%', 'Selective type query needs metadata index';
  assert (select count(*) from public.report_games_by_type('marathon')) = 10;
  insert into games(id, pgn, status) values ('backfill', '1. e4 $247 {[%eval 0.2]} e5 1-0', '1-0');
  assert (select count(*) from public.report_games_needing_classification(1)) = 1;
  perform public.store_report_game_classification('backfill', '1. e4 $247 {[%eval 0.2]} e5 1-0',
    '{"version":1,"result":"1-0","tags":["miniature"]}');
  assert not exists (select 1 from public.report_games_needing_classification(1));
  assert (select count(*) from public.report_games_needing_classification(2)) = 1;
  raise notice 'Additive metadata, idempotence, stale-input exclusion, RLS and query plan passed.';
end;
$$;
