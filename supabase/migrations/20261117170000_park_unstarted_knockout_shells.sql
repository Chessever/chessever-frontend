-- Hide boards published ahead of their day from every frontend, old builds
-- included, until their first move.
--
-- Total Chess World Championship Tour Pilot 2026 publishes every game of a
-- stage on day one as 0-move `*` boards (Semifinals: Games 1-14, 12 boards
-- each). Every shipped app before 38.14.2 reads an unfinished board as live,
-- so those future games filled the top of the Games tab above the game in
-- play and the played games.
--
-- Apps load an event's games by `tour_id`. While a board of a listed tour has
-- no move, it is parked under a hidden tour (no group broadcast, so no app
-- lists it); `round_id` is untouched, so the ingest's round reads (status
-- counts, board renumbering) still see it. The first move, whatever writer
-- sends it, moves the board back in the same statement, before the
-- notification trigger runs. Undo: delete the tour's row from
-- broadcasting_private.knockout_shell_parking and run
--   update public.games set tour_id = <real> where tour_id = <parking>;
-- Never delete a parking tour while boards are parked under it (cascade).
--
-- Replaces 20261117160000 (game_day clearing); parked boards keep game_day
-- empty for the same reason.

create table if not exists broadcasting_private.knockout_shell_parking (
  tour_id text primary key references public.tours(id),
  parking_tour_id text not null unique references public.tours(id),
  created_at timestamptz not null default now()
);

insert into public.tours (id, name, slug, info, created_at, url, tier, dates, players, group_broadcast_id, search)
values
  ('pk_qEXour3L', 'Total Chess World Championship Tour Pilot 2026 | Semifinals (upcoming boards)',
   'parked-qexour3l', '{}'::jsonb, now(), '', 0, array[]::timestamptz[], '[]'::jsonb, null, array[]::text[]),
  ('pk_6PTzCQFL', 'Total Chess World Championship Tour Pilot 2026 | Finals (upcoming boards)',
   'parked-6ptzcqfl', '{}'::jsonb, now(), '', 0, array[]::timestamptz[], '[]'::jsonb, null, array[]::text[])
on conflict (id) do nothing;

insert into broadcasting_private.knockout_shell_parking (tour_id, parking_tour_id)
values ('qEXour3L', 'pk_qEXour3L'), ('6PTzCQFL', 'pk_6PTzCQFL')
on conflict (tour_id) do nothing;

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
    NEW.tour_id := v_parking;
    NEW.game_day := null;
  else
    NEW.tour_id := v_real;
  end if;
  return NEW;
end;
$$;

drop trigger if exists z_clear_knockout_shell_game_day on public.games;
drop function if exists public.games_clear_knockout_shell_game_day();

-- BEFORE triggers fire in name order: after set_game_day and the override
-- trigger, before the AFTER notification trigger sees the row.
drop trigger if exists zz_park_unstarted_knockout_shells on public.games;
create trigger zz_park_unstarted_knockout_shells
  before insert or update on public.games
  for each row
  execute function public.games_park_unstarted_knockout_shells();

update public.games
set tour_id = tour_id
where tour_id in ('qEXour3L', '6PTzCQFL')
  and last_move_time is null
  and coalesce(live_ply_count, 0) = 0
  and coalesce(status, '*') = '*';
