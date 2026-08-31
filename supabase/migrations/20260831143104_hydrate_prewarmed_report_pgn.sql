-- Atomically persist the annotated PGN returned by the hourly report
-- prewarmer. The expected-PGN comparison is the concurrency boundary: a
-- delayed analysis must never overwrite a newer broadcast snapshot.

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

  if current_pgn = p_hydrated_pgn then
    return 'already_hydrated';
  end if;

  update public.games g
  set pgn = p_hydrated_pgn
  where g.id = p_game_id
    and g.pgn is not distinct from p_expected_pgn
    and public.is_game_finished(g.status);

  if found then
    return 'updated';
  end if;

  return 'stale';
end;
$$;

comment on function public.store_prewarmed_report_pgn(text, text, text) is
  'Stores an engine-annotated PGN only when the finished game still carries the exact PGN that was analyzed.';

revoke all on function public.store_prewarmed_report_pgn(text, text, text)
  from public, anon, authenticated;
grant execute on function public.store_prewarmed_report_pgn(text, text, text)
  to service_role;
