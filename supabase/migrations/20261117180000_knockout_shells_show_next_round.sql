-- Keep the NEXT game's boards visible; park only the ones after it.
--
-- 20261117170000 parked every 0-move board of the Total Chess knockout
-- stages. Between games that left only finished boards, and every shipped
-- app then ordered the matches by their latest finish, so the match that
-- ended last jumped to the top (Mishra-Vaishali after Game 5) instead of the
-- board order. With the next game's boards in the tour, every match holds an
-- unplayed board: builds before 38.14.2 keep every match in one tier with the
-- same latest start (a stable order), and inside a match that board sits
-- under the game in play.
--
-- The next round of a parked tour is its earliest-starting round that still
-- holds a 0-move board. The trigger applies the rule on every write; a cron
-- job re-applies it each minute, because the first move of the next round
-- changes which round is next for boards nobody writes.

create or replace function broadcasting_private.knockout_next_shell_round(p_tour_id text)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select r.id
  from public.rounds r
  where r.tour_id = p_tour_id
    and exists (
      select 1 from public.games g
      where g.round_id = r.id
        and g.last_move_time is null
        and coalesce(g.live_ply_count, 0) = 0
        and coalesce(g.status, '*') = '*'
    )
  order by r.starts_at asc nulls last, r.created_at asc, r.id
  limit 1
$$;

create or replace function public.games_park_unstarted_knockout_shells()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_real text;
  v_parking text;
begin
  select p.tour_id, p.parking_tour_id
    into v_real, v_parking
    from broadcasting_private.knockout_shell_parking p
   where p.tour_id = NEW.tour_id or p.parking_tour_id = NEW.tour_id
   limit 1;
  if v_real is null then
    return NEW;
  end if;

  if NEW.last_move_time is null
     and coalesce(NEW.live_ply_count, 0) = 0
     and coalesce(NEW.status, '*') = '*' then
    NEW.game_day := null;
    if NEW.round_id is not distinct from
       broadcasting_private.knockout_next_shell_round(v_real) then
      NEW.tour_id := v_real;
    else
      NEW.tour_id := v_parking;
    end if;
  else
    NEW.tour_id := v_real;
  end if;
  return NEW;
end;
$$;

create or replace function broadcasting_private.reapply_knockout_shell_parking()
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_count integer := 0;
  v_rows integer;
  p record;
  v_next text;
begin
  for p in select tour_id, parking_tour_id from broadcasting_private.knockout_shell_parking loop
    v_next := broadcasting_private.knockout_next_shell_round(p.tour_id);
    update public.games g
       set tour_id = g.tour_id
     where g.tour_id in (p.tour_id, p.parking_tour_id)
       and g.last_move_time is null
       and coalesce(g.live_ply_count, 0) = 0
       and coalesce(g.status, '*') = '*'
       and (
         (g.round_id is not distinct from v_next and g.tour_id <> p.tour_id)
         or (g.round_id is distinct from v_next and g.tour_id <> p.parking_tour_id)
         or g.game_day is not null
       );
    get diagnostics v_rows = row_count;
    v_count := v_count + v_rows;
  end loop;
  return v_count;
end;
$$;

select cron.unschedule('reapply-knockout-shell-parking')
where exists (select 1 from cron.job where jobname = 'reapply-knockout-shell-parking');

select cron.schedule(
  'reapply-knockout-shell-parking',
  '* * * * *',
  $$select broadcasting_private.reapply_knockout_shell_parking()$$
);

select broadcasting_private.reapply_knockout_shell_parking();
