create or replace function public.get_for_you_group_broadcasts(
  p_limit integer default 20,
  p_offset integer default 0,
  p_time_controls text[] default null,
  p_min_elo integer default null,
  p_max_elo integer default null,
  p_statuses text[] default null
)
returns table (
  id text,
  created_at timestamptz,
  name text,
  search text[],
  max_avg_elo smallint,
  date_start timestamptz,
  date_end timestamptz,
  time_control text,
  date_closest_round timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  with params as (
    select
      greatest(0, least(coalesce(p_limit, 20), 100)) as limit_count,
      greatest(0, coalesce(p_offset, 0)) as offset_count,
      coalesce(p_time_controls, '{}'::text[]) as time_controls,
      coalesce(p_statuses, '{}'::text[]) as statuses
  ),
  live_settings as (
    select coalesce(s.live_group_broadcast_ids, '{}'::text[]) as live_ids
    from public.settings s
    where s.id = 1
  ),
  window_current as (
    select distinct t.group_broadcast_id as id
    from public.rounds r
    join public.tours t on t.id = r.tour_id
    where t.group_broadcast_id is not null
      and r.starts_at is not null
      and r.starts_at >= now() - interval '1 day'
      and r.starts_at <= now()
  ),
  fallback_current as (
    select gb.id
    from public.group_broadcasts gb
    where gb.date_start < now()
      and (gb.date_end is null or gb.date_end > now() - interval '3 days')
      and exists (
        select 1
        from public.tours t
        where t.group_broadcast_id = gb.id
      )
      and not exists (
        select 1
        from public.tours t
        join public.rounds r on r.tour_id = t.id
        where t.group_broadcast_id = gb.id
          and r.starts_at is not null
      )
  ),
  current_ids as (
    select id from window_current
    union
    select id from fallback_current
  )
  select
    gb.id,
    gb.created_at,
    gb.name,
    gb.search,
    gb.max_avg_elo,
    gb.date_start,
    gb.date_end,
    gb.time_control,
    gb.date_closest_round
  from current_ids ci
  join public.group_broadcasts gb on gb.id = ci.id
  cross join params p
  cross join live_settings ls
  where (
      cardinality(p.time_controls) = 0
      or gb.time_control = any(p.time_controls)
    )
    and (p_min_elo is null or gb.max_avg_elo >= p_min_elo)
    and (p_max_elo is null or gb.max_avg_elo <= p_max_elo)
    and (
      cardinality(p.statuses) = 0
      or ('live' = any(p.statuses) and gb.id = any(ls.live_ids))
      or ('completed' = any(p.statuses) and not gb.id = any(ls.live_ids))
    )
  order by gb.max_avg_elo desc nulls last
  limit (select limit_count from params)
  offset (select offset_count from params);
$$;

revoke all on function public.get_for_you_group_broadcasts(
  integer,
  integer,
  text[],
  integer,
  integer,
  text[]
) from public;

grant execute on function public.get_for_you_group_broadcasts(
  integer,
  integer,
  text[],
  integer,
  integer,
  text[]
) to authenticated;
