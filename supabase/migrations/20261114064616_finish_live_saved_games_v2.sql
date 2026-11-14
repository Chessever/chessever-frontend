-- Finishing live-liked games, second pass (after the first run's review).
--
-- 1. A game is still once ITS last move is five minutes old. The first pass
--    read games.live_observed_at first, which the ingest stamps on every poll
--    of the round, so a like on a game that ended early waited until the
--    whole round was over.
-- 2. The cron's check only looks at rows that can link to a broadcast. Local
--    (`local_…`), imported (`imported_…`) and desktop-board (`desktop-…`)
--    analyses never do: about 5,700 rows the first index carried, each read
--    in full every two minutes.
-- 3. "Untouched since the job wrote it" is now the row's chess_game being the
--    job's own write (written_hash), not updated_at: opening a like stamps
--    last_opened_at, which moves updated_at, and must not switch off the
--    refinish of a game whose relay posted its result before its last moves.
-- 4. A row whose saved moves cannot be shown as the game (no move in common,
--    another start) is left as the reader saved it; a refinish that finds
--    that puts the saved copy back (`restored`).
-- 5. live_saved_games_to_reprocess: every row the job finished and nobody has
--    changed since, read again from the copy saved before the job's write.
--    Run by hand once after the merge rules change (body {"reprocess":true}).
--
-- Additive: one column, one index, one function; two functions replaced
-- with the same signatures. On production the index was built
-- `concurrently`, on its own, before this file ran; here it is a no-op there.

create index if not exists user_saved_analyses_unfinished_broadcast_idx
  on public.user_saved_analyses ((coalesce(source_game_id, chess_game->>'id')))
  where result is null
    and (chess_game->'md'->>'Result') = '*'
    and (source_game_id is not null
         or (chess_game->>'id') !~ '^(local|imported|desktop)[_-]');

alter table public.user_saved_analysis_live_finishes
  add column if not exists written_hash text;

-- The 555 rows of the first run, none changed since (checked 2026-11-14).
update public.user_saved_analysis_live_finishes l
set written_hash = md5(s.chess_game::text)
from public.user_saved_analyses s
where s.id = l.analysis_id
  and l.written_hash is null
  and l.outcome in ('extended', 'regrafted', 'replaced', 'result_only')
  and s.updated_at = l.finished_at;

create or replace function public.live_saved_games_to_finish(p_limit integer default 200)
returns table (
  id uuid,
  source_game_id text,
  chess_game jsonb,
  variation_comments jsonb,
  move_nags jsonb,
  updated_at timestamptz,
  game_id text,
  pgn text,
  status text,
  game_plies integer,
  refinish boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with fresh as (
    select s.id, s.source_game_id, s.chess_game, s.variation_comments,
           s.move_nags, s.updated_at, g.id as game_id, g.pgn, g.status,
           coalesce(g.live_ply_count, 0) as game_plies, false as refinish
    from public.user_saved_analyses s
    join public.games g
      on g.id = coalesce(s.source_game_id, s.chess_game->>'id')
    where s.result is null
      and (s.chess_game->'md'->>'Result') = '*'
      and (s.source_game_id is not null
           or (s.chess_game->>'id') !~ '^(local|imported|desktop)[_-]')
      and g.status in ('1-0', '0-1', '1/2-1/2', '½-½')
      and g.pgn is not null
      and coalesce(g.last_move_time, g.live_observed_at, 'epoch'::timestamptz)
          < now() - interval '5 minutes'
      and not exists (
        select 1
        from public.user_saved_analysis_live_finishes l
        where l.analysis_id = s.id
          and l.outcome = 'skipped'
          and l.finished_at >= s.updated_at
          and l.game_plies = coalesce(g.live_ply_count, 0)
      )
  ),
  -- Finished by the job within three days and its game has changed since:
  -- found from the small log first, the row's chess_game read only for them.
  changed as materialized (
    select l.analysis_id, l.previous_chess_game, l.written_hash, g.id as game_id,
           g.pgn, g.status, coalesce(g.live_ply_count, 0) as game_plies
    from public.user_saved_analysis_live_finishes l
    join public.games g on g.id = l.game_id
    join public.user_saved_analyses s on s.id = l.analysis_id
    where l.finished_at > now() - interval '3 days'
      and l.outcome in ('extended', 'regrafted', 'replaced', 'result_only')
      and l.written_hash is not null
      and g.status in ('1-0', '0-1', '1/2-1/2', '½-½')
      and g.pgn is not null
      and coalesce(g.last_move_time, g.live_observed_at, 'epoch'::timestamptz)
          < now() - interval '5 minutes'
      and (
        coalesce(g.live_ply_count, 0) <> l.game_plies
        or s.result is distinct from (
          case g.status when '1-0' then 'W' when '0-1' then 'B' else 'D' end
        )
      )
  ),
  again as (
    select s.id, s.source_game_id, c.previous_chess_game, s.variation_comments,
           s.move_nags, s.updated_at, c.game_id, c.pgn, c.status, c.game_plies,
           true
    from changed c
    join public.user_saved_analyses s on s.id = c.analysis_id
    where md5(s.chess_game::text) = c.written_hash
  )
  select * from (
    select * from fresh
    union all
    select * from again
  ) candidates
  order by candidates.updated_at
  limit greatest(1, least(coalesce(p_limit, 200), 1000));
$$;

-- Every row the job finished and nobody has changed since, with the copy
-- saved before the job's write, to be finished again under new merge rules.
create or replace function public.live_saved_games_to_reprocess(p_limit integer default 200)
returns table (
  id uuid,
  source_game_id text,
  chess_game jsonb,
  variation_comments jsonb,
  move_nags jsonb,
  updated_at timestamptz,
  game_id text,
  pgn text,
  status text,
  game_plies integer,
  refinish boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.source_game_id, l.previous_chess_game, s.variation_comments,
         s.move_nags, s.updated_at, g.id, g.pgn, g.status,
         coalesce(g.live_ply_count, 0), true
  from public.user_saved_analysis_live_finishes l
  join public.user_saved_analyses s on s.id = l.analysis_id
  join public.games g on g.id = l.game_id
  where l.outcome in ('extended', 'regrafted', 'replaced', 'result_only')
    and l.written_hash = md5(s.chess_game::text)
    and g.status in ('1-0', '0-1', '1/2-1/2', '½-½')
    and g.pgn is not null
  order by l.finished_at
  limit greatest(1, least(coalesce(p_limit, 200), 1000));
$$;

-- Writes one row. Only when the row is still the one that was read (same
-- updated_at). A refinish (the row no longer `Result "*"`) also needs the
-- row's chess_game to be the job's own last write; one the reader or an app
-- changed is theirs, and the job lets go of it (`released`).
--   extended | regrafted | replaced | result_only: p_chess_game is the
--     finished game, written.
--   skipped: nothing written. A fresh row waits until it or its game changes;
--     a refinish keeps the job's earlier write.
--   restored: a refinish whose saved moves cannot be shown as the game;
--     p_chess_game is the copy saved before the job's write, put back.
create or replace function public.finish_live_saved_game(
  p_id uuid,
  p_expected_updated_at timestamptz,
  p_game_id text,
  p_outcome text,
  p_chess_game jsonb,
  p_game_plies integer default 0
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current jsonb;
  v_fresh boolean;
  v_finished boolean := p_outcome in ('extended', 'regrafted', 'replaced', 'result_only');
begin
  if not v_finished and p_outcome not in ('skipped', 'restored') then
    raise exception 'unknown outcome %', p_outcome;
  end if;
  if (p_outcome = 'skipped') <> (p_chess_game is null) then
    raise exception 'outcome % does not match the game given', p_outcome;
  end if;
  if p_chess_game is not null and (
    jsonb_typeof(p_chess_game->'m') is distinct from 'array'
    or jsonb_typeof(p_chess_game->'md') is distinct from 'object'
  ) then
    raise exception 'not a saved game';
  end if;
  if v_finished
     and coalesce(p_chess_game->'md'->>'Result', '') not in ('1-0', '0-1', '1/2-1/2') then
    raise exception 'not a finished game';
  end if;
  if p_outcome = 'restored'
     and coalesce(p_chess_game->'md'->>'Result', '') <> '*' then
    raise exception 'not a saved live game';
  end if;

  select s.chess_game, (s.chess_game->'md'->>'Result') = '*'
    into v_current, v_fresh
  from public.user_saved_analyses s
  where s.id = p_id
    and s.updated_at = p_expected_updated_at
  for update;
  if not found then
    return false;
  end if;
  v_fresh := coalesce(v_fresh, false);

  if not v_fresh then
    if not exists (
      select 1
      from public.user_saved_analysis_live_finishes l
      where l.analysis_id = p_id
        and l.outcome in ('extended', 'regrafted', 'replaced', 'result_only')
        and l.written_hash = md5(v_current::text)
    ) then
      update public.user_saved_analysis_live_finishes
      set outcome = 'released'
      where analysis_id = p_id
        and outcome in ('extended', 'regrafted', 'replaced', 'result_only');
      return false;
    end if;
  elsif p_outcome = 'restored' then
    -- Only a row the job finished is ever put back.
    return false;
  end if;

  if p_outcome = 'skipped' and not v_fresh then
    -- Keep the earlier write; wait for the game to change again.
    update public.user_saved_analysis_live_finishes
    set game_plies = coalesce(p_game_plies, 0)
    where analysis_id = p_id;
    return true;
  end if;

  -- An identical game is not written again: the row, its updated_at and
  -- every app's copy stay as they are when a run is repeated.
  if p_chess_game is not null and p_chess_game is distinct from v_current then
    update public.user_saved_analyses
    set chess_game = p_chess_game
    where id = p_id;
  end if;

  insert into public.user_saved_analysis_live_finishes
    as l (analysis_id, game_id, outcome, previous_chess_game, game_plies,
          written_hash, finished_at)
  values (
    p_id, p_game_id,
    case when p_outcome = 'restored' then 'skipped' else p_outcome end,
    v_current, coalesce(p_game_plies, 0),
    case when v_finished then md5(p_chess_game::text) end,
    now()
  )
  on conflict (analysis_id) do update
    set game_id = excluded.game_id,
        outcome = excluded.outcome,
        -- A refinish keeps the copy from before the job's first write.
        previous_chess_game = case
          when v_fresh then excluded.previous_chess_game
          else l.previous_chess_game
        end,
        game_plies = excluded.game_plies,
        written_hash = excluded.written_hash,
        finished_at = excluded.finished_at;
  return true;
end;
$$;

revoke execute on function public.live_saved_games_to_reprocess(integer) from public, anon, authenticated;
grant execute on function public.live_saved_games_to_reprocess(integer) to service_role;
