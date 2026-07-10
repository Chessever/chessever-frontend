create or replace function public.get_strict_live_group_broadcast_ids(
  p_live_round_ids text[],
  p_stale_after_seconds integer default 7200
)
returns table (group_broadcast_id text)
language sql
stable
security invoker
set search_path = ''
as $$
  with live_rounds as materialized (
    select
      r.id,
      r.tour_id,
      r.starts_at
    from public.rounds r
    where r.id = any(coalesce(p_live_round_ids, '{}'::text[]))
  ),
  latest_game_activity as materialized (
    select
      g.round_id,
      max(g.last_move_time) as last_move_time
    from public.games g
    join live_rounds lr on lr.id = g.round_id
    where g.last_move_time is not null
    group by g.round_id
  )
  select distinct
    t.group_broadcast_id
  from live_rounds lr
  join public.tours t on t.id = lr.tour_id
  join public.group_broadcasts gb on gb.id = t.group_broadcast_id
  left join latest_game_activity lga on lga.round_id = lr.id
  where t.group_broadcast_id is not null
    and t.group_broadcast_id <> ''
    and now() <= coalesce(lga.last_move_time, lr.starts_at)
      + pg_catalog.make_interval(
          secs => greatest(coalesce(p_stale_after_seconds, 7200), 0)
        )
  order by t.group_broadcast_id;
$$;

comment on function public.get_strict_live_group_broadcast_ids(text[], integer)
is 'Returns strict-live event IDs from configured live rounds in one compact query.';

revoke all on function public.get_strict_live_group_broadcast_ids(text[], integer)
from public, anon;

grant execute on function public.get_strict_live_group_broadcast_ids(text[], integer)
to authenticated;
