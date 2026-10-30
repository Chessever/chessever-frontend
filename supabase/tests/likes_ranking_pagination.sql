-- LOCAL FIXTURE ONLY: run in an empty disposable PostgreSQL database.
begin;
create role anon;
create role authenticated;
create schema auth;
create schema rewarded_private;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create table public.user_folders(id int primary key, user_id uuid, is_liked_games bool);
create table public.user_saved_analyses(source_game_id text, user_id uuid, folder_id int, created_at timestamptz);
grant usage on schema public, auth, rewarded_private to authenticated;
\ir ../migrations/20261028150850_likes_ranking_pagination.sql

insert into public.user_folders values
 (1, '00000000-0000-0000-0000-000000000001', true),
 (2, '00000000-0000-0000-0000-000000000002', true),
 (3, '00000000-0000-0000-0000-000000000003', true),
 (4, '00000000-0000-0000-0000-000000000001', false);
insert into public.user_saved_analyses
 select 'g' || lpad(g::text,3,'0'), f.user_id, f.id, '2026-10-01T12:00:00Z'
 from generate_series(1,65) g cross join public.user_folders f where f.id <= 2;
insert into public.user_saved_analyses values
 ('leader','00000000-0000-0000-0000-000000000001',1,'2026-10-01T12:00:00Z'),
 ('leader','00000000-0000-0000-0000-000000000002',2,'2026-10-01T12:00:00Z'),
 ('leader','00000000-0000-0000-0000-000000000003',3,'2026-10-01T12:00:00Z'),
 ('one-like','00000000-0000-0000-0000-000000000001',1,'2026-10-01T12:00:00Z'),
 ('g001','00000000-0000-0000-0000-000000000001',1,'2026-10-01T12:00:00Z'),
 ('other-folder','00000000-0000-0000-0000-000000000001',4,'2026-10-01T12:00:00Z');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$
declare r record; ids text[] := '{}'; last_likes bigint; last_id text; page_count int;
begin
  loop
    page_count := 0;
    for r in select * from public.most_liked_ranking_page(
      '2026-10-01', '2026-11-01', 12, last_likes, last_id)
    loop
      assert not r.source_game_id = any(ids), 'duplicate game across pages';
      ids := array_append(ids,r.source_game_id);
      last_likes := r.like_count; last_id := r.source_game_id;
      page_count := page_count + 1;
    end loop;
    exit when page_count < 12;
  end loop;
  assert cardinality(ids) = 66, 'pagination must continue beyond 50 games';
  assert ids[1] = 'leader' and ids[2] = 'g001' and ids[66] = 'g065', 'tie order';
  assert (select count(*) from public.most_liked_ranking_page('2026-10-01','2026-11-01',500)) = 50, 'page-size cap';
  assert (select count(*) from public.most_liked_ranking_page('2026-11-01','2026-12-01')) = 0, 'date window';
  assert (select count(*) from public.most_liked_ranking_page('2026-10-01T12:00:00Z','2026-11-01',1)) = 1, 'inclusive start';
  assert (select count(*) from public.most_liked_ranking_page('2026-10-01','2026-10-01T12:00:00Z')) = 0, 'exclusive end';
  assert (select count(*) from public.most_liked_ranking_page('2026-10-01','2028-01-01')) = 0, 'maximum window';
  begin
    perform * from public.most_liked_ranking_page('2026-10-01','2026-11-01',12,2,null);
    raise exception 'partial cursor accepted';
  exception when others then
    if sqlerrm <> 'invalid_cursor' then raise; end if;
  end;
end;
$$;
select set_config('request.jwt.claim.sub','',true);
do $$
begin
  begin
    perform * from public.most_liked_ranking_page('2026-10-01','2026-11-01');
    raise exception 'unauthenticated caller accepted';
  exception when others then
    if sqlerrm <> 'authentication_required' then raise; end if;
  end;
  assert not has_function_privilege('anon','public.most_liked_ranking_page(timestamptz,timestamptz,integer,bigint,text)','execute'), 'anon must not execute';
end;
$$;
rollback;
