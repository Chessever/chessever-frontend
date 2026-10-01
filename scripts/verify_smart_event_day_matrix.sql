-- Run against the explicitly selected production app database after the
-- additive migration. This comparison uses existing data, writes only TEMP
-- tables, and rolls everything back. No user/game/event row is changed.
begin;
set local statement_timeout = '45s';

-- Independent oracle: reduce existing games to their latest date per exact
-- opening, format, rating band and eligibility. Rating is calculated here
-- without calling the new helper, to detect rating/rounding discrepancies.
create temp table smart_day_oracle on commit drop as
with rated as (
  select g.game_day, g.eco, g.status, g.last_move, g.last_move_time,
    g.last_clock_white, g.last_clock_black,
    case when g.players->0->>'rating' ~ '^[0-9]+$'
          and g.players->1->>'rating' ~ '^[0-9]+$'
          and (g.players->0->>'rating')::numeric > 0
          and (g.players->1->>'rating')::numeric > 0
      then floor(((g.players->0->>'rating')::numeric
                + (g.players->1->>'rating')::numeric) / 2) else 0 end as average,
    case lower(btrim(b.time_control))
      when 'standard' then 1 when 'classical' then 1
      when 'rapid' then 2 when 'blitz' then 3 when 'bullet' then 3
      else 0 end as format
  from public.games g
  join public.rounds r on r.id = g.round_id
  left join public.tours t on t.id = g.tour_id
  left join public.group_broadcasts b on b.id = t.group_broadcast_id
  where g.game_day <= (now() at time zone 'UTC')::date
    and (r.starts_at is null or r.starts_at <= now())
), facts as (
  select *,
    case when average >= 2500 then 2500 when average >= 2400 then 2400
      when average >= 2300 then 2300 when average >= 2200 then 2200
      else 0 end as rating_band,
    coalesce(status not in ('*','ongoing','live'), false) as completed,
    coalesce(status in ('*','ongoing','live') and last_move is not null
      and last_move_time >= now() - interval '8 hours'
      and last_clock_white > 0 and last_clock_black > 0, false) as live
  from rated
)
select eco, format, rating_band, completed, live, max(game_day) as newest
from facts group by eco, format, rating_band, completed, live;

create temp table smart_day_matrix on commit drop as
select states.mask as state_mask, formats.mask as format_mask, levels.floor,
  openings.id as opening_id, openings.codes,
  case when formats.mask in (0,7) then null else array(
    select token from (values
      (1,'standard'),(1,'classical'),(2,'rapid'),(4,'blitz'),(4,'bullet')
    ) f(bit,token) where (formats.mask & f.bit) != 0
  ) end as time_controls
from generate_series(0,3) states(mask)
cross join generate_series(0,7) formats(mask)
cross join (values (0),(2200),(2300),(2400),(2500)) levels(floor)
cross join (values
  ('all',null::text[]), ('exact',array['C44']),
  ('decade',array(select 'B'||n from generate_series(90,99) n)),
  ('irregular',array(select 'D'||n from generate_series(30,42) n)),
  ('multiple',array(select 'E'||n from generate_series(60,99) n))
) openings(id,codes);

create temp table smart_day_results (
  state_mask integer, format_mask integer, floor integer, opening_id text,
  expected date, actual date, seconds double precision
) on commit drop;

do $$
declare c record; expected_day date; actual_day date; started timestamptz;
begin
  for c in select * from smart_day_matrix loop
    select max(o.newest) into expected_day from smart_day_oracle o
    where o.rating_band >= c.floor
      and (c.codes is null or o.eco = any(c.codes))
      and (c.format_mask in (0,7)
        or o.format > 0 and (c.format_mask & (1 << (o.format - 1))) != 0)
      and (c.state_mask != 1 or o.live)
      and (c.state_mask != 2 or o.completed);
    started := clock_timestamp();
    actual_day := public.get_current_smart_event_day(
      p_min_rating => nullif(c.floor,0), p_eco_codes => c.codes,
      p_time_controls => c.time_controls,
      p_live_only => c.state_mask = 1,
      p_completed_only => c.state_mask = 2
    );
    insert into smart_day_results values (
      c.state_mask,c.format_mask,c.floor,c.opening_id,expected_day,actual_day,
      extract(epoch from clock_timestamp() - started));
  end loop;
  if exists(select 1 from smart_day_results where expected is distinct from actual) then
    raise exception 'Smart event day matrix differs from independent oracle';
  end if;
end;
$$;

select jsonb_build_object(
  'summary', (select jsonb_build_object(
    'combinations', count(*),
    'mismatches', count(*) filter(where expected is distinct from actual),
    'slowest_seconds', round(max(seconds)::numeric,4),
    'p95_seconds', round((percentile_cont(0.95) within group (order by seconds))::numeric,4),
    'total_rpc_seconds', round(sum(seconds)::numeric,3)
  ) from smart_day_results),
  'slow_cases', (select jsonb_agg(c) from (
    select state_mask,format_mask,floor,opening_id,
      round(seconds::numeric,4) as seconds from smart_day_results
    order by seconds desc limit 5
  ) c)
) as verification;
rollback;
