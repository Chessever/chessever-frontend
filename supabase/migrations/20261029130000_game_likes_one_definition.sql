-- One definition of a like, read by every like count.
--
-- A like is a user_saved_analyses row in that user's liked folder
-- (user_folders.is_liked_games), keyed by the original game in
-- source_game_id and dated by the row's created_at. That rule now lives only
-- in rewarded_private.game_likes:
--   * Discovery > Likes ranks games by the likes inside a window
--     (most_liked_ranking_preview / most_liked_ranking_page, unchanged output);
--   * the board's Like heart shows the game's likes, all of them, from
--     game_like_count.
-- Both need a signed-in caller; signed-out users cannot like.
--
-- The view is private: the rows say who liked what, so only the
-- SECURITY DEFINER functions below read it and they return aggregates.

create or replace view rewarded_private.game_likes as
  select a.source_game_id, a.user_id, a.created_at
  from public.user_saved_analyses a
  join public.user_folders f
    on f.id = a.folder_id
   and f.user_id = a.user_id
   and f.is_liked_games
  where a.source_game_id is not null
    and btrim(a.source_game_id) <> '';

revoke all on rewarded_private.game_likes from public, anon, authenticated;

create or replace function rewarded_private.most_liked_ranking_preview(
  p_from timestamptz, p_to timestamptz, p_limit integer default 20)
returns table(source_game_id text, like_count bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_from is null or p_to is null or p_to <= p_from
      or p_to - p_from > interval '367 days' then return; end if;
  return query
    select l.source_game_id, count(distinct l.user_id)::bigint as likes
    from rewarded_private.game_likes l
    where l.created_at >= p_from and l.created_at < p_to
    group by l.source_game_id
    order by likes desc, l.source_game_id asc
    limit v_limit;
end;
$$;

create or replace function rewarded_private.most_liked_ranking_page(
  p_from timestamptz, p_to timestamptz, p_limit integer default 13,
  p_after_likes bigint default null, p_after_game_id text default null)
returns table(source_game_id text, like_count bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_from is null or p_to is null or p_to <= p_from
      or p_to - p_from > interval '367 days' then return; end if;
  if (p_after_likes is null) <> (p_after_game_id is null) then
    raise exception 'invalid_cursor';
  end if;
  return query
    select ranked.game_id, ranked.likes
    from (
      select l.source_game_id as game_id,
        count(distinct l.user_id)::bigint as likes
      from rewarded_private.game_likes l
      where l.created_at >= p_from and l.created_at < p_to
      group by l.source_game_id
      having count(distinct l.user_id) >= 2
    ) ranked
    where p_after_likes is null or ranked.likes < p_after_likes
      or (ranked.likes = p_after_likes and ranked.game_id > p_after_game_id)
    order by ranked.likes desc, ranked.game_id asc
    limit least(greatest(coalesce(p_limit, 13), 1), 50);
end;
$$;

-- Every like of one game, the caller's included: the server's number, as is.
create or replace function public.game_like_count(p_source_game_id text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select count(distinct l.user_id)::bigint
  from rewarded_private.game_likes l
  where l.source_game_id = btrim(p_source_game_id)
    and auth.uid() is not null;
$$;

revoke all on function public.game_like_count(text) from public, anon;
grant execute on function public.game_like_count(text) to authenticated;
