-- Ranking previews are browsable; opening non-Today games is gated in the app.
-- Only aggregate game IDs/counts leave storage. Paid/session authorization RPCs
-- and personal saved analyses remain unchanged.
create or replace function rewarded_private.most_liked_ranking_preview(
  p_from timestamptz, p_to timestamptz, p_limit integer default 20
)
returns table(source_game_id text, like_count bigint)
language plpgsql stable security definer set search_path = '' as $$
declare v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_from is null or p_to is null or p_to <= p_from
      or p_to - p_from > interval '367 days' then return; end if;
  return query
    select ranked.game_id, ranked.likes
    from (
      select a.source_game_id as game_id,
        count(distinct a.user_id)::bigint as likes
      from public.user_saved_analyses a
      join public.user_folders f on f.id = a.folder_id
        and f.user_id = a.user_id and f.is_liked_games
      where a.source_game_id is not null and btrim(a.source_game_id) <> ''
        and a.created_at >= p_from and a.created_at < p_to
      group by a.source_game_id
    ) ranked
    order by ranked.likes desc, ranked.game_id asc limit v_limit;
end;
$$;
revoke all on function rewarded_private.most_liked_ranking_preview(timestamptz,timestamptz,integer) from public, anon;
grant execute on function rewarded_private.most_liked_ranking_preview(timestamptz,timestamptz,integer) to authenticated;

create or replace function public.most_liked_ranking_preview(
  p_from timestamptz, p_to timestamptz, p_limit integer default 20
)
returns table(source_game_id text, like_count bigint)
language sql stable security invoker set search_path = '' as $$
  select * from rewarded_private.most_liked_ranking_preview(p_from,p_to,p_limit);
$$;
revoke all on function public.most_liked_ranking_preview(timestamptz,timestamptz,integer) from public, anon;
grant execute on function public.most_liked_ranking_preview(timestamptz,timestamptz,integer) to authenticated;
