-- Additive API: older app versions keep using the capped preview function.
create or replace function rewarded_private.most_liked_ranking_page(
  p_from timestamptz, p_to timestamptz, p_limit integer default 13,
  p_after_likes bigint default null, p_after_game_id text default null
)
returns table(source_game_id text, like_count bigint)
language plpgsql stable security definer set search_path = '' as $$
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
      select a.source_game_id as game_id,
        count(distinct a.user_id)::bigint as likes
      from public.user_saved_analyses a
      join public.user_folders f on f.id = a.folder_id
        and f.user_id = a.user_id and f.is_liked_games
      where a.source_game_id is not null and btrim(a.source_game_id) <> ''
        and a.created_at >= p_from and a.created_at < p_to
      group by a.source_game_id
      having count(distinct a.user_id) >= 2
    ) ranked
    where p_after_likes is null or ranked.likes < p_after_likes
      or (ranked.likes = p_after_likes and ranked.game_id > p_after_game_id)
    order by ranked.likes desc, ranked.game_id asc
    limit least(greatest(coalesce(p_limit, 13), 1), 50);
end;
$$;
revoke all on function rewarded_private.most_liked_ranking_page(timestamptz,timestamptz,integer,bigint,text) from public, anon;
grant execute on function rewarded_private.most_liked_ranking_page(timestamptz,timestamptz,integer,bigint,text) to authenticated;

create or replace function public.most_liked_ranking_page(
  p_from timestamptz, p_to timestamptz, p_limit integer default 13,
  p_after_likes bigint default null, p_after_game_id text default null
)
returns table(source_game_id text, like_count bigint)
language sql stable security invoker set search_path = '' as $$
  select * from rewarded_private.most_liked_ranking_page(
    p_from,p_to,p_limit,p_after_likes,p_after_game_id);
$$;
revoke all on function public.most_liked_ranking_page(timestamptz,timestamptz,integer,bigint,text) from public, anon;
grant execute on function public.most_liked_ranking_page(timestamptz,timestamptz,integer,bigint,text) to authenticated;
