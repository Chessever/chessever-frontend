-- LOCAL CONTRACT TEST FIXTURE ONLY: disposable PostgreSQL, NOT a Supabase
-- integration/parity test. Bootstrap mimics auth UUID + role/RLS essentials,
-- not GoTrue, signed JWTs, PostgREST, schema cache or production auth settings.
-- Run with scripts/inbox/run_sql_tests.py; it creates/destroys its own cluster.
\set ON_ERROR_STOP on
\if :{?editorial_inbox_local_fixture}
\else
  \echo 'Refusing: this SQL requires the disposable local fixture runner.'
  \quit 3
\endif

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create table auth.users (id uuid primary key, is_anonymous boolean not null default false);
create function auth.uid() returns uuid language sql stable set search_path = '' as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema public, auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
-- Mimic permissive Supabase default grants to test explicit revocations.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

\ir ../migrations/20260930170000_editorial_inbox.sql

create temp table fixture_results (label text primary key, passed boolean not null);
grant insert, select on fixture_results to anon, authenticated, service_role;
create function pg_temp.ok(condition boolean, label text) returns void language plpgsql as $$
begin
  if condition is distinct from true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.fixture_results values (label, true);
end;
$$;
create function pg_temp.expect_error(statement text, expected_state text, label text)
returns void language plpgsql as $$
declare actual_state text;
begin
  begin
    execute statement;
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate;
    perform pg_temp.ok(actual_state = expected_state,
      label || ' [SQLSTATE ' || actual_state || ']');
    return;
  end;
  raise exception 'FAIL: expected % for %', expected_state, label;
end;
$$;

insert into auth.users values
 ('11111111-1111-4111-8111-111111111111', true),
 ('22222222-2222-4222-8222-222222222222', false),
 ('33333333-3333-4333-8333-333333333333', false);
-- Owner-only synthetic past/future dates for visibility and cursor fixtures;
-- live publication RPCs never permit client-supplied dates.
alter table public.editorial_inbox_messages disable trigger editorial_inbox_message_guard;
insert into public.editorial_inbox_messages (id, title, body, published_at) values
 ('10000000-0000-4000-8000-000000000001', '[LOCAL TEST FIXTURE] First', 'Plain body one', now() - interval '1 day'),
 ('10000000-0000-4000-8000-000000000002', '[LOCAL TEST FIXTURE] Second', 'Plain body two', now() - interval '1 day'),
 ('20000000-0000-4000-8000-000000000001', '[LOCAL TEST FIXTURE] Draft', 'Hidden draft', null),
 ('30000000-0000-4000-8000-000000000001', '[LOCAL TEST FIXTURE] Future', 'Hidden future', now() + interval '1 day');
insert into public.editorial_inbox_messages (id, title, body, published_at)
select md5('LOCAL CONTRACT TEST FIXTURE ' || n)::uuid,
       '[LOCAL TEST FIXTURE] Page ' || n, 'Local synthetic body',
       now() - interval '2 days' - (n / 3) * interval '1 hour'
from generate_series(1,205) n;
alter table public.editorial_inbox_messages enable trigger editorial_inbox_message_guard;
insert into public.editorial_inbox_reads values
 ('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000001', now() - interval '6 hours'),
 ('11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000002', now() - interval '12 hours');

select pg_temp.ok((select count(*) = 2 from pg_policy where polrelid in
 ('public.editorial_inbox_messages'::regclass, 'public.editorial_inbox_reads'::regclass)), 'Only SELECT policies exist');
select pg_temp.ok((select bool_and(relrowsecurity) from pg_class where oid in
 ('public.editorial_inbox_messages'::regclass, 'public.editorial_inbox_reads'::regclass)), 'Both tables enable RLS');
select pg_temp.ok((select bool_and(proconfig @> array['search_path=""']) from pg_proc where oid in
 ('public.list_editorial_inbox(timestamptz,uuid,integer)'::regprocedure,
  'public.mark_editorial_inbox_read(uuid)'::regprocedure,
  'public.save_editorial_inbox_draft(uuid,text,text)'::regprocedure,
  'public.publish_editorial_inbox(uuid,text,text)'::regprocedure)), 'All exposed RPCs have an empty search path');
select pg_temp.ok(not has_function_privilege('anon','public.mark_editorial_inbox_read(uuid)','EXECUTE')
 and not has_function_privilege('anon','public.list_editorial_inbox(timestamptz,uuid,integer)','EXECUTE'), 'Anon has no session RPC execution');
select pg_temp.ok(not has_function_privilege('authenticated','public.save_editorial_inbox_draft(uuid,text,text)','EXECUTE')
 and not has_function_privilege('authenticated','public.publish_editorial_inbox(uuid,text,text)','EXECUTE'), 'Authenticated has no administrative RPC execution');

set role anon;
select set_config('request.jwt.claim.sub', '', false);
select pg_temp.ok((select count(*) = 207 from public.editorial_inbox_messages), 'Anon can read all published messages, not draft/future');
select pg_temp.expect_error('select * from public.editorial_inbox_reads', '42501', 'Anon cannot read read markers');
select pg_temp.expect_error('select * from public.list_editorial_inbox()', '42501', 'Anon cannot list session Inbox');
select pg_temp.expect_error($q$select public.mark_editorial_inbox_read('10000000-0000-4000-8000-000000000001')$q$, '42501', 'Anon cannot mark');
select pg_temp.expect_error($q$insert into public.editorial_inbox_messages(id,title,body) values ('40000000-0000-4000-8000-000000000001','Attack','Attack')$q$, '42501', 'Anon cannot write content');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000001','Attack','Attack')$q$, '42501', 'Anon cannot call draft administration');
reset role;

-- This UUID represents a guest created by signInAnonymously: authenticated,
-- NOT the anon database role, exactly like the registered user's role below.
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select pg_temp.ok((select count(*) = 207 from public.editorial_inbox_messages), 'Anonymous-auth guest sees all published content');
select pg_temp.ok((select count(*) = 1 from public.editorial_inbox_reads), 'Guest sees own read markers only');
select pg_temp.ok((select count(*) = 100 from public.list_editorial_inbox()), 'Default first page is 100');
select pg_temp.ok((select count(*) = 100 from public.list_editorial_inbox(p_limit => 1000000)), 'Oversize pages clamp to 100');
select pg_temp.ok((select count(*) = 1 from public.list_editorial_inbox(p_limit => 1)), 'Small positive page size honored');
select pg_temp.ok((select read_at is null from public.list_editorial_inbox() where id = '10000000-0000-4000-8000-000000000001'), 'Other-user read never joins');
select pg_temp.ok((select read_at is not null from public.list_editorial_inbox() where id = '10000000-0000-4000-8000-000000000002'), 'Own read joins');
select pg_temp.expect_error('select * from public.list_editorial_inbox(p_limit => 0)', '22023', 'Zero page rejected');
select pg_temp.expect_error('select * from public.list_editorial_inbox(p_limit => -1)', '22023', 'Negative page rejected');
select pg_temp.expect_error('select * from public.list_editorial_inbox(p_limit => null)', '22023', 'Null page rejected');
select pg_temp.expect_error($q$select * from public.list_editorial_inbox(p_before_id => '10000000-0000-4000-8000-000000000001')$q$, '22023', 'Partial ID cursor rejected');
select pg_temp.expect_error('select * from public.list_editorial_inbox(p_before_published_at => now())', '22023', 'Partial date cursor rejected');

do $$
declare
  row record;
  cursor_time timestamptz := null;
  cursor_id uuid := null;
  seen uuid[] := '{}';
  expected uuid[];
  page_count integer;
  pages integer := 0;
begin
  select array_agg(id order by published_at desc,id desc) into expected
    from public.editorial_inbox_messages;
  loop
    page_count := 0;
    for row in select * from public.list_editorial_inbox(cursor_time,cursor_id,100) loop
      seen := array_append(seen,row.id);
      cursor_time := row.published_at;
      cursor_id := row.id;
      page_count := page_count + 1;
    end loop;
    pages := pages + 1;
    exit when page_count < 100;
  end loop;
  perform pg_temp.ok(seen = expected and cardinality(seen) = 207 and pages = 3,
    'All 207 messages over three pages: exact order, timestamp ties, no duplication/omission');
end;
$$;

select pg_temp.ok(public.mark_editorial_inbox_read('10000000-0000-4000-8000-000000000002') =
 (select read_at from public.editorial_inbox_reads where message_id = '10000000-0000-4000-8000-000000000002')
 and (select read_at < now() - interval '11 hours' from public.editorial_inbox_reads where message_id = '10000000-0000-4000-8000-000000000002'), 'Repeat mark returns original old timestamp, never updates it');
select pg_temp.ok(public.mark_editorial_inbox_read('10000000-0000-4000-8000-000000000001') is not null, 'Guest can mark exact published item');
select pg_temp.ok((select count(*) = 2 from public.editorial_inbox_reads), 'Mark creates only the requested own marker');
select pg_temp.expect_error($q$select public.mark_editorial_inbox_read('20000000-0000-4000-8000-000000000001')$q$, 'P0002', 'Cannot mark draft');
select pg_temp.expect_error($q$select public.mark_editorial_inbox_read('30000000-0000-4000-8000-000000000001')$q$, 'P0002', 'Cannot mark future message');
select pg_temp.expect_error($q$select public.mark_editorial_inbox_read('90000000-0000-4000-8000-000000000001')$q$, 'P0002', 'Cannot mark nonexistent message');
select pg_temp.expect_error('select public.mark_editorial_inbox_read(null)', 'P0002', 'Cannot mark null message');
select pg_temp.expect_error($q$select public.mark_editorial_inbox_read(p_message_id => '10000000-0000-4000-8000-000000000001', p_user_id => '22222222-2222-4222-8222-222222222222')$q$, '42883', 'No arbitrary user parameter/cross-user mark entry point');
select pg_temp.expect_error($q$insert into public.editorial_inbox_reads values ('22222222-2222-4222-8222-222222222222','10000000-0000-4000-8000-000000000002',now())$q$, '42501', 'Raw cross-user read insert blocked');
select pg_temp.expect_error($q$insert into public.editorial_inbox_reads values ('11111111-1111-4111-8111-111111111111','20000000-0000-4000-8000-000000000001',now())$q$, '42501', 'Raw own read insert blocked too');
select pg_temp.expect_error('update public.editorial_inbox_reads set read_at = now()', '42501', 'Raw marker update blocked');
select pg_temp.expect_error('delete from public.editorial_inbox_reads', '42501', 'Raw marker delete blocked');
select pg_temp.expect_error($q$insert into public.editorial_inbox_messages(id,title,body) values ('40000000-0000-4000-8000-000000000009','Attack','Attack')$q$, '42501', 'Authenticated raw content inserts blocked');
select pg_temp.expect_error($q$update public.editorial_inbox_messages set title = 'Attack'$q$, '42501', 'Client content updates blocked');
select pg_temp.expect_error('delete from public.editorial_inbox_messages', '42501', 'Client content deletes blocked');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000001','Attack','Attack')$q$, '42501', 'Authenticated draft administration blocked');
select pg_temp.expect_error($q$select public.publish_editorial_inbox('20000000-0000-4000-8000-000000000001','Attack','Attack')$q$, '42501', 'Authenticated publication blocked');

select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);
select pg_temp.ok((select count(*) = 1 from public.editorial_inbox_reads), 'Registered user cannot see guest markers');
select pg_temp.ok((select read_at is null from public.list_editorial_inbox() where id = '10000000-0000-4000-8000-000000000002'), 'Registered listing ignores guest read');
select set_config('request.jwt.claim.sub', '', false);
select pg_temp.expect_error('select * from public.list_editorial_inbox()', '28000', 'Authenticated role with missing UUID cannot list');
select pg_temp.expect_error($q$select public.mark_editorial_inbox_read('10000000-0000-4000-8000-000000000001')$q$, '28000', 'Authenticated role with missing UUID cannot mark');
select pg_temp.ok((select count(*) = 0 from public.editorial_inbox_reads), 'Missing UUID sees zero markers');
reset role;

-- Defense in depth: even an accidental future write grant cannot open RLS.
grant insert, update, delete on public.editorial_inbox_reads to authenticated;
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select pg_temp.expect_error($q$insert into public.editorial_inbox_reads values ('11111111-1111-4111-8111-111111111111','20000000-0000-4000-8000-000000000001',now())$q$, '42501', 'RLS itself rejects even own raw insert');
update public.editorial_inbox_reads set read_at = now();
delete from public.editorial_inbox_reads;
select pg_temp.ok((select count(*) = 2 from public.editorial_inbox_reads), 'RLS itself prevents marker deletion');
select pg_temp.ok((select read_at < now() - interval '11 hours' from public.editorial_inbox_reads where message_id = '10000000-0000-4000-8000-000000000002'), 'RLS itself prevents marker update');
reset role;
revoke insert, update, delete on public.editorial_inbox_reads from authenticated;

set role service_role;
select set_config('request.jwt.claim.sub', '', false);
select pg_temp.ok((select count(*) = 209 from public.editorial_inbox_messages), 'Service role can inspect drafts/future fixtures');
select pg_temp.expect_error($q$insert into public.editorial_inbox_messages values ('40000000-0000-4000-8000-000000000001','Bypass','Bypass',now(),now())$q$, '42501', 'Service has no raw content write grant');
select pg_temp.ok((public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000001','[LOCAL TEST FIXTURE] Draft','Fixture body')).published_at is null, 'Service creates unpublished draft');
select pg_temp.ok((public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000001','[LOCAL TEST FIXTURE] Revised','Revised fixture body')).title = '[LOCAL TEST FIXTURE] Revised', 'Service saves draft using same explicit UUID');
select pg_temp.ok((select count(*) = 1 from public.editorial_inbox_messages where id = '40000000-0000-4000-8000-000000000001'), 'Save retry does not duplicate');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000002',' ','Fixture body')$q$, '23514', 'Blank title rejected by database');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000002',repeat('x',201),'Fixture body')$q$, '23514', 'Oversize title rejected by database');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000002',E'Line\nbreak','Fixture body')$q$, '23514', 'Multiline title rejected by database');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000002','Fixture title',E' \n\t')$q$, '23514', 'Blank body rejected by database');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000002','Fixture title',repeat('x',20001))$q$, '23514', 'Oversize body rejected by database');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft(null,'Fixture title','Fixture body')$q$, '23502', 'Null explicit UUID rejected');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000002',null,'Fixture body')$q$, '23502', 'Null title rejected by database');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000002','Fixture title',null)$q$, '23502', 'Null body rejected by database');
select pg_temp.ok(char_length((public.save_editorial_inbox_draft('70000000-0000-4000-8000-000000000001',repeat('界',200),repeat('界',20000))).body) = 20000, 'Unicode character-count maximum bounds accepted');
select pg_temp.expect_error($q$select public.publish_editorial_inbox(p_id => '40000000-0000-4000-8000-000000000001', p_expected_title => '[LOCAL TEST FIXTURE] Revised', p_expected_body => 'Revised fixture body', p_published_at => now() + interval '1 year')$q$, '42883', 'No client publication-date parameter exists');
select pg_temp.expect_error($q$select public.publish_editorial_inbox('90000000-0000-4000-8000-000000000001','Missing','Missing')$q$, 'P0002', 'Publishing missing UUID does not create content');
select pg_temp.expect_error($q$select public.publish_editorial_inbox('40000000-0000-4000-8000-000000000001','Old preview','Revised fixture body')$q$, '55000', 'Stale approved snapshot cannot publish');
select pg_temp.ok((select published_at is null from public.editorial_inbox_messages where id = '40000000-0000-4000-8000-000000000001'), 'Stale publication leaves draft hidden');
select pg_temp.ok((public.publish_editorial_inbox('40000000-0000-4000-8000-000000000001','[LOCAL TEST FIXTURE] Revised','Revised fixture body')).published_at is not null, 'Explicit service publication succeeds');
select pg_temp.ok((select published_at <= now() and published_at > now() - interval '1 minute' from public.editorial_inbox_messages where id = '40000000-0000-4000-8000-000000000001'), 'Publication date is server current time');
select pg_temp.ok((public.publish_editorial_inbox('40000000-0000-4000-8000-000000000001','[LOCAL TEST FIXTURE] Revised','Revised fixture body')).published_at =
 (select published_at from public.editorial_inbox_messages where id = '40000000-0000-4000-8000-000000000001'), 'Publication retry preserves original timestamp');
select pg_temp.expect_error($q$select public.save_editorial_inbox_draft('40000000-0000-4000-8000-000000000001','Edited published','Edited published')$q$, '55000', 'Service cannot edit published content through save');
select pg_temp.expect_error($q$select public.publish_editorial_inbox('40000000-0000-4000-8000-000000000001','Edited published','Edited published')$q$, '55000', 'Publication retry cannot change content');
reset role;

-- Guard remains effective for accidental owner writes, too.
select pg_temp.expect_error($q$update public.editorial_inbox_messages set body = 'Edited' where id = '40000000-0000-4000-8000-000000000001'$q$, '55000', 'Trigger prevents privileged published edit');
select pg_temp.expect_error($q$update public.editorial_inbox_messages set published_at = null where id = '40000000-0000-4000-8000-000000000001'$q$, '55000', 'Trigger prevents unpublishing');
select pg_temp.expect_error($q$update public.editorial_inbox_messages set id = '40000000-0000-4000-8000-000000000003' where id = '20000000-0000-4000-8000-000000000001'$q$, '55000', 'Trigger prevents draft UUID replacement');
select pg_temp.expect_error($q$update public.editorial_inbox_messages set created_at = now() where id = '20000000-0000-4000-8000-000000000001'$q$, '55000', 'Trigger prevents draft creation-time replacement');

set role anon;
select pg_temp.ok((select count(*) = 208 from public.editorial_inbox_messages), 'New publication is visible to unauthed reader, remaining drafts/future hidden');
reset role;

-- Privileged maintenance only: there is no delete client/admin RPC. Both FKs
-- must still clean up orphan read markers during authorized future erasure.
delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select pg_temp.ok(not exists(select 1 from public.editorial_inbox_reads where user_id = '11111111-1111-4111-8111-111111111111'), 'Auth-user deletion cascades all own markers');
select pg_temp.ok((select count(*) = 1 from public.editorial_inbox_reads), 'Auth-user deletion preserves other user marker');
delete from public.editorial_inbox_messages where id = '10000000-0000-4000-8000-000000000001';
select pg_temp.ok(not exists(select 1 from public.editorial_inbox_reads where message_id = '10000000-0000-4000-8000-000000000001'), 'Privileged message deletion cascades marker FK');
select pg_temp.expect_error($q$insert into public.editorial_inbox_reads values ('22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001',now())$q$, '23503', 'Read marker cannot reference nonexistent message');
select pg_temp.expect_error($q$insert into public.editorial_inbox_reads values ('99999999-9999-4999-8999-999999999999','10000000-0000-4000-8000-000000000002',now())$q$, '23503', 'Read marker cannot reference nonexistent user');

select count(*) as local_contract_checks_passed, bool_and(passed) as all_passed from fixture_results;
\echo 'LOCAL CONTRACT FIXTURE ONLY: no hosted Supabase/PostgREST/JWT parity claimed.'
