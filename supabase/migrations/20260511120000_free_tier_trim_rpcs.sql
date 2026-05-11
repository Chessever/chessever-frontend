-- Server-side trim helpers used by the RevenueCat webhook (on EXPIRATION) and
-- the trim-overlimit-free-users admin Edge Function. Both functions are
-- SECURITY DEFINER so they can bypass the user-scoped RLS policies on
-- user_favorite_players / user_saved_analyses when invoked with the service
-- role from server contexts.

create or replace function public.trim_favorite_players_to_top_n(
  p_user_id uuid,
  p_keep    int
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  if p_user_id is null or p_keep is null or p_keep < 0 then
    return 0;
  end if;

  with ranked as (
    select id,
      row_number() over (
        order by
          case
            when metadata ? 'rating'
              and jsonb_typeof(metadata->'rating') = 'number'
              then (metadata->>'rating')::int
            when metadata ? 'rating'
              and jsonb_typeof(metadata->'rating') = 'string'
              and metadata->>'rating' ~ '^[0-9]+$'
              then (metadata->>'rating')::int
            else null
          end desc nulls last,
          created_at desc,
          id desc
      ) as rn
    from public.user_favorite_players
    where user_id = p_user_id
  ),
  deleted as (
    delete from public.user_favorite_players
    where id in (select id from ranked where rn > p_keep)
    returning 1
  )
  select count(*)::int into v_deleted from deleted;

  return v_deleted;
end;
$$;

create or replace function public.trim_saved_analyses_to_recent_n(
  p_user_id uuid,
  p_keep    int
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  if p_user_id is null or p_keep is null or p_keep < 0 then
    return 0;
  end if;

  with ranked as (
    select id,
      row_number() over (
        order by created_at desc, id desc
      ) as rn
    from public.user_saved_analyses
    where user_id = p_user_id
  ),
  deleted as (
    delete from public.user_saved_analyses
    where id in (select id from ranked where rn > p_keep)
    returning 1
  )
  select count(*)::int into v_deleted from deleted;

  return v_deleted;
end;
$$;

revoke all on function public.trim_favorite_players_to_top_n(uuid, int) from public, anon, authenticated;
revoke all on function public.trim_saved_analyses_to_recent_n(uuid, int) from public, anon, authenticated;

grant execute on function public.trim_favorite_players_to_top_n(uuid, int) to service_role;
grant execute on function public.trim_saved_analyses_to_recent_n(uuid, int) to service_role;
