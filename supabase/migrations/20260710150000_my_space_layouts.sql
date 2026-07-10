-- Premium users persist one ordered My Space layout document. Layout rows stay
-- readable after premium expiry, but every mutation is re-authorized by the
-- SECURITY DEFINER RPC below.

create table public.user_my_space_layouts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  schema_version integer not null default 1,
  revision bigint not null default 1,
  shelves jsonb not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint user_my_space_layouts_schema_version_positive
    check (schema_version > 0),
  constraint user_my_space_layouts_revision_positive
    check (revision > 0),
  constraint user_my_space_layouts_shelves_array
    check (pg_catalog.jsonb_typeof(shelves) = 'array'),
  constraint user_my_space_layouts_shelf_count
    check (
      case
        when pg_catalog.jsonb_typeof(shelves) = 'array'
          then pg_catalog.jsonb_array_length(shelves) <= 24
        else false
      end
    ),
  constraint user_my_space_layouts_serialized_payload_size
    check (pg_catalog.octet_length(shelves::text) <= 32768)
);

comment on table public.user_my_space_layouts is
  'One validated, ordered My Space layout per user; writes are RPC-only.';

alter table public.user_my_space_layouts enable row level security;

-- Supabase may install broad default privileges for exposed schemas. Start from
-- no client privileges, then grant only owner-scoped reads.
revoke all on table public.user_my_space_layouts
from public, anon, authenticated;

grant select on table public.user_my_space_layouts
to authenticated;

create policy "Users can read their own My Space layout"
  on public.user_my_space_layouts
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.save_my_space_layout(
  p_layout jsonb,
  p_expected_revision bigint
)
returns public.user_my_space_layouts
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_shelves jsonb;
  v_descriptor jsonb;
  v_key_count bigint;
  v_id text;
  v_type text;
  v_target_id text;
  v_size text;
  v_saved public.user_my_space_layouts%rowtype;
  v_now timestamptz := pg_catalog.statement_timestamp();
begin
  if v_user_id is null then
    raise exception using
      errcode = '28000',
      message = 'MY_SPACE_LAYOUT_UNAUTHENTICATED',
      detail = 'An authenticated user is required to save a My Space layout.';
  end if;

  -- The view includes active/trialing subscriptions and the bounded past-due
  -- grace policy. Reads intentionally do not repeat this premium predicate.
  if not exists (
    select 1
    from public.user_premium_view as premium
    where premium.user_id = v_user_id
      and premium.is_premium is true
  ) then
    raise exception using
      errcode = '42501',
      message = 'MY_SPACE_LAYOUT_PREMIUM_REQUIRED',
      detail = 'An authoritative premium entitlement is required to mutate a My Space layout.';
  end if;

  -- Revision zero means "insert only". Positive revisions must match the
  -- currently stored row exactly.
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception using
      errcode = '22023',
      message = 'MY_SPACE_LAYOUT_INVALID_EXPECTED_REVISION',
      detail = 'Expected revision must be zero for the first save or a positive stored revision.';
  end if;

  if p_layout is null
    or pg_catalog.jsonb_typeof(p_layout) is distinct from 'object'
  then
    raise exception using
      errcode = '22023',
      message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
      detail = 'The layout must be a JSON object.';
  end if;

  select count(*)
  into v_key_count
  from pg_catalog.jsonb_object_keys(p_layout);

  if v_key_count <> 2
    or not (p_layout ? 'schema_version')
    or not (p_layout ? 'shelves')
  then
    raise exception using
      errcode = '22023',
      message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
      detail = 'The layout object must contain exactly schema_version and shelves.';
  end if;

  if pg_catalog.jsonb_typeof(p_layout -> 'schema_version') is distinct from 'number'
    or (p_layout ->> 'schema_version') !~ '^[0-9]+$'
    or (p_layout ->> 'schema_version') <> '1'
  then
    raise exception using
      errcode = '22023',
      message = 'MY_SPACE_LAYOUT_UNSUPPORTED_SCHEMA_VERSION',
      detail = 'Only integer schema_version 1 is accepted.';
  end if;

  if pg_catalog.octet_length(p_layout::text) > 32768 then
    raise exception using
      errcode = '22001',
      message = 'MY_SPACE_LAYOUT_PAYLOAD_TOO_LARGE',
      detail = 'The complete serialized layout must not exceed 32768 bytes.';
  end if;

  v_shelves := p_layout -> 'shelves';

  if pg_catalog.jsonb_typeof(v_shelves) is distinct from 'array' then
    raise exception using
      errcode = '22023',
      message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
      detail = 'shelves must be a JSON array.';
  end if;

  if pg_catalog.jsonb_array_length(v_shelves) > 24 then
    raise exception using
      errcode = '22023',
      message = 'MY_SPACE_LAYOUT_TOO_MANY_SHELVES',
      detail = 'A My Space layout may contain at most 24 shelf descriptors.';
  end if;

  for v_descriptor in
    select descriptor.value
    from pg_catalog.jsonb_array_elements(v_shelves) as descriptor(value)
  loop
    if pg_catalog.jsonb_typeof(v_descriptor) is distinct from 'object' then
      raise exception using
        errcode = '22023',
        message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
        detail = 'Every shelf descriptor must be a JSON object.';
    end if;

    select count(*)
    into v_key_count
    from pg_catalog.jsonb_object_keys(v_descriptor);

    if v_key_count <> 5
      or not (v_descriptor ? 'id')
      or not (v_descriptor ? 'type')
      or not (v_descriptor ? 'targetId')
      or not (v_descriptor ? 'size')
      or not (v_descriptor ? 'visible')
    then
      raise exception using
        errcode = '22023',
        message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
        detail = 'Each descriptor must contain exactly id, type, targetId, size, and visible.';
    end if;

    if pg_catalog.jsonb_typeof(v_descriptor -> 'id') is distinct from 'string' then
      raise exception using
        errcode = '22023',
        message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
        detail = 'Descriptor id must be a string.';
    end if;

    v_id := v_descriptor ->> 'id';
    if v_id = ''
      or v_id ~ '^[[:space:]]'
      or v_id ~ '[[:space:]]$'
      or pg_catalog.char_length(v_id) > 128
    then
      raise exception using
        errcode = '22023',
        message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
        detail = 'Descriptor id must be nonblank, unpadded, and at most 128 characters.';
    end if;

    if pg_catalog.jsonb_typeof(v_descriptor -> 'type') is distinct from 'string' then
      raise exception using
        errcode = '22023',
        message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
        detail = 'Descriptor type must be a string.';
    end if;

    v_type := v_descriptor ->> 'type';
    if v_type not in (
      'continue',
      'my_likes',
      'saved_events',
      'databases',
      'saved_studies',
      'favorite_players',
      'library_recents',
      'miniatures',
      'study_discovery',
      'pinned_event',
      'pinned_database',
      'pinned_folder',
      'pinned_study',
      'pinned_study_chapter',
      'pinned_player',
      'pinned_game'
    ) then
      raise exception using
        errcode = '22023',
        message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
        detail = 'Descriptor type is not supported by schema version 1.';
    end if;

    if v_type in (
      'continue',
      'my_likes',
      'saved_events',
      'databases',
      'saved_studies',
      'favorite_players',
      'library_recents',
      'miniatures',
      'study_discovery'
    ) then
      if v_descriptor -> 'targetId' <> 'null'::jsonb then
        raise exception using
          errcode = '22023',
          message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
          detail = 'Dynamic shelf targetId must be JSON null.';
      end if;
    else
      if pg_catalog.jsonb_typeof(v_descriptor -> 'targetId') is distinct from 'string' then
        raise exception using
          errcode = '22023',
          message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
          detail = 'Pinned shelf targetId must be a string.';
      end if;

      v_target_id := v_descriptor ->> 'targetId';
      if v_target_id = ''
        or v_target_id ~ '^[[:space:]]'
        or v_target_id ~ '[[:space:]]$'
        or pg_catalog.char_length(v_target_id) > 512
      then
        raise exception using
          errcode = '22023',
          message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
          detail = 'Pinned shelf targetId must be nonblank, unpadded, and at most 512 characters.';
      end if;
    end if;

    if pg_catalog.jsonb_typeof(v_descriptor -> 'size') is distinct from 'string' then
      raise exception using
        errcode = '22023',
        message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
        detail = 'Descriptor size must be a string.';
    end if;

    v_size := v_descriptor ->> 'size';
    if not (
      (v_type = 'continue' and v_size in ('standard', 'featured'))
      or (
        v_type in (
          'my_likes',
          'saved_events',
          'databases',
          'saved_studies',
          'favorite_players',
          'library_recents',
          'miniatures',
          'study_discovery'
        )
        and v_size in ('compact', 'standard')
      )
      or (
        v_type in (
          'pinned_event',
          'pinned_database',
          'pinned_folder',
          'pinned_study',
          'pinned_study_chapter',
          'pinned_player',
          'pinned_game'
        )
        and v_size in ('standard', 'featured')
      )
    ) then
      raise exception using
        errcode = '22023',
        message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
        detail = 'Descriptor size is not supported for its shelf type.';
    end if;

    if pg_catalog.jsonb_typeof(v_descriptor -> 'visible') is distinct from 'boolean' then
      raise exception using
        errcode = '22023',
        message = 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
        detail = 'Descriptor visible must be a boolean.';
    end if;
  end loop;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_shelves) as descriptor(value)
    group by descriptor.value ->> 'id'
    having count(*) > 1
  ) then
    raise exception using
      errcode = '22023',
      message = 'MY_SPACE_LAYOUT_DUPLICATE_ID',
      detail = 'Shelf descriptor ids must be unique.';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_shelves) as descriptor(value)
    where descriptor.value ->> 'type' in (
      'continue',
      'my_likes',
      'saved_events',
      'databases',
      'saved_studies',
      'favorite_players',
      'library_recents',
      'miniatures',
      'study_discovery'
    )
    group by descriptor.value ->> 'type'
    having count(*) > 1
  ) then
    raise exception using
      errcode = '22023',
      message = 'MY_SPACE_LAYOUT_DUPLICATE_DYNAMIC_TYPE',
      detail = 'Each dynamic shelf type is a singleton.';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_shelves) as descriptor(value)
    where descriptor.value ->> 'type' in (
      'pinned_event',
      'pinned_database',
      'pinned_folder',
      'pinned_study',
      'pinned_study_chapter',
      'pinned_player',
      'pinned_game'
    )
    group by
      descriptor.value ->> 'type',
      descriptor.value ->> 'targetId'
    having count(*) > 1
  ) then
    raise exception using
      errcode = '22023',
      message = 'MY_SPACE_LAYOUT_DUPLICATE_PINNED_TARGET',
      detail = 'A pinned type and targetId pair may appear only once.';
  end if;

  if p_expected_revision = 0 then
    insert into public.user_my_space_layouts (
      user_id,
      schema_version,
      revision,
      shelves,
      created_at,
      updated_at
    )
    values (v_user_id, 1, 1, v_shelves, v_now, v_now)
    on conflict (user_id) do nothing
    returning * into v_saved;
  else
    update public.user_my_space_layouts as layout
    set schema_version = 1,
        revision = layout.revision + 1,
        shelves = v_shelves,
        updated_at = v_now
    where layout.user_id = v_user_id
      and layout.revision = p_expected_revision
    returning layout.* into v_saved;
  end if;

  if v_saved.user_id is null then
    raise exception using
      errcode = '40001',
      message = 'MY_SPACE_LAYOUT_REVISION_CONFLICT',
      detail = 'The expected revision does not match the stored layout revision.';
  end if;

  return v_saved;
end;
$function$;

comment on function public.save_my_space_layout(jsonb, bigint) is
  'Validates and atomically saves schema-v1 My Space layouts. Reset-to-default saves the curated default through this same RPC with the current expected revision; it never deletes the row, so revision remains monotonic.';

revoke all on function public.save_my_space_layout(jsonb, bigint)
from public, anon, authenticated;

grant execute on function public.save_my_space_layout(jsonb, bigint)
to authenticated;
