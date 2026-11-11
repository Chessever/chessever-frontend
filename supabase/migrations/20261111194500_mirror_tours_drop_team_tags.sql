-- A mirror section never reads as a team event, on any app build.
--
-- Lichess tags every Total Chess Combined player with their group as a
-- "team" ("Group C"). info.teamTable=false already stops current builds, but
-- the apps also infer a team event when most players carry a team tag, and a
-- client holding an older copy of the tour can still land on the team view.
-- Mirror tours therefore drop the team key from tours.players and from every
-- element of their games' players. Triggers keep it that way through every
-- Lichess sync; nothing else in a player entry changes.

set lock_timeout = '10s';

create or replace function public.tours_mirror_players()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if coalesce(new.info->>'mirror', '') = 'true'
     and jsonb_typeof(new.players) = 'array'
     and new.players::text like '%"team"%' then
    new.players := (
      select coalesce(jsonb_agg(
        case when jsonb_typeof(e) = 'object' then e - 'team' else e end
        order by ord), '[]'::jsonb)
      from jsonb_array_elements(new.players) with ordinality as x(e, ord)
    );
  end if;
  return new;
end;
$$;

-- Fires after tours_zz_apply_info_override (BEFORE triggers run in name
-- order), so an override that sets info.mirror is already applied.
drop trigger if exists tours_zzz_mirror_players on public.tours;
create trigger tours_zzz_mirror_players
before insert or update on public.tours
for each row execute function public.tours_mirror_players();

create or replace function public.games_mark_mirror()
returns trigger
language plpgsql
set search_path to ''
as $$
declare
  mirror boolean;
begin
  select coalesce(t.info->>'mirror', '') = 'true' into mirror
  from public.tours t
  where t.id = new.tour_id;
  mirror := coalesce(mirror, false);

  if jsonb_typeof(new.players) = 'array' then
    if mirror then
      new.players := (
        select coalesce(jsonb_agg(
          case when jsonb_typeof(e) = 'object'
            then (e - 'team') || '{"mirror": true}'::jsonb else e end
          order by ord), '[]'::jsonb)
        from jsonb_array_elements(new.players) with ordinality as x(e, ord)
      );
    elsif new.players::text like '%"mirror"%' then
      new.players := (
        select coalesce(jsonb_agg(
          case when jsonb_typeof(e) = 'object' then e - 'mirror' else e end
          order by ord), '[]'::jsonb)
        from jsonb_array_elements(new.players) with ordinality as x(e, ord)
      );
    end if;
  end if;

  if mirror then
    new.search := array[]::text[];
  end if;
  return new;
end;
$$;

-- Apply to the tours already marked and their games.
update public.tours set players = players
where coalesce(info->>'mirror', '') = 'true';
update public.games g set players = g.players
from public.tours t
where t.id = g.tour_id and coalesce(t.info->>'mirror', '') = 'true';
