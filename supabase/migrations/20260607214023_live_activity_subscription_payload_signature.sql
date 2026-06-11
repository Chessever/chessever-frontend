-- Track the last Live Activity / live-notification content state that was
-- actually sent. `last_event_at` is a wall-clock freshness/check timestamp;
-- it must not be used as the move identity because broadcast `last_move_time`
-- can lag behind server time or stay unchanged while FEN changes.
alter table public.user_live_game_subscriptions
  add column if not exists last_payload_signature text;
