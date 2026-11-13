-- Games liked or saved while live catch up when the game ends (Trello #1387).
--
-- A like, or a save to a database, copies the game into
-- `user_saved_analyses.chess_game` as it stands at that moment. For a game
-- still being played that is half a game with `Result "*"`, and nothing ever
-- updated it: on 2026-11-14, 555 saved games (501 likes) still sat frozen at
-- the move they were saved on, every one of them long finished.
--
-- The edge function `finish-live-saved-games` now finishes them. pg_cron
-- starts it every two minutes while there is work; it reads the rows below,
-- adds the moves played after the save (see its `finish.ts`), and writes
-- each one back through `finish_live_saved_game`.
--
-- A row is linked to its broadcast game by `source_game_id` (likes, phone
-- saves) or, failing that, by `chess_game.id` (desktop board saves).
-- `games.status` is the result: `1-0`, `0-1`, `1/2-1/2` or `½-½`, `*` live.
--
-- A relay can post a result early and the moves after it (the ingest reopens
-- such a game). A row the job finished, and the reader has not touched
-- since, is finished again from the copy saved before the job's write
-- whenever its game changes after that write: new moves or another result.
--
-- Additive: one index built without blocking writes, one table, three
-- functions, one cron job. Every row changed keeps its saved `chess_game` in
-- `user_saved_analysis_live_finishes` until the reader deletes the row.

-- Rows still marked unfinished. Few (about 700 before the first run, the
-- games being played afterwards), so the cron's check reads almost nothing.
-- Built concurrently: likes and saves keep writing while it builds. Run this
-- statement on its own, outside a transaction.
create index concurrently if not exists user_saved_analyses_unfinished_game_idx
  on public.user_saved_analyses ((coalesce(source_game_id, chess_game->>'id')))
  where result is null and (chess_game->'md'->>'Result') = '*';

begin;

create table if not exists public.user_saved_analysis_live_finishes (
  analysis_id uuid primary key
    references public.user_saved_analyses(id) on delete cascade,
  game_id text not null,
  -- extended | regrafted | replaced | result_only | skipped (see finish.ts)
  outcome text not null,
  -- The row as the reader saved it, before the job first wrote it.
  -- Restoring it undoes the job; a refinish starts from it again.
  previous_chess_game jsonb not null,
  -- games.live_ply_count when the row was finished (0: not known). A game
  -- that moves on from it is finished again.
  game_plies integer not null default 0,
  finished_at timestamptz not null default now()
);

create index if not exists user_saved_analysis_live_finishes_recent_idx
  on public.user_saved_analysis_live_finishes (finished_at);

alter table public.user_saved_analysis_live_finishes enable row level security;
revoke all on table public.user_saved_analysis_live_finishes
  from public, anon, authenticated;
grant select, insert, update on table public.user_saved_analysis_live_finishes
  to service_role;

-- The rows to finish, oldest change first, with the game to finish each from
-- (`chess_game`: the row itself, or for a refinish the copy saved before the
-- job's write). The game must have been still for five minutes.
--   fresh: still `Result "*"`. One that could not be finished (`skipped`)
--          waits until the reader changes it or its game moves on.
--   again: finished by the job within three days, untouched since, and its
--          game has changed since that write.
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
      and g.status in ('1-0', '0-1', '1/2-1/2', '½-½')
      and g.pgn is not null
      and coalesce(g.live_observed_at, g.last_move_time, 'epoch'::timestamptz)
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
  again as (
    select s.id, s.source_game_id, l.previous_chess_game, s.variation_comments,
           s.move_nags, s.updated_at, g.id, g.pgn, g.status,
           coalesce(g.live_ply_count, 0), true
    from public.user_saved_analysis_live_finishes l
    join public.user_saved_analyses s on s.id = l.analysis_id
    join public.games g on g.id = l.game_id
    where l.finished_at > now() - interval '3 days'
      and l.outcome <> 'skipped'
      and l.finished_at >= s.updated_at
      and g.status in ('1-0', '0-1', '1/2-1/2', '½-½')
      and g.pgn is not null
      and coalesce(g.live_observed_at, g.last_move_time, 'epoch'::timestamptz)
          < now() - interval '5 minutes'
      and (
        coalesce(g.live_ply_count, 0) <> l.game_plies
        or s.result is distinct from (
          case g.status when '1-0' then 'W' when '0-1' then 'B' else 'D' end
        )
      )
  )
  select * from (
    select * from fresh
    union all
    select * from again
  ) candidates
  order by candidates.updated_at
  limit greatest(1, least(coalesce(p_limit, 200), 1000));
$$;

-- Writes one finished row. Only when the row is still the one that was read
-- (same `updated_at`): a reader who saved the game in the meantime keeps
-- their version, and it is read again on the next run. A refinish also needs
-- the row to still be the job's own write. `p_chess_game` null records a row
-- that could not be finished (`skipped`).
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
begin
  if p_outcome not in ('extended', 'regrafted', 'replaced', 'result_only', 'skipped') then
    raise exception 'unknown outcome %', p_outcome;
  end if;
  if (p_outcome = 'skipped') <> (p_chess_game is null) then
    raise exception 'outcome % does not match the game given', p_outcome;
  end if;
  if p_chess_game is not null and (
    jsonb_typeof(p_chess_game->'m') is distinct from 'array'
    or jsonb_typeof(p_chess_game->'md') is distinct from 'object'
    or coalesce(p_chess_game->'md'->>'Result', '') not in ('1-0', '0-1', '1/2-1/2')
  ) then
    raise exception 'not a finished game';
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
  if not coalesce(v_fresh, false) and not exists (
    select 1
    from public.user_saved_analysis_live_finishes l
    where l.analysis_id = p_id
      and l.outcome <> 'skipped'
      and l.finished_at >= p_expected_updated_at
  ) then
    -- Finished by the reader or another app, not by this job: theirs.
    return false;
  end if;

  if p_chess_game is not null then
    update public.user_saved_analyses
    set chess_game = p_chess_game
    where id = p_id;
  end if;

  insert into public.user_saved_analysis_live_finishes
    as l (analysis_id, game_id, outcome, previous_chess_game, game_plies, finished_at)
  values (p_id, p_game_id, p_outcome, v_current, coalesce(p_game_plies, 0), now())
  on conflict (analysis_id) do update
    set game_id = excluded.game_id,
        outcome = excluded.outcome,
        -- A refinish keeps the copy from before the job's first write.
        previous_chess_game = case
          when coalesce(v_fresh, false) then excluded.previous_chess_game
          else l.previous_chess_game
        end,
        game_plies = excluded.game_plies,
        finished_at = excluded.finished_at;
  return true;
end;
$$;

-- Starts the edge function when there is a row to finish, with the
-- dispatcher's stream token (the function's own auth: verify_jwt is off).
create or replace function public.kick_finish_live_saved_games()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_token text;
  v_headers jsonb := jsonb_build_object('Content-Type', 'application/json');
begin
  if not exists (select 1 from public.live_saved_games_to_finish(1)) then
    return;
  end if;

  v_url := public.get_vault_secret('finish_live_saved_games_url');
  if v_url is null or v_url = '' then
    v_url := 'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/finish-live-saved-games';
  end if;

  v_token := public.get_vault_secret('live_dispatch_token');
  if v_token is not null and v_token <> '' then
    v_headers := v_headers || jsonb_build_object('x-stream-token', v_token);
  end if;

  begin
    perform net.http_post(
      url := v_url,
      body := '{}'::jsonb,
      headers := v_headers,
      timeout_milliseconds := 60000
    );
  exception when others then
    null;
  end;
end;
$$;

revoke execute on function public.live_saved_games_to_finish(integer) from public, anon, authenticated;
revoke execute on function public.finish_live_saved_game(uuid, timestamptz, text, text, jsonb, integer) from public, anon, authenticated;
revoke execute on function public.kick_finish_live_saved_games() from public, anon, authenticated;
grant execute on function public.live_saved_games_to_finish(integer) to service_role;
grant execute on function public.finish_live_saved_game(uuid, timestamptz, text, text, jsonb, integer) to service_role;
grant execute on function public.kick_finish_live_saved_games() to service_role;

-- Every two minutes, off the minute the dispatch jobs share. A run with
-- nothing to finish stops at the `exists` above.
select cron.schedule(
  'finish-live-saved-games',
  '1-59/2 * * * *',
  $$select public.kick_finish_live_saved_games()$$
);

commit;
