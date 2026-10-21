-- LOCAL CONTRACT TEST FIXTURE ONLY: disposable PostgreSQL, NOT a Supabase
-- integration/parity test. Applies the original Inbox migration, publishes a
-- message through it, then applies the rich migration on top, as production
-- will, and checks old rows, old RPCs and the new ones together.
-- Run with: scripts/inbox/run_sql_tests.py --sql supabase/tests/editorial_inbox_rich.sql
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
-- Just the columns the migration writes; not Supabase Storage.
create schema storage;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
grant usage on schema public, auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

\ir ../migrations/20261010120000_editorial_inbox.sql

insert into auth.users (id) values ('22222222-2222-4222-8222-222222222222');
set role service_role;
select public.save_editorial_inbox_draft(
  '10000000-0000-4000-8000-000000000001', '[LOCAL TEST FIXTURE] Before rich', 'Plain **as typed**');
select public.publish_editorial_inbox(
  '10000000-0000-4000-8000-000000000001', '[LOCAL TEST FIXTURE] Before rich', 'Plain **as typed**');
reset role;

\ir ../migrations/20261012200000_editorial_inbox_rich.sql

create function pg_temp.ok(condition boolean, label text) returns void language plpgsql as $$
begin
  if condition is distinct from true then raise exception 'FAIL: %', label; end if;
  raise notice 'ok: %', label;
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
    if actual_state = expected_state then
      raise notice 'ok: %', label;
      return;
    end if;
    raise exception 'FAIL: % (got %, wanted %)', label, actual_state, expected_state;
  end;
  raise exception 'FAIL: % (no error)', label;
end;
$$;

select pg_temp.ok(
  (select body_format = 'plain' and image_url is null and action_label is null
       and action_url is null and published_at is not null
     from public.editorial_inbox_messages where id = '10000000-0000-4000-8000-000000000001'),
  'a message published before the migration stays plain, imageless and published');
select pg_temp.ok(
  (select public and file_size_limit = 5242880 from storage.buckets where id = 'editorial-inbox'),
  'the public image bucket exists with its size limit');

set role service_role;
select pg_temp.ok(
  (select (public.save_editorial_inbox_draft_v2(
     '10000000-0000-4000-8000-000000000002', '[LOCAL TEST FIXTURE] Rich', '## Heading',
     'markdown', 'https://fixture.invalid/storage/v1/object/public/editorial-inbox/a.webp',
     'Tap to see', 'https://chessever.com/feed')).action_label) = 'Tap to see',
  'v2 saves a Markdown draft with an image and a button');
select pg_temp.expect_error(
  $$select public.save_editorial_inbox_draft_v2('10000000-0000-4000-8000-000000000003','[LOCAL TEST FIXTURE] x','y','plain',null,'Tap to see',null)$$,
  '23514', 'a button label without a link is refused');
select pg_temp.expect_error(
  $$select public.save_editorial_inbox_draft_v2('10000000-0000-4000-8000-000000000003','[LOCAL TEST FIXTURE] x','y','plain',null,null,'https://chessever.com/feed')$$,
  '23514', 'a button link without a label is refused');
select pg_temp.expect_error(
  $$select public.save_editorial_inbox_draft_v2('10000000-0000-4000-8000-000000000003','[LOCAL TEST FIXTURE] x','y','plain',null,'Tap to see','chessever://feed')$$,
  '23514', 'a button link that is not https is refused');
select pg_temp.expect_error(
  $$select public.save_editorial_inbox_draft_v2('10000000-0000-4000-8000-000000000003','[LOCAL TEST FIXTURE] x','y','plain',null,repeat('a',41),'https://chessever.com/feed')$$,
  '23514', 'a button label over 40 characters is refused');
select pg_temp.expect_error(
  $$select public.save_editorial_inbox_draft_v2('10000000-0000-4000-8000-000000000003','[LOCAL TEST FIXTURE] x','y','html',null,null,null)$$,
  '23514', 'an unknown body format is refused');
select pg_temp.expect_error(
  $$select public.save_editorial_inbox_draft_v2('10000000-0000-4000-8000-000000000003','[LOCAL TEST FIXTURE] x','y','plain','http://fixture.invalid/a.png',null,null)$$,
  '23514', 'a non-https image is refused');
select pg_temp.expect_error(
  $$select public.save_editorial_inbox_draft_v2('10000000-0000-4000-8000-000000000001','[LOCAL TEST FIXTURE] x','y','markdown',null,null,null)$$,
  '55000', 'v2 cannot rewrite a published message');
select pg_temp.expect_error(
  $$select public.publish_editorial_inbox_v2('10000000-0000-4000-8000-000000000002','[LOCAL TEST FIXTURE] Rich','## Heading','markdown',null,'Tap to see','https://chessever.com/feed')$$,
  '55000', 'publishing refuses an image that differs from the approved one');
select pg_temp.expect_error(
  $$select public.publish_editorial_inbox_v2('10000000-0000-4000-8000-000000000002','[LOCAL TEST FIXTURE] Rich','## Heading','plain','https://fixture.invalid/storage/v1/object/public/editorial-inbox/a.webp','Tap to see','https://chessever.com/feed')$$,
  '55000', 'publishing refuses a format that differs from the approved one');
select pg_temp.expect_error(
  $$select public.publish_editorial_inbox_v2('10000000-0000-4000-8000-000000000002','[LOCAL TEST FIXTURE] Rich','## Heading','markdown','https://fixture.invalid/storage/v1/object/public/editorial-inbox/a.webp','Tap to see','https://chessever.com/other')$$,
  '55000', 'publishing refuses a button link that differs from the approved one');
select pg_temp.ok(
  (select (public.publish_editorial_inbox_v2(
     '10000000-0000-4000-8000-000000000002', '[LOCAL TEST FIXTURE] Rich', '## Heading',
     'markdown', 'https://fixture.invalid/storage/v1/object/public/editorial-inbox/a.webp',
     'Tap to see', 'https://chessever.com/feed')).published_at) is not null,
  'v2 publishes the approved snapshot');
-- The original draft RPC still works and writes a plain, imageless draft.
select pg_temp.ok(
  (select (public.save_editorial_inbox_draft(
     '10000000-0000-4000-8000-000000000004', '[LOCAL TEST FIXTURE] Old tool', 'text')).body_format) = 'plain',
  'the original save RPC still writes plain drafts');
reset role;

set role authenticated;
set request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
select pg_temp.ok(
  (select count(*) = 2 and bool_and(read_at is null) from public.list_editorial_inbox_v2()),
  'v2 lists both published messages, drafts hidden');
select pg_temp.ok(
  (select body_format = 'markdown' and image_url like 'https://%'
       and action_label = 'Tap to see' and action_url = 'https://chessever.com/feed'
     from public.list_editorial_inbox_v2() where id = '10000000-0000-4000-8000-000000000002'),
  'v2 carries the format, image and button');
select pg_temp.ok(
  (select count(*) = 2 from public.list_editorial_inbox()),
  'the original listing still answers with every message');
select public.mark_editorial_inbox_read('10000000-0000-4000-8000-000000000002');
select pg_temp.ok(
  (select read_at is not null from public.list_editorial_inbox_v2() where id = '10000000-0000-4000-8000-000000000002'),
  'a read shows in the v2 listing');
select pg_temp.expect_error(
  $$select public.save_editorial_inbox_draft_v2('10000000-0000-4000-8000-000000000009','[LOCAL TEST FIXTURE] x','y','plain',null,null,null)$$,
  '42501', 'a signed-in user cannot save drafts');
select pg_temp.expect_error(
  $$select public.publish_editorial_inbox_v2('10000000-0000-4000-8000-000000000004','[LOCAL TEST FIXTURE] Old tool','text','plain',null,null,null)$$,
  '42501', 'a signed-in user cannot publish');
reset role;
set role anon;
select pg_temp.expect_error(
  $$select * from public.list_editorial_inbox_v2()$$,
  '42501', 'a caller with no session cannot use the v2 listing');
reset role;
\echo 'Rich Inbox contract checks passed.'
