-- tours.info is free-form JSON written by the data hub, the admin web and
-- ad-hoc scripts. Installed apps read the keys below as strings, and before
-- 36.10.1 a single non-string value threw and left the whole event on an
-- endless loading shimmer (2026-10-16: `info.players` stored as the number
-- 171 on the Russian Rapid/Blitz Championship tours).
--
-- This trigger normalizes those keys on every write so no writer can break
-- the clients again: numbers/booleans become their text, arrays of scalars
-- become a ", "-joined string, and objects are dropped.

create or replace function public.tours_normalize_info_text()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  k text;
  v jsonb;
begin
  if new.info is null then
    return new;
  end if;

  if jsonb_typeof(new.info) <> 'object' then
    new.info := '{}'::jsonb;
    return new;
  end if;

  foreach k in array array[
    'tc', 'fideTc', 'format', 'players', 'website', 'location',
    'timeZone', 'standings', 'standingsSource'
  ] loop
    v := new.info -> k;
    if v is null then
      continue;
    end if;

    case jsonb_typeof(v)
      when 'string', 'null' then
        null;
      when 'number', 'boolean' then
        new.info := jsonb_set(new.info, array[k], to_jsonb(v #>> '{}'));
      when 'array' then
        new.info := jsonb_set(
          new.info,
          array[k],
          to_jsonb(coalesce((
            select string_agg(e #>> '{}', ', ' order by ord)
            from jsonb_array_elements(v) with ordinality as t(e, ord)
            where jsonb_typeof(e) in ('string', 'number')
          ), ''))
        );
      else
        new.info := new.info - k;
    end case;
  end loop;

  return new;
end;
$$;

drop trigger if exists tours_normalize_info_text on public.tours;
create trigger tours_normalize_info_text
  before insert or update of info on public.tours
  for each row execute function public.tours_normalize_info_text();
