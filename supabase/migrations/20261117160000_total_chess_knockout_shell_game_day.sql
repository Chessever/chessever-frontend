-- Total Chess World Championship Tour Pilot 2026, Semifinals (qEXour3L) and
-- Finals (6PTzCQFL): every round of the stage ("Game 1".."Game 14") is
-- published up front as 0-move `*` boards. games_set_game_day() stamps those
-- shells with their round's start date, and the knockout match card in every
-- shipped app orders a match's unfinished boards by
-- `last_move_time ?? game_day ?? date_start`, newest first. Tomorrow's shells
-- (game_day = tomorrow, midnight) therefore sorted above the board actually
-- being played (last_move_time = today), burying the live game.
--
-- Server-side fix for every app version: while a board of these two tours has
-- no move, leave game_day empty. The app then falls back to date_start (the
-- PGN date, never after the live day), so the live board is on top again.
-- The first move sets last_move_time and set_game_day() fills game_day as
-- before; this trigger then steps aside.
--
-- Additive: previous values are kept in a backup table. To undo, drop the
-- trigger and restore game_day from the backup.

create table if not exists broadcasting_private.total_chess_shell_game_day_backup (
  game_id text primary key,
  game_day date,
  backed_up_at timestamptz not null default now()
);

insert into broadcasting_private.total_chess_shell_game_day_backup (game_id, game_day)
select id, game_day
from public.games
where tour_id in ('qEXour3L', '6PTzCQFL')
  and last_move_time is null
  and coalesce(live_ply_count, 0) = 0
  and coalesce(status, '*') = '*'
on conflict (game_id) do nothing;

create or replace function public.games_clear_knockout_shell_game_day()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  if NEW.tour_id in ('qEXour3L', '6PTzCQFL')
     and NEW.last_move_time is null
     and coalesce(NEW.live_ply_count, 0) = 0
     and coalesce(NEW.status, '*') = '*' then
    NEW.game_day := null;
  end if;
  return NEW;
end;
$$;

-- BEFORE triggers fire in name order; "z_" runs after set_game_day.
drop trigger if exists z_clear_knockout_shell_game_day on public.games;
create trigger z_clear_knockout_shell_game_day
  before insert or update on public.games
  for each row
  when (NEW.tour_id in ('qEXour3L', '6PTzCQFL'))
  execute function public.games_clear_knockout_shell_game_day();

update public.games
set game_day = null
where tour_id in ('qEXour3L', '6PTzCQFL')
  and last_move_time is null
  and coalesce(live_ply_count, 0) = 0
  and coalesce(status, '*') = '*'
  and game_day is not null;
