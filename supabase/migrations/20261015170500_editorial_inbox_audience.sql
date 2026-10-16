-- Audiences for Inbox messages and Nudges, kept private. ADDITIVE ONLY.
--
-- This migration creates new objects and adds one nullable column. It drops,
-- replaces, updates and deletes nothing that already exists, and grants no new
-- schema access. Every existing message keeps audience_id null, which the new
-- checks treat exactly as today: visible to everyone, readable by everyone.
--
-- An audience is the admin portal's filters (Premium/free, platform, sign-in
-- method, guest/registered, country, followed player or event, chosen user
-- ids, a name search). It may name people, so it is stored only in
-- editorial_private.audiences, which no app role can read. Messages and Nudges
-- refer to an audience by a random id that says nothing about it: a hash of
-- the filters could be confirmed by hashing a guess ("is it this user?"). The
-- private filters_hash stores equal filters once, so a retried save reuses the
-- same id.
--
-- Who may read a message is narrowed by two RESTRICTIVE policies, added next
-- to the existing permissive one (which is left untouched). Both list RPCs run
-- as the reader, so every app version, and the unread badge built from the
-- list, follows the audience. A trigger keeps a live message's audience fixed,
-- and another refuses read receipts for messages outside the reader's
-- audience. Nudges live in Remote Config, which every install can read, so a
-- targeted Nudge there carries only its audience id; the phone asks
-- match_editorial_audiences which ids include the signed-in person.
--
-- Matching a person calls admin_portal.includes() from the admin portal
-- migration 20261015170000_shared_audiences.sql. Apply that one first.
begin;
set local lock_timeout = '5s';

create table editorial_private.audiences (
  id text primary key constraint editorial_audience_id check (id ~ '^[0-9a-f]{64}$'),
  filters jsonb not null constraint editorial_audience_filters
    check (jsonb_typeof(filters) = 'object' and filters <> '{}'::jsonb),
  filters_hash bytea not null unique,
  created_at timestamptz not null default now()
);
comment on table editorial_private.audiences is
  'Admin portal audience filters behind Inbox messages and Nudges. Private: filters can list user ids.';
alter table editorial_private.audiences enable row level security;
revoke all on table editorial_private.audiences from public, anon, authenticated, service_role;

-- Stores filters once and returns their id; null for everyone. User ids are
-- lower-cased, de-duplicated and sorted first, so their order never matters.
create function editorial_private.audience_id(p_filters jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare v_id text; v_hash bytea;
begin
  if p_filters is null or p_filters = '{}'::jsonb then return null; end if;
  if jsonb_typeof(p_filters) <> 'object' then
    raise exception 'An audience must be an object of filters' using errcode = '22023';
  end if;
  if p_filters ? 'userIds' then
    if jsonb_typeof(p_filters->'userIds') <> 'array' then
      raise exception 'userIds must be a list' using errcode = '22023';
    end if;
    p_filters := jsonb_set(p_filters, '{userIds}', (
      select coalesce(jsonb_agg(v order by v), '[]'::jsonb)
      from (select distinct lower(value) as v from jsonb_array_elements_text(p_filters->'userIds')) ids));
  end if;
  v_hash := sha256(convert_to(p_filters::text, 'UTF8'));
  select id into v_id from editorial_private.audiences where filters_hash = v_hash;
  if found then return v_id; end if;
  insert into editorial_private.audiences(id, filters, filters_hash)
    values (replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), p_filters, v_hash)
    on conflict (filters_hash) do nothing returning id into v_id;
  if v_id is null then
    select id into v_id from editorial_private.audiences where filters_hash = v_hash;
  end if;
  return v_id;
end; $$;
revoke all on function editorial_private.audience_id(jsonb) from public, anon, authenticated, service_role;

-- True when the signed-in reader is in the audience; true for everyone (null).
-- An unknown id includes nobody. Signed-out callers never reach it: their
-- policy below admits only messages for everyone.
create function editorial_private.viewer_in_audience(p_audience_id text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v_filters jsonb;
begin
  if p_audience_id is null then return true; end if;
  select filters into v_filters from editorial_private.audiences where id = p_audience_id;
  if not found then return false; end if;
  return coalesce(admin_portal.includes(auth.uid(), v_filters), false);
end; $$;
revoke all on function editorial_private.viewer_in_audience(text) from public, anon, authenticated, service_role;
grant execute on function editorial_private.viewer_in_audience(text) to authenticated, service_role;

-- For the admin portal (service role only): an id for filters, and filters for ids.
create function public.editorial_audience_id(p_filters jsonb) returns text
language sql security invoker set search_path = '' as $$ select editorial_private.audience_id(p_filters); $$;
revoke all on function public.editorial_audience_id(jsonb) from public, anon, authenticated, service_role;
grant execute on function editorial_private.audience_id(jsonb) to service_role;
grant execute on function public.editorial_audience_id(jsonb) to service_role;

create function public.editorial_audience_filters(p_ids text[]) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(a.id, a.filters), '{}'::jsonb)
  from editorial_private.audiences a where a.id = any(p_ids);
$$;
revoke all on function public.editorial_audience_filters(text[]) from public, anon, authenticated, service_role;
grant execute on function public.editorial_audience_filters(text[]) to service_role;

-- Nullable, no default: existing rows stay null (everyone) and the table is not rewritten.
alter table public.editorial_inbox_messages
  add column audience_id text references editorial_private.audiences(id);
comment on column public.editorial_inbox_messages.audience_id is
  'Who can read it: editorial_private.audiences id, null for everyone. Part of the content: take the message back, or revise it, to change it.';

-- Restrictive policies are ANDed with the existing permissive policy
-- editorial_inbox_visible_messages, which stays as it is.
create policy editorial_inbox_audience_signed_out
  on public.editorial_inbox_messages as restrictive for select to anon
  using (audience_id is null);
create policy editorial_inbox_audience_members
  on public.editorial_inbox_messages as restrictive for select to authenticated
  using (audience_id is null or editorial_private.viewer_in_audience(audience_id));

-- A live message's audience changes only by taking it back or revising it
-- (which unpublishes and republishes in one transaction).
create function editorial_private.guard_inbox_audience()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.published_at is not null and new.audience_id is distinct from old.audience_id then
    raise exception 'Take back the message before editing' using errcode = '55000';
  end if;
  return new;
end; $$;
revoke all on function editorial_private.guard_inbox_audience() from public, anon, authenticated, service_role;
create trigger editorial_inbox_audience_guard
  before update of audience_id on public.editorial_inbox_messages
  for each row execute function editorial_private.guard_inbox_audience();

-- Read receipts only for messages the signed-in reader is meant to see.
-- Writes without a session (service role, maintenance) are unaffected.
create function editorial_private.guard_inbox_read_audience()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_target text;
begin
  if auth.uid() is null then return new; end if;
  select audience_id into v_target from public.editorial_inbox_messages where id = new.message_id;
  if v_target is not null and not editorial_private.viewer_in_audience(v_target) then
    raise exception 'Message unavailable' using errcode = 'P0002';
  end if;
  return new;
end; $$;
revoke all on function editorial_private.guard_inbox_read_audience() from public, anon, authenticated, service_role;
create trigger editorial_inbox_read_audience_guard
  before insert or update on public.editorial_inbox_reads
  for each row execute function editorial_private.guard_inbox_read_audience();

create function editorial_private.save_draft_v4(
  p_id uuid, p_expected_revision bigint, p_title text, p_body text,
  p_body_format text, p_image_url text, p_action_label text, p_action_url text, p_audience jsonb
) returns public.editorial_inbox_messages
language plpgsql security definer set search_path = '' as $$
declare m public.editorial_inbox_messages; v_audience text := editorial_private.audience_id(p_audience);
begin
  select * into m from public.editorial_inbox_messages where id=p_id for update;
  if found then
    if m.revision is distinct from p_expected_revision or m.published_at is not null then
      raise exception 'Message changed; reload or take it back before editing' using errcode='55000';
    end if;
    update public.editorial_inbox_messages set title=p_title,body=p_body,body_format=p_body_format,
      image_url=p_image_url,action_label=p_action_label,action_url=p_action_url,audience_id=v_audience
      where id=p_id returning * into m;
  else
    if p_expected_revision is not null then
      raise exception 'Message was removed' using errcode='P0002';
    end if;
    insert into public.editorial_inbox_messages(id,title,body,body_format,image_url,action_label,action_url,audience_id)
      values(p_id,p_title,p_body,p_body_format,p_image_url,p_action_label,p_action_url,v_audience)
      on conflict(id) do nothing returning * into m;
    if not found then raise exception 'Message changed; reload' using errcode='55000'; end if;
  end if;
  return m;
end; $$;
revoke all on function editorial_private.save_draft_v4(uuid,bigint,text,text,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function editorial_private.save_draft_v4(uuid,bigint,text,text,text,text,text,text,jsonb) to service_role;
create function public.save_editorial_inbox_draft_v4(p_id uuid,p_expected_revision bigint,p_title text,p_body text,p_body_format text,p_image_url text,p_action_label text,p_action_url text,p_audience jsonb) returns public.editorial_inbox_messages
language sql security invoker set search_path='' as $$ select editorial_private.save_draft_v4(p_id,p_expected_revision,p_title,p_body,p_body_format,p_image_url,p_action_label,p_action_url,p_audience); $$;
revoke all on function public.save_editorial_inbox_draft_v4(uuid,bigint,text,text,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.save_editorial_inbox_draft_v4(uuid,bigint,text,text,text,text,text,text,jsonb) to service_role;

-- Publishes new content for a live message in one transaction: readers see
-- the old edition until the new one replaces it, unread, under a new reading
-- identity. An everyone-push still pending for the old edition is skipped.
create function editorial_private.revise_edition(
  p_id uuid, p_expected_revision bigint, p_title text, p_body text,
  p_body_format text, p_image_url text, p_action_label text, p_action_url text, p_audience jsonb
) returns public.editorial_inbox_messages
language plpgsql security definer set search_path = '' as $$
declare m public.editorial_inbox_messages; v_audience text := editorial_private.audience_id(p_audience);
begin
  select * into m from public.editorial_inbox_messages where id=p_id for update;
  if not found then raise exception 'Message was removed' using errcode='P0002'; end if;
  -- A lost acknowledgement retried: this call's two updates already landed.
  if m.published_at is not null and m.revision = p_expected_revision + 2 and
    row(m.title,m.body,m.body_format,m.image_url,m.action_label,m.action_url,m.audience_id)
    is not distinct from row(p_title,p_body,p_body_format,p_image_url,p_action_label,p_action_url,v_audience) then
    return m;
  end if;
  if m.revision is distinct from p_expected_revision or m.published_at is null then
    raise exception 'Message changed; reload' using errcode='55000';
  end if;
  update public.editorial_inbox_messages set published_at=null where id=p_id;
  update public.editorial_inbox_messages set title=p_title,body=p_body,body_format=p_body_format,
    image_url=p_image_url,action_label=p_action_label,action_url=p_action_url,audience_id=v_audience,
    published_at=clock_timestamp(),publication_id=gen_random_uuid()
    where id=p_id returning * into m;
  update public.notification_outbox set status='skipped',last_error='inbox_revised'
    where status='pending' and event_type='call_to_action' and coalesce(payload#>>'{data,inbox_record_id}',payload#>>'{data,inbox_message_id}')=p_id::text;
  return m;
end; $$;
revoke all on function editorial_private.revise_edition(uuid,bigint,text,text,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function editorial_private.revise_edition(uuid,bigint,text,text,text,text,text,text,jsonb) to service_role;
create function public.revise_editorial_inbox(p_id uuid,p_expected_revision bigint,p_title text,p_body text,p_body_format text,p_image_url text,p_action_label text,p_action_url text,p_audience jsonb) returns public.editorial_inbox_messages
language sql security invoker set search_path='' as $$ select editorial_private.revise_edition(p_id,p_expected_revision,p_title,p_body,p_body_format,p_image_url,p_action_label,p_action_url,p_audience); $$;
revoke all on function public.revise_editorial_inbox(uuid,bigint,text,text,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.revise_editorial_inbox(uuid,bigint,text,text,text,text,text,text,jsonb) to service_role;

-- Targeted Nudges ship in Remote Config under "targeted" with an audience id.
-- The phone sends {nudge id: audience id} and shows the nudge ids returned.
-- Each caller learns only whether they themselves are in an audience; unknown
-- ids and signed-out callers match nothing.
create function public.match_editorial_audiences(p_audiences jsonb)
returns text[] language plpgsql stable security definer set search_path = '' as $$
declare matched text[] := '{}'; entry record; v_filters jsonb;
begin
  if jsonb_typeof(p_audiences) is distinct from 'object' then
    raise exception 'Audiences must be an object of id to audience id' using errcode='22023';
  end if;
  if (select count(*) from jsonb_object_keys(p_audiences)) > 100 then
    raise exception 'At most 100 audiences per call' using errcode='22023';
  end if;
  if auth.uid() is null then return matched; end if;
  for entry in select key, value from jsonb_each(p_audiences) order by key loop
    if jsonb_typeof(entry.value) <> 'string' then continue; end if;
    select filters into v_filters from editorial_private.audiences where id = entry.value #>> '{}';
    if found and coalesce(admin_portal.includes(auth.uid(), v_filters), false) then
      matched := matched || entry.key;
    end if;
  end loop;
  return matched;
end; $$;
revoke all on function public.match_editorial_audiences(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.match_editorial_audiences(jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
