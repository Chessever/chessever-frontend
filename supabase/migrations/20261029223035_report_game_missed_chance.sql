-- Missed Chance joins the report game stories. The writer's tag allowlist
-- widens; the stored shape stays version 1, so older apps ignore the new tag,
-- and the type filter RPC already accepts any tag. Nothing existing changes.
create or replace function public.store_report_game_classification(
  p_game_id text,
  p_expected_pgn text,
  p_classification jsonb
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  bound jsonb;
  original_row jsonb;
  written_row jsonb;
begin
  if coalesce(btrim(p_game_id), '') = ''
    or coalesce(btrim(p_expected_pgn), '') = ''
    or p_classification is null
    or jsonb_typeof(p_classification) <> 'object'
    or p_classification->>'version' is distinct from '1'
    or jsonb_typeof(p_classification->'tags') is distinct from 'array'
    or length(p_classification::text) > 16384 then
    raise exception 'invalid report game classification';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(p_classification->'tags') t(tag)
    where t.tag is null or t.tag not in ('upside_down', 'comeback', 'one_blunder',
      'great_escape', 'missed_chance', 'domination', 'squeeze', 'deadlock',
      'miniature', 'marathon')
  ) then
    raise exception 'unknown report game classification';
  end if;

  bound := p_classification || jsonb_build_object('pgnHash', md5(p_expected_pgn));
  select to_jsonb(g) into original_row from public.games g
    where g.id = p_game_id
    and g.pgn is not distinct from p_expected_pgn
    and g.status = p_classification->>'result'
    and g.status in ('1-0', '0-1', '1/2-1/2')
    for update;
  if original_row is null then return 'stale'; end if;
  if original_row->'report_game_classification' = bound then return 'unchanged'; end if;

  -- Existing broadcast override triggers also run on metadata updates. Keep
  -- them installed, but roll back this write and all its trigger effects if
  -- any existing field changes. Optional enrichment must only add metadata.
  begin
    update public.games g set report_game_classification = bound
      where g.id = p_game_id;
    select to_jsonb(g) into written_row from public.games g where g.id = p_game_id;
    if (written_row - 'report_game_classification') is distinct from
         (original_row - 'report_game_classification')
       or written_row->'report_game_classification' is distinct from bound then
      raise exception 'classification write changed an existing game field'
        using errcode = 'PGR01';
    end if;
    return 'updated';
  exception when sqlstate 'PGR01' then
    return 'stale';
  end;
end;
$$;

revoke all on function public.store_report_game_classification(text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.store_report_game_classification(text, text, jsonb)
  to service_role;

-- The backfill's --revisit adds Missed Chance to metadata that is already
-- current, keeping every stored story, so it reads only rows bound to their
-- exact PGN and result. A changed PGN never has stale stories re-bound, and
-- the writer's exact-PGN check closes the race after this read.
create or replace function public.report_games_with_current_classification(p_version integer)
returns setof public.games
language sql stable security invoker
as $$
  select g.* from public.games g
  where g.status in ('1-0', '0-1', '1/2-1/2')
    and g.report_game_classification is not null
    and g.report_game_classification->>'version' = p_version::text
    and g.report_game_classification->>'result' = g.status
    and g.report_game_classification->>'pgnHash' = pg_catalog.md5(g.pgn);
$$;
revoke all on function public.report_games_with_current_classification(integer)
  from public, anon, authenticated;
grant execute on function public.report_games_with_current_classification(integer)
  to service_role;

notify pgrst, 'reload schema';
