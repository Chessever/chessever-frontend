-- The first --revisit reader filtered on md5(pgn): with ~33k classified games
-- in 1.3M, every page hashed every classified PGN and timed out. This one
-- pages the primary key itself and hashes only the page it returns. A row
-- that is not current comes back with current = false, so the caller still
-- advances its cursor past it and never adds a story to stale metadata.
-- Additive only: the earlier reader stays in place, unused.
create or replace function public.report_game_classification_page(
  p_version integer,
  p_after text default '',
  p_limit integer default 100
)
returns table (
  id text,
  pgn text,
  status text,
  report_game_classification jsonb,
  current boolean
)
language sql stable security invoker
set search_path = ''
as $$
  select c.id, c.pgn, c.status, c.report_game_classification,
    coalesce(c.report_game_classification->>'version' = p_version::text
      and c.report_game_classification->>'result' = c.status
      and c.report_game_classification->>'pgnHash' = pg_catalog.md5(c.pgn), false)
  from (
    -- The LIMIT keeps this subquery apart, so the hash runs on one page only.
    select g.id, g.pgn, g.status, g.report_game_classification
    from public.games g
    where g.id > coalesce(p_after, '')
      and g.report_game_classification is not null
      and g.status in ('1-0', '0-1', '1/2-1/2')
    order by g.id
    limit least(greatest(coalesce(p_limit, 100), 1), 500)
  ) c
  order by c.id;
$$;

revoke all on function public.report_game_classification_page(integer, text, integer)
  from public, anon, authenticated;
grant execute on function public.report_game_classification_page(integer, text, integer)
  to service_role;

notify pgrst, 'reload schema';
