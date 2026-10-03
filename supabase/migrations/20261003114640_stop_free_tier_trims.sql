-- Stop deleting a lapsed subscriber's data.
--
-- 20260511120000_free_tier_trim_rpcs.sql had the RevenueCat webhook call these
-- two functions on EXPIRATION: followed players were cut to the top 3 and
-- saved games to the newest 10 across every folder, My Likes included, as
-- hard deletes. Free accounts now get the same app with ads, so nothing is
-- taken away when a subscription ends. The free limits still apply to NEW
-- follows and saves, in the client guards.
--
-- Both functions keep their signature and grants and become no-ops, so every
-- caller (the deployed webhook included) stops deleting at once, without a
-- redeploy. Rows trimmed before this ran are not restored by it.

create or replace function public.trim_favorite_players_to_top_n(
  p_user_id uuid,
  p_keep    int
) returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  return 0;
end;
$$;

create or replace function public.trim_saved_analyses_to_recent_n(
  p_user_id uuid,
  p_keep    int
) returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  return 0;
end;
$$;
