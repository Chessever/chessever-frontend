-- Most Liked (For You > Discovery): community like counts per game.
--
-- A like is a user_saved_analyses row inside that user's special liked
-- folder (user_folders.is_liked_games = true), keyed by the original game in
-- source_game_id. Those rows are private (RLS: own rows only), so the ranking
-- is computed here as SECURITY DEFINER and only the aggregate leaves the
-- database: a game id and how many distinct users liked it inside the
-- window. No user ids, folder ids, names, notes, tags or PGNs are returned.
--
-- Ranking: like_count desc, then source_game_id asc. The id tie-break is
-- deterministic, so two games with equal counts never swap places between
-- reads.
--
-- Window: [p_from, p_to). The current day is free: a window of at most 26
-- hours (one local calendar day plus a DST hour, with slack) starting no
-- earlier than 26 hours ago. Longer or older windows (Week, Month, Year,
-- earlier days) are Premium and raise 'premium_required' (SQLSTATE P0001)
-- for everyone else, anon included. Premium is read from
-- public._user_has_premium, the same authority the analysis-report quota
-- uses (20260723120000_game_analysis_report_daily_quota.sql). plpgsql keeps
-- that reference late-bound, so creating this function never depends on it.
--
-- Additive only: one function and its grants. Nothing is
-- dropped, rewritten or backfilled.
--
-- Zero-impact rollout: this file creates NO index, so applying it never takes
-- a lock on user_saved_analyses and no like/save write waits on it. The
-- supporting index lives in supabase/manual/20260923100001_most_liked_index_concurrently.sql
-- and is built with CREATE INDEX CONCURRENTLY (outside a transaction, no
-- write lock). The function is correct without it, only slower.

create or replace function public.most_liked_games(
  p_from timestamptz,
  p_to timestamptz,
  p_limit integer default 20
)
returns table (
  source_game_id text,
  like_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if p_from is null or p_to is null or p_to <= p_from then
    return;
  end if;

  if (p_to - p_from > interval '26 hours'
      or p_from < now() - interval '26 hours')
    and not coalesce(public._user_has_premium(auth.uid()), false) then
    raise exception 'premium_required'
      using errcode = 'P0001',
            hint = 'Most Liked beyond the current day is a Premium ranking.';
  end if;

  return query
    select ranked.game_id, ranked.likes
    from (
      select
        a.source_game_id as game_id,
        count(distinct a.user_id)::bigint as likes
      from public.user_saved_analyses a
      join public.user_folders f
        on f.id = a.folder_id
       and f.user_id = a.user_id
       and f.is_liked_games
      where a.source_game_id is not null
        and btrim(a.source_game_id) <> ''
        and a.created_at >= p_from
        and a.created_at < p_to
      group by a.source_game_id
    ) ranked
    order by ranked.likes desc, ranked.game_id asc
    limit v_limit;
end;
$$;

comment on function public.most_liked_games(timestamptz, timestamptz, integer) is
  'Community Most Liked ranking: distinct users who liked each game in [p_from, p_to), like_count desc then source_game_id asc. Aggregates only. Windows beyond the current day require Premium.';

revoke all on function public.most_liked_games(timestamptz, timestamptz, integer)
  from public;
grant execute on function public.most_liked_games(timestamptz, timestamptz, integer)
  to anon, authenticated;
