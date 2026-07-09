-- Daniel Naroditsky appears in games.players with FIDE id 2026961, but the
-- chess_players search source was missing his row. Keep this idempotent so it
-- can run after the production hotfix as well as on fresh databases.
insert into public.chess_players (
  fideid,
  name,
  country,
  sex,
  title,
  rating,
  rapid_rating,
  blitz_rating,
  birthday,
  inserted_at,
  updated_at
)
values (
  2026961,
  'Naroditsky, Daniel',
  'USA',
  'M',
  'GM',
  2711,
  2711,
  2711,
  1995,
  now(),
  now()
)
on conflict (fideid) do update
set
  name = excluded.name,
  country = excluded.country,
  sex = excluded.sex,
  title = excluded.title,
  rating = excluded.rating,
  rapid_rating = excluded.rapid_rating,
  blitz_rating = excluded.blitz_rating,
  birthday = excluded.birthday,
  updated_at = now();

create or replace function public.search_chess_players(search_query text, max_results integer default 25)
returns table(fideid bigint, name text, title text, rating integer, country text)
language plpgsql
stable
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  q text;
  toks text[];
  anchor text;
  cap integer := greatest(1, least(coalesce(max_results, 25), 100));
  pool_size integer;
begin
  q := lower(trim(regexp_replace(coalesce(search_query, ''), '[,\.]+', ' ', 'g')));

  select array_agg(distinct tok) into toks
  from regexp_split_to_table(q, '\s+') as tok
  where length(tok) >= 2;

  if toks is null then return; end if;

  select tok into anchor
  from unnest(toks) as tok
  order by length(tok) desc
  limit 1;

  pool_size := greatest(cap * 3, 75);

  if length(anchor) <= 3 then
    return query
    with pool as (
      select cp.fideid, cp.name, cp.title, cp.rating, cp.country::text as country
      from chess_players cp
      where lower(cp.name) like anchor || '%'
        and cp.name ilike all (select '%' || t.tok || '%' from unnest(toks) as t(tok))
        and (cp.rating < 3300 or cp.rating is null)
      order by cp.rating desc nulls last
      limit pool_size
    )
    select p.fideid, p.name, p.title, p.rating, p.country
    from pool p
    order by
      case when lower(p.name) = q then 0
           when lower(p.name) like q || '%' then 1
           else 2 end,
      p.rating desc nulls last
    limit cap;
    return;
  end if;

  return query
  with pool as (
    select cp.fideid, cp.name, cp.title, cp.rating, cp.country::text as country
    from chess_players cp
    where cp.name ilike '%' || anchor || '%'
      and cp.name ilike all (select '%' || t.tok || '%' from unnest(toks) as t(tok))
      and (cp.rating < 3300 or cp.rating is null)
    order by cp.rating desc nulls last
    limit pool_size
  )
  select p.fideid, p.name, p.title, p.rating, p.country
  from pool p
  order by
    case when lower(p.name) = q then 0
         when lower(p.name) like q || '%' then 1
         else 2 end,
    p.rating desc nulls last,
    similarity(lower(p.name), q) desc
  limit cap;

  if found then return; end if;

  if length(q) >= 3 then
    return query
    select cp.fideid, cp.name, cp.title, cp.rating, cp.country::text
    from chess_players cp
    where cp.name % q
      and (cp.rating < 3300 or cp.rating is null)
    order by similarity(cp.name, q) desc, cp.rating desc nulls last
    limit cap;
  end if;
end;
$function$;
