# Push Notifications (OneSignal + Supabase)

This document describes the current push notification pipeline for ChessEver and the operational steps to enable live updates.

## Overview

- **Client:** OneSignal Flutter SDK (`onesignal_flutter`) with external user ID set to Supabase `auth.users.id`.
- **Server:** Supabase `notification_outbox` table + `onesignal-dispatch` Edge Function.
- **Triggers:** DB triggers and scheduled functions enqueue rows into `notification_outbox`.

## Environment Variables

Add to your Flutter build (see `CODEMAGIC_DART_DEFINES.txt`):

- `ONESIGNAL_APP_ID`

Configure these secrets in Supabase Edge Functions:

- `ONESIGNAL_APP_ID`
- `ONESIGNAL_REST_API_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

## OneSignal Dashboard Setup

1. Create a OneSignal app.
2. **Android:** configure Firebase (FCM) credentials for the app.
3. **iOS:** upload APNs `.p8` key (required for Live Activities later).

## Supabase: Notifications Pipeline

### Tables

- `user_notification_preferences`: user opt-in + preferences.
- `user_push_tokens`: device subscription IDs + tokens for OneSignal (kept current).
- `user_live_game_subscriptions`: per-game opt-ins for Live Activities / Android live notifications.
- `notification_outbox`: server-side queue for notification dispatch.

### Triggers

The following DB triggers/functions are included in
`supabase/migrations/012_notifications_prefs_and_outbox.sql`:

- `queue_game_notifications`: enqueue `game_started` and `game_finished`.
- `queue_round_start_notifications()`: enqueue `round_started` (2-hour rate limit per event).
- `queue_round_heads_up_notifications()`: enqueue `round_heads_up` (opt-in, 30 min lead).
- `queue_live_game_updates()`: enqueue `live_game_update` (call via cron).

### Edge Function

`supabase/functions/onesignal-dispatch/index.ts`

This function:

1. Pulls `pending` rows from `notification_outbox`.
2. Resolves recipients using `user_favorite_events` and `user_favorite_players`.
3. Filters using `user_notification_preferences`.
4. Sends notifications via OneSignal (player favorites vs event favorites for rounds and heads-up).
   - Android channels (IDs):
     - `fav_updates` for `round_started`, `game_started`, `game_finished`
     - `heads_up` for `round_heads_up`
     - `live_updates` for `live_game_update`
     - `general` fallback
5. Marks rows as `sent`, `skipped`, or `failed`.

## Live Updates (Per-Game)

Live Activities / Android Live Notifications are opt-in per game:

- Client upserts `user_live_game_subscriptions` with `game_id` + `platform`.
- `onesignal-dispatch` uses these rows to send:
  - iOS Live Activity updates (OneSignal Live Activities API).
  - Android Live Notifications (collapse_id + `live_notification` payload).

Deploy the function and call it on a schedule.

## Scheduling (Cron)

Recommended cadence:

- `queue_round_start_notifications()` every 5 minutes (window is 10 minutes).
- `queue_round_heads_up_notifications()` every 5 minutes (window is 20–40 minutes ahead).
- `queue_live_game_updates()` every 1–2 minutes (for live game updates).
- `onesignal-dispatch` every 1 minute (or faster if needed).

You can schedule via Supabase Scheduled Functions or `pg_cron`.

## Live Activities / Live Notifications (Future)

Now supported (requires native wiring):

- **iOS Live Activities:** ActivityKit + Widget extension + OneSignal Live Activities updates.
- **Android Live Notifications:** Notification Service Extension + `live_notification` payloads.

See `ios/ChessEverLiveActivity/` and `android/app/src/main/kotlin/com/chessEver/app/NotificationServiceExtension.kt`.
