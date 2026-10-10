-- One-way editorial Inbox. Additive; no push, email, recipient fan-out or
-- existing notification/feed changes. Everyone can read published messages;
-- signed-in AND Supabase anonymous-auth guests can record their own reads.
-- Publishing is service_role-only through the two administrative RPCs below.

begin;

-- The foreign key to auth.users takes a lock there. Give up quickly rather than
-- queue sign-ins behind a long-running transaction; re-run if it times out.
set local lock_timeout = '5s';

create table public.editorial_inbox_messages (
  -- Explicit UUIDs make administrative retries identify the same message.
  id uuid primary key,
  title text not null,
  body text not null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  constraint editorial_inbox_title_bounds check (
    char_length(title) between 1 and 200
    and title ~ '[^[:space:]]'
    and position(chr(10) in title) = 0
    and position(chr(13) in title) = 0
  ),
  constraint editorial_inbox_body_bounds check (
    char_length(body) between 1 and 20000 and body ~ '[^[:space:]]'
  )
);

comment on column public.editorial_inbox_messages.body is
  'Plain text only; clients must not interpret this as HTML or Markdown.';
comment on column public.editorial_inbox_messages.published_at is
  'NULL is a draft. Publication is server-timed and irreversible; published content is immutable.';

create table public.editorial_inbox_reads (
  user_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null references public.editorial_inbox_messages(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (user_id, message_id)
);

create index editorial_inbox_published_order_idx
  on public.editorial_inbox_messages (published_at desc, id desc)
  where published_at is not null;
-- The primary key handles per-user reads; this index also supports FK deletion.
create index editorial_inbox_reads_message_idx
  on public.editorial_inbox_reads (message_id);

alter table public.editorial_inbox_messages enable row level security;
alter table public.editorial_inbox_reads enable row level security;

create policy editorial_inbox_visible_messages
  on public.editorial_inbox_messages for select to anon, authenticated
  using (published_at is not null and published_at <= now());
create policy editorial_inbox_own_reads
  on public.editorial_inbox_reads for select to authenticated
  using (user_id = (select auth.uid()));

-- Do not inherit any broad Supabase default table/function privileges.
revoke all on public.editorial_inbox_messages from public, anon, authenticated, service_role;
revoke all on public.editorial_inbox_reads from public, anon, authenticated, service_role;
grant select on public.editorial_inbox_messages to anon, authenticated, service_role;
grant select on public.editorial_inbox_reads to authenticated;

-- Even privileged accidental UPDATEs cannot edit/unpublish a published item.
-- No remote administrative RPC accepts a publication timestamp or created_at.
create function public.guard_editorial_inbox_message()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if old.published_at is not null then
      raise exception 'Published editorial messages are immutable' using errcode = '55000';
    end if;
    if new.id is distinct from old.id or new.created_at is distinct from old.created_at then
      raise exception 'Editorial message identity and creation time are immutable' using errcode = '55000';
    end if;
  end if;
  if new.published_at is not null then
    new.published_at := now();
  end if;
  return new;
end;
$$;
revoke all on function public.guard_editorial_inbox_message() from public, anon, authenticated, service_role;
create trigger editorial_inbox_message_guard
  before insert or update on public.editorial_inbox_messages
  for each row execute function public.guard_editorial_inbox_message();

-- Authenticated includes signInAnonymously guests; no account-upgrade gate.
-- Invoker retains table RLS. Anonymous (no auth UUID) can SELECT visible
-- messages directly, but cannot execute session/read RPCs.
create function public.list_editorial_inbox(
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
    select m.id, m.title, m.body, m.published_at, r.read_at
    from public.editorial_inbox_messages m
    left join public.editorial_inbox_reads r
      on r.message_id = m.id and r.user_id = v_user_id
    where m.published_at is not null and m.published_at <= now()
      and (p_before_id is null or (m.published_at, m.id) < (p_before_published_at, p_before_id))
    order by m.published_at desc, m.id desc
    limit least(p_limit, 100);
end;
$$;
revoke all on function public.list_editorial_inbox(timestamptz, uuid, integer) from public, anon, authenticated, service_role;
grant execute on function public.list_editorial_inbox(timestamptz, uuid, integer) to authenticated;

create function public.mark_editorial_inbox_read(p_message_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_read_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'An authenticated session is required' using errcode = '28000';
  end if;
  -- Lock this exact visible item against privileged deletion until the FK
  -- insert finishes. Missing, draft and future items share the same failure.
  perform 1 from public.editorial_inbox_messages m
    where m.id = p_message_id and m.published_at is not null and m.published_at <= now()
    for key share;
  if not found then
    raise exception 'Published editorial message not found' using errcode = 'P0002';
  end if;
  insert into public.editorial_inbox_reads (user_id, message_id)
    values (v_user_id, p_message_id)
    on conflict (user_id, message_id) do nothing;
  -- A separate statement also sees the winner of a simultaneous first mark.
  select r.read_at into v_read_at from public.editorial_inbox_reads r
    where r.user_id = v_user_id and r.message_id = p_message_id;
  return v_read_at;
end;
$$;
revoke all on function public.mark_editorial_inbox_read(uuid) from public, anon, authenticated, service_role;
grant execute on function public.mark_editorial_inbox_read(uuid) to authenticated;

-- Administrative additions do not change the frontend contract. No direct
-- INSERT/UPDATE/DELETE grants, arbitrary user parameters or timestamp inputs.
create function public.save_editorial_inbox_draft(p_id uuid, p_title text, p_body text)
returns public.editorial_inbox_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message public.editorial_inbox_messages;
begin
  insert into public.editorial_inbox_messages (id, title, body)
    values (p_id, p_title, p_body)
    on conflict (id) do update set title = excluded.title, body = excluded.body
      where editorial_inbox_messages.published_at is null
    returning * into v_message;
  if not found then
    raise exception 'Published editorial messages are immutable' using errcode = '55000';
  end if;
  return v_message;
end;
$$;
revoke all on function public.save_editorial_inbox_draft(uuid, text, text) from public, anon, authenticated, service_role;
grant execute on function public.save_editorial_inbox_draft(uuid, text, text) to service_role;

create function public.publish_editorial_inbox(p_id uuid, p_expected_title text, p_expected_body text)
returns public.editorial_inbox_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message public.editorial_inbox_messages;
begin
  -- Check the displayed/approved snapshot under the same lock as publishing;
  -- a concurrent draft edit must not silently publish different content.
  select * into v_message from public.editorial_inbox_messages where id = p_id for update;
  if not found then
    raise exception 'Editorial draft not found' using errcode = 'P0002';
  end if;
  if v_message.title is distinct from p_expected_title or v_message.body is distinct from p_expected_body then
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
revoke all on function public.publish_editorial_inbox(uuid, text, text) from public, anon, authenticated, service_role;
grant execute on function public.publish_editorial_inbox(uuid, text, text) to service_role;

commit;
