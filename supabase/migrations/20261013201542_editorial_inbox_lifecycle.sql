-- Individually retract, edit, remove and republish editorial Inbox messages.
-- Existing readers keep their list contracts. Receipts apply only to the
-- publication they were recorded against, including legacy app builds.
begin;
set local lock_timeout = '5s';
alter table public.editorial_inbox_messages
  add column revision bigint not null default 0,
  add column publication_count integer not null default 0,
  add column updated_at timestamptz not null default now();
alter table public.editorial_inbox_messages disable trigger editorial_inbox_message_guard;
update public.editorial_inbox_messages set publication_count = 1 where published_at is not null;
alter table public.editorial_inbox_messages enable trigger editorial_inbox_message_guard;

create or replace function public.guard_editorial_inbox_message()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id or new.created_at is distinct from old.created_at then
      raise exception 'Editorial message identity is immutable' using errcode = '55000';
    end if;
    if old.published_at is not null and
      row(new.title,new.body,new.body_format,new.image_url,new.action_label,new.action_url)
      is distinct from row(old.title,old.body,old.body_format,old.image_url,old.action_label,old.action_url) then
      raise exception 'Take back the message before editing' using errcode = '55000';
    end if;
    new.revision := old.revision + 1;
    new.publication_count := old.publication_count;
  else
    new.revision := 0;
    new.publication_count := 0;
  end if;
  if new.published_at is not null and
    (tg_op = 'INSERT' or new.published_at is distinct from old.published_at) then
    new.published_at := clock_timestamp();
    if tg_op = 'UPDATE' and old.published_at is not null then
      new.published_at := greatest(new.published_at, old.published_at + interval '1 microsecond');
    end if;
    new.publication_count := new.publication_count + 1;
  end if;
  new.updated_at := clock_timestamp();
  return new;
end; $$;
comment on column public.editorial_inbox_messages.published_at is
  'NULL hides a draft/retracted message. A new publication timestamp invalidates prior read receipts.';

create schema if not exists editorial_private;
revoke all on schema editorial_private from public, anon;
grant usage on schema editorial_private to service_role, authenticated;

create function editorial_private.save_draft(
  p_id uuid, p_expected_revision bigint, p_title text, p_body text,
  p_body_format text, p_image_url text, p_action_label text, p_action_url text
) returns public.editorial_inbox_messages
language plpgsql security definer set search_path = '' as $$
declare m public.editorial_inbox_messages;
begin
  select * into m from public.editorial_inbox_messages where id=p_id for update;
  if found then
    if m.revision is distinct from p_expected_revision or m.published_at is not null then
      raise exception 'Message changed; reload or take it back before editing' using errcode='55000';
    end if;
    update public.editorial_inbox_messages set title=p_title,body=p_body,
      body_format=p_body_format,image_url=p_image_url,action_label=p_action_label,action_url=p_action_url
      where id=p_id returning * into m;
  else
    if p_expected_revision is not null then
      raise exception 'Message was removed' using errcode='P0002';
    end if;
    insert into public.editorial_inbox_messages(id,title,body,body_format,image_url,action_label,action_url)
      values(p_id,p_title,p_body,p_body_format,p_image_url,p_action_label,p_action_url)
      on conflict(id) do nothing returning * into m;
    if not found then raise exception 'Message changed; reload' using errcode='55000'; end if;
  end if;
  return m;
end; $$;

create function editorial_private.publish_message(
  p_id uuid,p_expected_revision bigint,p_expected_title text,p_expected_body text,
  p_expected_body_format text,p_expected_image_url text,p_expected_action_label text,p_expected_action_url text,
  p_republish boolean default false
) returns public.editorial_inbox_messages
language plpgsql security definer set search_path = '' as $$
declare m public.editorial_inbox_messages;
begin
  select * into m from public.editorial_inbox_messages where id=p_id for update;
  if not found then raise exception 'Message was removed' using errcode='P0002'; end if;
  if row(m.title,m.body,m.body_format,m.image_url,m.action_label,m.action_url)
    is distinct from row(p_expected_title,p_expected_body,p_expected_body_format,p_expected_image_url,p_expected_action_label,p_expected_action_url) then
    raise exception 'Message changed; preview again' using errcode='55000';
  end if;
  -- An acknowledgement lost after publication can be retried without a new
  -- unread generation or duplicate push. A later edit/retraction fails this CAS.
  if m.published_at is not null and m.revision = p_expected_revision + 1 then return m; end if;
  if m.revision is distinct from p_expected_revision then
    raise exception 'Message changed; reload' using errcode='55000';
  end if;
  if m.published_at is null or p_republish then
    update public.editorial_inbox_messages set published_at=clock_timestamp()
      where id=p_id returning * into m;
  end if;
  return m;
end; $$;

create function editorial_private.retract_message(p_id uuid,p_expected_revision bigint)
returns public.editorial_inbox_messages
language plpgsql security definer set search_path = '' as $$
declare m public.editorial_inbox_messages;
begin
  select * into m from public.editorial_inbox_messages where id=p_id for update;
  if not found then raise exception 'Message was removed' using errcode='P0002'; end if;
  if m.revision is distinct from p_expected_revision then
    if m.published_at is null and m.revision=p_expected_revision+1 then return m; end if;
    raise exception 'Message changed; reload' using errcode='55000';
  end if;
  if m.published_at is not null then
    update public.editorial_inbox_messages set published_at=null where id=p_id returning * into m;
  end if;
  update public.notification_outbox set status='skipped',last_error='inbox_retracted'
    where status='pending' and event_type='call_to_action' and payload#>>'{data,inbox_message_id}'=p_id::text;
  return m;
end; $$;

create function editorial_private.remove_message(p_id uuid,p_expected_revision bigint)
returns boolean language plpgsql security definer set search_path = '' as $$
declare m public.editorial_inbox_messages;
begin
  select * into m from public.editorial_inbox_messages where id=p_id for update;
  if not found then return true; end if;
  if m.revision is distinct from p_expected_revision then raise exception 'Message changed; reload' using errcode='55000'; end if;
  delete from public.editorial_inbox_messages where id=p_id;
  update public.notification_outbox set status='skipped',last_error='inbox_removed'
    where status='pending' and event_type='call_to_action' and payload#>>'{data,inbox_message_id}'=p_id::text;
  return true;
end; $$;

create function editorial_private.mark_read(p_message_id uuid,p_expected_published_at timestamptz)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare owner uuid:=auth.uid(); publication timestamptz; result timestamptz;
begin
  if owner is null then raise exception 'Sign in required' using errcode='28000'; end if;
  select published_at into publication from public.editorial_inbox_messages
    where id=p_message_id and published_at is not null and published_at<=now() for share;
  if not found then raise exception 'Message unavailable' using errcode='P0002'; end if;
  if publication is distinct from p_expected_published_at then raise exception 'Message republished; read the new version' using errcode='55000'; end if;
  insert into public.editorial_inbox_reads(user_id,message_id,read_at)
    values(owner,p_message_id,clock_timestamp()) on conflict(user_id,message_id) do update
    set read_at=excluded.read_at where editorial_inbox_reads.read_at<publication;
  select read_at into result from public.editorial_inbox_reads where user_id=owner and message_id=p_message_id;
  return result;
end; $$;

revoke all on function editorial_private.save_draft(uuid,bigint,text,text,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function editorial_private.save_draft(uuid,bigint,text,text,text,text,text,text) to service_role;
create function public.save_editorial_inbox_draft_v3(p_id uuid,p_expected_revision bigint,p_title text,p_body text,p_body_format text,p_image_url text,p_action_label text,p_action_url text) returns public.editorial_inbox_messages
language sql security invoker set search_path='' as $$ select editorial_private.save_draft(p_id,p_expected_revision,p_title,p_body,p_body_format,p_image_url,p_action_label,p_action_url); $$;
revoke all on function public.save_editorial_inbox_draft_v3(uuid,bigint,text,text,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.save_editorial_inbox_draft_v3(uuid,bigint,text,text,text,text,text,text) to service_role;

revoke all on function editorial_private.publish_message(uuid,bigint,text,text,text,text,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function editorial_private.publish_message(uuid,bigint,text,text,text,text,text,text,boolean) to service_role;
create function public.publish_editorial_inbox_v3(p_id uuid,p_expected_revision bigint,p_expected_title text,p_expected_body text,p_expected_body_format text,p_expected_image_url text,p_expected_action_label text,p_expected_action_url text,p_republish boolean default false) returns public.editorial_inbox_messages
language sql security invoker set search_path='' as $$ select editorial_private.publish_message(p_id,p_expected_revision,p_expected_title,p_expected_body,p_expected_body_format,p_expected_image_url,p_expected_action_label,p_expected_action_url,p_republish); $$;
revoke all on function public.publish_editorial_inbox_v3(uuid,bigint,text,text,text,text,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.publish_editorial_inbox_v3(uuid,bigint,text,text,text,text,text,text,boolean) to service_role;

revoke all on function editorial_private.retract_message(uuid,bigint) from public,anon,authenticated,service_role;
grant execute on function editorial_private.retract_message(uuid,bigint) to service_role;
create function public.retract_editorial_inbox(p_id uuid,p_expected_revision bigint) returns public.editorial_inbox_messages
language sql security invoker set search_path='' as $$ select editorial_private.retract_message(p_id,p_expected_revision); $$;
revoke all on function public.retract_editorial_inbox(uuid,bigint) from public,anon,authenticated,service_role;
grant execute on function public.retract_editorial_inbox(uuid,bigint) to service_role;

revoke all on function editorial_private.remove_message(uuid,bigint) from public,anon,authenticated,service_role;
grant execute on function editorial_private.remove_message(uuid,bigint) to service_role;
create function public.remove_editorial_inbox(p_id uuid,p_expected_revision bigint) returns boolean
language sql security invoker set search_path='' as $$ select editorial_private.remove_message(p_id,p_expected_revision); $$;
revoke all on function public.remove_editorial_inbox(uuid,bigint) from public,anon,authenticated,service_role;
grant execute on function public.remove_editorial_inbox(uuid,bigint) to service_role;

revoke all on function editorial_private.mark_read(uuid,timestamptz) from public,anon,authenticated,service_role;
grant execute on function editorial_private.mark_read(uuid,timestamptz) to authenticated;
create function public.mark_editorial_inbox_read_v2(p_message_id uuid,p_expected_published_at timestamptz) returns timestamptz
language sql security invoker set search_path='' as $$ select editorial_private.mark_read(p_message_id,p_expected_published_at); $$;
revoke all on function public.mark_editorial_inbox_read_v2(uuid,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.mark_editorial_inbox_read_v2(uuid,timestamptz) to authenticated;

create or replace function public.list_editorial_inbox(
  p_before_published_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 100
)
returns table (id uuid, title text, body text, published_at timestamptz, read_at timestamptz)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'An authenticated session is required' using errcode = '28000';
  end if;
  if (p_before_published_at is null) <> (p_before_id is null) then
    raise exception 'Both cursor fields must be provided together' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 then
    raise exception 'Page size must be positive' using errcode = '22023';
  end if;
  return query
    select m.id, m.title, m.body, m.published_at, case when r.read_at >= m.published_at then r.read_at end
    from public.editorial_inbox_messages m
    left join public.editorial_inbox_reads r
      on r.message_id = m.id and r.user_id = v_user_id
    where m.published_at is not null and m.published_at <= now()
      and (p_before_id is null or (m.published_at, m.id) < (p_before_published_at, p_before_id))
    order by m.published_at desc, m.id desc
    limit least(p_limit, 100);
end;
$$;

create or replace function public.list_editorial_inbox_v2(
  p_before_published_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 100
)
returns table (
  id uuid,
  title text,
  body text,
  body_format text,
  image_url text,
  action_label text,
  action_url text,
  published_at timestamptz,
  read_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'An authenticated session is required' using errcode = '28000';
  end if;
  if (p_before_published_at is null) <> (p_before_id is null) then
    raise exception 'Both cursor fields must be provided together' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 then
    raise exception 'Page size must be positive' using errcode = '22023';
  end if;
  return query
    select m.id, m.title, m.body, m.body_format, m.image_url, m.action_label, m.action_url,
      m.published_at, case when r.read_at >= m.published_at then r.read_at end
    from public.editorial_inbox_messages m
    left join public.editorial_inbox_reads r
      on r.message_id = m.id and r.user_id = v_user_id
    where m.published_at is not null and m.published_at <= now()
      and (p_before_id is null or (m.published_at, m.id) < (p_before_published_at, p_before_id))
    order by m.published_at desc, m.id desc
    limit least(p_limit, 100);
end;
$$;

create or replace function public.mark_editorial_inbox_read(p_message_id uuid)
returns timestamptz language plpgsql security definer set search_path='' as $$
declare publication timestamptz;
begin
  select published_at into publication from public.editorial_inbox_messages
    where id=p_message_id and published_at is not null and published_at<=now() for share;
  if not found then raise exception 'Message unavailable' using errcode='P0002'; end if;
  return editorial_private.mark_read(p_message_id,publication);
end; $$;
notify pgrst, 'reload schema';
commit;
