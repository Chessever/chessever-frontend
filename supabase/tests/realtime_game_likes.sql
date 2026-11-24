-- LOCAL FIXTURE ONLY: run in an empty disposable PostgreSQL database.
begin;
create role anon;
create role authenticated;
create schema auth;
create schema realtime;
create schema rewarded_private;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create function realtime.topic() returns text language sql stable as $$
  select current_setting('realtime.topic', true);
$$;
create table realtime.messages(topic text, event text, extension text, payload jsonb, private boolean);
alter table realtime.messages enable row level security;
create function realtime.send(jsonb, text, text, boolean) returns void language sql as $$
  insert into realtime.messages values ($3, $2, 'broadcast', $1, $4);
$$;
create table public.user_folders(id uuid primary key, user_id uuid, is_liked_games bool);
create table public.user_saved_analyses(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  folder_id uuid references public.user_folders on delete cascade,
  source_game_id text,
  source_tournament_id text,
  title text,
  chess_game jsonb,
  created_at timestamptz default now(),
  tags text[] default '{}',
  notes text
);
alter table public.user_saved_analyses enable row level security;
create policy own_analysis on public.user_saved_analyses to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant usage on schema auth, public, realtime to authenticated;
grant select on public.user_folders, realtime.messages to authenticated;
grant select, insert, update, delete on public.user_saved_analyses to authenticated;

\ir ../migrations/20261029130000_game_likes_one_definition.sql
\ir ../migrations/20261124142016_realtime_game_likes.sql

insert into public.user_folders values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',true),
 ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',true),
 ('10000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001',false);

-- A library copy and two legacy inserts for the same account/game.
insert into public.user_saved_analyses
  (user_id, folder_id, source_game_id, title, tags, notes) values
 ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','g','Library','{}','Library note'),
 ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','g','Old like','{keep}','Old note'),
 ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','g','Old like','{keep}','Old note');

do $$
begin
  assert (select count(*) from realtime.messages) = 4, 'only likes notify';
  assert not exists (select 1 from realtime.messages where payload <> '{}'),
    'notifications must not include private rows';
  assert not exists (
    select 1 from realtime.messages where private <> (topic like 'account-likes:%')
  ), 'only account broadcasts are private';
  assert not has_function_privilege('anon','public.write_game_like(text,uuid,jsonb)','execute');
end;
$$;
set local role anon;
do $$
begin
  assert public.game_like_summary('g') = '{"count":1,"liked":false}', 'guests see the aggregate';
end;
$$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
do $$
declare
  folder constant uuid := '10000000-0000-0000-0000-000000000001';
  result jsonb;
begin
  assert public.game_like_count('g') = 1, 'older clients count distinct accounts';
  assert public.game_like_summary('g') = '{"count":1,"liked":true}', 'new clients see the legacy like';
  result := public.write_game_like('g', folder, '{"title":"New","chess_game":{}}');
  assert result->>'notes' = 'Old note' and result->'tags' = '["keep"]', 'a retry preserves the saved analysis';
  assert (select count(*) from public.user_saved_analyses where folder_id=folder) = 2;
  perform public.write_game_like('g', folder);
  assert public.game_like_summary('g') = '{"count":0,"liked":false}', 'unlike removes old duplicates';
  assert (select count(*) from public.user_saved_analyses where notes='Library note') = 1, 'library copy stays';
  result := public.write_game_like('g', folder, '{"title":"New","chess_game":{}}');
  assert result->>'title' = 'New' and (result->>'id') is not null and (result->>'created_at') is not null;
  assert public.write_game_like('g', folder, '{"title":"Retry","chess_game":{}}') = result;
  assert public.game_like_summary('g') = '{"count":1,"liked":true}';
  update public.user_saved_analyses
    set folder_id='10000000-0000-0000-0000-000000000003' where id=(result->>'id')::uuid;
  assert public.game_like_summary('g') = '{"count":0,"liked":false}', 'moving the row out unlikes it';
  update public.user_saved_analyses set folder_id=folder where id=(result->>'id')::uuid;
  assert public.game_like_summary('g') = '{"count":1,"liked":true}', 'move undo restores the like';
end;
$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
do $$
begin
  assert public.game_like_summary('g') = '{"count":1,"liked":false}', 'other accounts see only the aggregate';
  perform set_config('realtime.topic','account-likes:00000000-0000-0000-0000-000000000001',true);
  assert (select count(*) from realtime.messages) = 0, 'other accounts cannot join the owner channel';
  begin
    perform public.write_game_like('g', '10000000-0000-0000-0000-000000000001', '{"title":"Wrong owner","chess_game":{}}');
    raise exception 'wrong folder accepted';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
do $$
begin
  assert (select count(*) from realtime.messages where topic='game-likes:g' and not private) = 7,
    'legacy inserts, each removed row, fresh insert and both moves broadcast publicly';
end;
$$;
delete from public.user_folders where id='10000000-0000-0000-0000-000000000001';
do $$
begin
  assert (select count(*) from realtime.messages where topic='game-likes:g') = 8,
    'cascading folder deletion broadcasts';
end;
$$;
rollback;
