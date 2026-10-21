-- Rich editorial Inbox. Additive on top of 20261010120000_editorial_inbox.sql:
-- a message may be Markdown, may carry one attached image, and may end in one
-- button that opens a link (a ChessEver page opens inside the app). Nothing is
-- removed or rewritten: published rows keep body_format 'plain', and the
-- original RPCs stay for app builds that predate this (they keep receiving
-- id/title/body, and show a Markdown body as its source text).
--
-- A push's own title, text and image are not stored here. They travel in the
-- notification_outbox payload the admin queues at publish time.

begin;

-- ADD COLUMN takes a brief exclusive lock on a tiny table. Give up quickly
-- rather than queue Inbox reads behind a long transaction; re-run if it times out.
set local lock_timeout = '5s';

alter table public.editorial_inbox_messages
  add column body_format text not null default 'plain',
  add column image_url text,
  add column action_label text,
  add column action_url text,
  add constraint editorial_inbox_body_format_known check (
    body_format in ('plain', 'markdown')
  ),
  add constraint editorial_inbox_image_url_bounds check (
    image_url is null
    or (char_length(image_url) between 12 and 2000 and image_url ~ '^https://[^[:space:]]+$')
  ),
  -- The button is a label and where it leads, together or not at all.
  add constraint editorial_inbox_action_bounds check (
    (action_label is null and action_url is null)
    or (
      action_label is not null and action_url is not null
      and char_length(action_label) between 1 and 40
      and action_label ~ '[^[:space:]]'
      and position(chr(10) in action_label) = 0
      and position(chr(13) in action_label) = 0
      and char_length(action_url) between 12 and 2000
      and action_url ~ '^https://[^[:space:]]+$'
    )
  );

comment on column public.editorial_inbox_messages.body is
  'Text in body_format. Clients never interpret it as HTML.';
comment on column public.editorial_inbox_messages.body_format is
  '''plain'' is shown literally; ''markdown'' is rendered. Unknown values must be shown literally.';
comment on column public.editorial_inbox_messages.action_url is
  'Where the message''s button leads. Clients open chessever.com links in the app and anything else in the browser.';
comment on column public.editorial_inbox_messages.image_url is
  'Optional attached image. Clients load it only from origins they allow (public Storage of this project).';

-- Attached and inline images. Public read by URL; only the service role
-- (the admin console) uploads, so no storage policy grants client writes.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'editorial-inbox',
  'editorial-inbox',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- Same contract as list_editorial_inbox, plus the new columns. A new name
-- rather than a changed return type, so the original stays callable.
create function public.list_editorial_inbox_v2(
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
      m.published_at, r.read_at
    from public.editorial_inbox_messages m
    left join public.editorial_inbox_reads r
      on r.message_id = m.id and r.user_id = v_user_id
    where m.published_at is not null and m.published_at <= now()
      and (p_before_id is null or (m.published_at, m.id) < (p_before_published_at, p_before_id))
    order by m.published_at desc, m.id desc
    limit least(p_limit, 100);
end;
$$;
revoke all on function public.list_editorial_inbox_v2(timestamptz, uuid, integer) from public, anon, authenticated, service_role;
grant execute on function public.list_editorial_inbox_v2(timestamptz, uuid, integer) to authenticated;

create function public.save_editorial_inbox_draft_v2(
  p_id uuid,
  p_title text,
  p_body text,
  p_body_format text,
  p_image_url text,
  p_action_label text,
  p_action_url text
)
returns public.editorial_inbox_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message public.editorial_inbox_messages;
begin
  insert into public.editorial_inbox_messages
      (id, title, body, body_format, image_url, action_label, action_url)
    values (p_id, p_title, p_body, p_body_format, p_image_url, p_action_label, p_action_url)
    on conflict (id) do update
      set title = excluded.title,
          body = excluded.body,
          body_format = excluded.body_format,
          image_url = excluded.image_url,
          action_label = excluded.action_label,
          action_url = excluded.action_url
      where editorial_inbox_messages.published_at is null
    returning * into v_message;
  if not found then
    raise exception 'Published editorial messages are immutable' using errcode = '55000';
  end if;
  return v_message;
end;
$$;
revoke all on function public.save_editorial_inbox_draft_v2(uuid, text, text, text, text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.save_editorial_inbox_draft_v2(uuid, text, text, text, text, text, text) to service_role;

create function public.publish_editorial_inbox_v2(
  p_id uuid,
  p_expected_title text,
  p_expected_body text,
  p_expected_body_format text,
  p_expected_image_url text,
  p_expected_action_label text,
  p_expected_action_url text
)
returns public.editorial_inbox_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message public.editorial_inbox_messages;
begin
  -- The whole approved snapshot is checked under the publishing lock: text,
  -- how it is rendered, the picture that goes with it, and the button.
  select * into v_message from public.editorial_inbox_messages where id = p_id for update;
  if not found then
    raise exception 'Editorial draft not found' using errcode = 'P0002';
  end if;
  if v_message.title is distinct from p_expected_title
    or v_message.body is distinct from p_expected_body
    or v_message.body_format is distinct from p_expected_body_format
    or v_message.image_url is distinct from p_expected_image_url
    or v_message.action_label is distinct from p_expected_action_label
    or v_message.action_url is distinct from p_expected_action_url then
    raise exception 'Editorial draft changed; preview and approve again' using errcode = '55000';
  end if;
  if v_message.published_at is null then
    update public.editorial_inbox_messages set published_at = now()
      where id = p_id returning * into v_message;
  end if;
  -- An explicit UUID retry returns the original publication unchanged.
  return v_message;
end;
$$;
revoke all on function public.publish_editorial_inbox_v2(uuid, text, text, text, text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.publish_editorial_inbox_v2(uuid, text, text, text, text, text, text) to service_role;

commit;
