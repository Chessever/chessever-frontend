-- LOCAL ONLY. Account preference used by the shared game/event delivery service.
-- Apply together with the publication migration before activating News fanout.
begin;
alter table public.user_notification_preferences
 add column favorite_player_news_alerts boolean not null default true,
 add column favorite_player_news_enabled_at timestamptz not null default now();

-- The enabled timestamp is server-owned. An opt-out/re-enable cannot replay old
-- publications; ordinary game/event preference saves do not move the boundary.
create function public.stamp_favorite_player_news_preference() returns trigger
language plpgsql set search_path='' as $$
begin
 if TG_OP='INSERT' then
  new.favorite_player_news_enabled_at=clock_timestamp();
 elsif new.favorite_player_news_alerts and not old.favorite_player_news_alerts then
  new.favorite_player_news_enabled_at=clock_timestamp();
 else
  new.favorite_player_news_enabled_at=old.favorite_player_news_enabled_at;
 end if;
 return new;
end $$;
revoke all on function public.stamp_favorite_player_news_preference() from public,anon,authenticated;
create trigger stamp_favorite_player_news_preference
 before insert or update on public.user_notification_preferences
 for each row execute function public.stamp_favorite_player_news_preference();
-- Existing ownership RLS and grants on user_notification_preferences apply.
commit;
