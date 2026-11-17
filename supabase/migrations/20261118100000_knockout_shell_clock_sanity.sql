-- Unplayed boards of a parked knockout tour: never show an impossible clock.
--
-- The Total Chess semifinal file publishes board 1's blitz boards (Games
-- 8-11, Giri-MVL) with a starting clock of 3:00:02 (1080200 centiseconds)
-- where every other board carries 3:02 (18200) for the 180+2 control.
-- Every app printed three hours on both sides. While a board of a parked
-- tour has no move, a clock above twice the control's base is replaced by
-- base + increment; the first move brings the relay's real clocks.

create or replace function public.games_park_unstarted_knockout_shells()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_real text;
  v_parking text;
  v_base bigint;
  v_inc bigint;
  v_side int;
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

    v_base := nullif(substring(NEW.pgn from '\[TimeControl "([0-9]+)'), '')::bigint;
    v_inc := coalesce(nullif(substring(NEW.pgn from '\[TimeControl "[0-9]+\+([0-9]+)'), '')::bigint, 0);
    if v_base is not null and v_base > 0 and jsonb_typeof(NEW.players) = 'array' then
      for v_side in 0..1 loop
        if jsonb_typeof(NEW.players->v_side->'clock') = 'number'
           and (NEW.players->v_side->>'clock')::numeric > 2 * 100 * v_base then
          NEW.players := jsonb_set(
            NEW.players, array[v_side::text, 'clock'], to_jsonb((v_base + v_inc) * 100));
        end if;
      end loop;
    end if;
  else
    NEW.tour_id := v_real;
  end if;
  return NEW;
end;
$$;

update public.games g
   set players = g.players
 where g.tour_id in (select tour_id from broadcasting_private.knockout_shell_parking
                     union select parking_tour_id from broadcasting_private.knockout_shell_parking)
   and g.last_move_time is null
   and coalesce(g.live_ply_count, 0) = 0
   and coalesce(g.status, '*') = '*';
