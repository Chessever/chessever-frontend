-- Guardrail: prevent unbounded growth of user_live_game_subscriptions.
-- Disabled subscriptions have NO runtime function (the live-activity-refresh edge
-- fn only ever selects enabled=true) — they are dead history rows. Reap disabled
-- rows untouched for 7+ days. ENABLED rows are NEVER deleted, so an active Live
-- Activity can't be dropped. Enabled rows self-clean via the edge fn (game-over /
-- 3h-stale / 404 user-dismiss / missing-game all set enabled=false), so this only
-- trims dead history. Applied to prod 2026-06-07 (cron job 'cleanup-live-game-subscriptions', every 6h).
create or replace function public.cleanup_live_game_subscriptions()
returns void
language sql
as $$
  delete from public.user_live_game_subscriptions
  where enabled = false
    and last_event_at is not null
    and last_event_at < now() - interval '7 days';
$$;

select cron.schedule(
  'cleanup-live-game-subscriptions',
  '23 */6 * * *',
  $$select public.cleanup_live_game_subscriptions();$$
);
