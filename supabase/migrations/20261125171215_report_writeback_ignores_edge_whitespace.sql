-- Report writeback ignored every game whose stored PGN ended in a newline.
--
-- The analysis Worker trims a game's PGN before analysing it, and sends that
-- trimmed text back as `p_expected_pgn`. The guard below compared it to the
-- stored PGN byte for byte, so a game stored as "... 1/2-1/2\n" never matched:
-- the report was produced, cached and served, and the writeback answered
-- 'stale' on every attempt, forever. In the 14 days before this fix 5,564
-- finished games had such a PGN and not one of them carried a report,
-- including the World Championship games.
--
-- Whitespace at either end is not a different snapshot of the game, so it is
-- ignored on both sides. Anything inside the text still has to match exactly,
-- which keeps the guard's purpose: a delayed analysis never overwrites a newer
-- broadcast snapshot.

create or replace function public.store_prewarmed_report_pgn(
  p_game_id text,
  p_expected_pgn text,
  p_hydrated_pgn text
)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_pgn text;
  current_status text;
begin
  if coalesce(btrim(p_game_id), '') = ''
    or coalesce(btrim(p_expected_pgn), '') = ''
    or coalesce(btrim(p_hydrated_pgn), '') = '' then
    raise exception 'game id and both PGNs are required';
  end if;

  select g.pgn, g.status
    into current_pgn, current_status
  from public.games g
  where g.id = p_game_id;

  if not found then
    return 'missing';
  end if;

  if not public.is_game_finished(current_status) then
    return 'not_finished';
  end if;

  if btrim(current_pgn, E' \t\r\n') = btrim(p_hydrated_pgn, E' \t\r\n') then
    return 'already_hydrated';
  end if;

  update public.games g
  set pgn = p_hydrated_pgn
  where g.id = p_game_id
    and btrim(g.pgn, E' \t\r\n') = btrim(p_expected_pgn, E' \t\r\n')
    and public.is_game_finished(g.status);

  if found then
    return 'updated';
  end if;

  return 'stale';
end;
$$;

comment on function public.store_prewarmed_report_pgn(text, text, text) is
  'Stores an engine-annotated PGN only when the finished game still carries the PGN that was analyzed, ignoring whitespace at either end.';

revoke all on function public.store_prewarmed_report_pgn(text, text, text)
  from public, anon, authenticated;
grant execute on function public.store_prewarmed_report_pgn(text, text, text)
  to service_role;
