# Push Notifications (OneSignal + Supabase)

This document describes the current push notification pipeline for ChessEver and the operational steps to enable live updates.

## Overview

- **Client:** OneSignal Flutter SDK (`onesignal_flutter`) with external user ID set to Supabase `auth.users.id`.
- **Server:** Supabase `notification_outbox` table + `onesignal-dispatch` Edge Function.
- **Dispatch:** Trigger-based immediate dispatch via `pg_net` + 1-minute fallback heartbeat cron.

## Environment Variables

Add to your Flutter build (see `CODEMAGIC_DART_DEFINES.txt`):

- `ONESIGNAL_APP_ID`

Configure these secrets in Supabase Edge Functions:

- `ONESIGNAL_APP_ID`
- `ONESIGNAL_REST_API_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

Vault secrets (Supabase DB):

- `live_dispatch_url`: Edge Function URL for dispatch.
- `live_dispatch_token`: Shared secret for `x-stream-token` auth.

## OneSignal Dashboard Setup

1. Create a OneSignal app.
2. **Android:** configure Firebase (FCM) credentials for the app.
3. **iOS:** upload APNs `.p8` key (required for Live Activities).
4. **Android channels:** create the following channel IDs in OneSignal dashboard:
   - `fav_updates` — favorites: `round_started`, `round_finished`, `game_started`, `game_finished`
   - `heads_up` — heads-up alerts: `round_heads_up`
   - `live_updates` — live game updates: `live_game_update`
   - `live_alerts` — live game milestone alerts
   - `call_to_action` — chess world updates
  - `general` — fallback (database activity, etc.)

## Supabase: Notifications Pipeline

### Tables

- `user_notification_preferences`: user opt-in + per-category preferences.
- `user_push_tokens`: device subscription IDs + tokens for OneSignal (kept current).
- `user_live_game_subscriptions`: per-game opt-ins for Live Activities / Android live notifications.
- `notification_outbox`: server-side queue for notification dispatch.
- `notification_user_windows`: start-family cooldown state (service-role only).

### Enqueue Triggers & Functions

- `queue_game_notifications` (trigger on `games`): enqueues `game_started` and `game_finished` on game state transitions. Includes `board_nr` in payload. Also handles round-level events via its internal `round_started` and `round_finished` branches: it piggybacks `round_started` when a game goes live and has a `round_id` (catches rounds missed by cron), and enqueues `round_finished` when the last game in a round finishes (embeds the full results array in the payload and uses dedupe key `round_finished:{round_id}` to handle simultaneous last-game finishes).
- `queue_round_start_notifications()` (cron): enqueues `round_started` for rounds within 10-min window.
- `queue_round_heads_up_notifications()` (cron): enqueues `round_heads_up` for rounds 25-45 min away.
- `queue_live_game_updates()` (cron/trigger): enqueues `live_game_update` for active games.

### Dispatch Triggers

Two `AFTER INSERT` triggers on `notification_outbox` provide immediate dispatch:

- `dispatch_live_game_update_outbox`: fires for `live_game_update` events only, calls the Edge Function via `pg_net`.
- `dispatch_notification_outbox`: fires for all other event types, calls the Edge Function via `pg_net`.

Both use named parameters for `net.http_post` and authenticate with `x-stream-token` from Vault.

### Fallback Heartbeat

`dispatch_pending_heartbeat()` runs every 1 minute via `pg_cron`. It checks for any pending outbox rows and calls the Edge Function if items exist. This ensures trigger failures degrade to bounded delay (~60s worst case) instead of silent backlog growth.

### Queue Claiming & Priority

`claim_notification_outbox_batch()` atomically claims pending rows with priority ordering:

1. **Priority 0:** `game_started`, `game_finished` (immediate per-game events)
2. **Priority 1:** `round_started`, `round_heads_up`, `round_finished` (round-level events)
3. **Priority 2:** `book_game_added`, `book_game_updated`, `book_game_removed`
4. **Priority 3:** `call_to_action`, other
5. **Priority 4:** `live_game_update` (high-volume, separate pipeline)

This ensures game-level notifications are processed within SLA even under high `live_game_update` volume.

### Start-Family Precedence (Bidirectional Cooldown)

A 900-second (15-minute) cooldown window is recorded in `notification_user_windows` after either `game_started` or `round_started` is sent to a player-favourite user. Whichever fires first wins; the other is suppressed for that user+round combination during the window.

- **`game_started`**: only sent to users with **exactly 1** favourite in the round (Scenario A). Users with 2+ favourites skip `game_started` and receive a combined `round_started` instead.
- **`round_started`** (player channel): sends combined messages — Scenario B (2 favs: "Carlsen & Caruana are live") or Scenario C (3+: "Carlsen, Caruana & 1 more are live"). Also records the cooldown window so any later `game_started` in the same batch is suppressed.
- Only applies to player-favourite users; event-starred users always get round-level notifications.
- Cooldown windows are cleaned up every 10 minutes by `cleanup_notification_user_windows()`.

### Edge Function

`supabase/functions/onesignal-dispatch/index.ts`

This function:

1. Claims `pending` rows from `notification_outbox` via `claim_notification_outbox_batch()`.
2. Resolves recipients using `user_favorite_events` and `user_favorite_players`.
3. Filters using `user_notification_preferences`.
4. For `game_started`: only player-favourite users with **exactly 1** favourite in the round (Scenario A). Multi-favourite users receive `round_started` instead.
5. For `game_finished`: single "White vs Black: result" push to all player-favourite recipients.
6. For `round_started`: player-favourite users get per-user combined messages (Scenarios A/B/C); event-starred users get a pairings digest ("Carlsen–Nepo · Caruana–Giri +4 more").
7. For `round_heads_up`: same Scenario A/B/C per-user messages for player-favourites; event template for event-starred.
8. For `round_finished`: results digest for event-starred users only ("Carlsen 1-0 · Caruana ½-½ +3").
9. Sends regular notifications via OneSignal by expanding each user to every active `user_push_tokens` subscription ID, so a signed-in user receives pushes on all synced devices. Users without synced token rows fall back to OneSignal `external_id` targeting.
10. All round/event data payloads include `tour_id`, `round_id`, and `group_broadcast_id` for deep-link routing.
11. Database activity payloads include `folder_id` and a deep-link URL so taps can land directly on the subscribed database screen on both iOS and Android.
12. Records 900-second bidirectional cooldown windows after sending `game_started` or `round_started` (player channel).
13. Marks rows as `sent`, `skipped`, or `failed`.


## Live Updates (Per-Game)

Live Activities / Android Live Notifications are opt-in per game:

- Client upserts `user_live_game_subscriptions` with `game_id` + `platform`.
- `onesignal-dispatch` uses these rows to send:
  - iOS Live Activity updates (OneSignal Live Activities API).
  - Android Live Notifications (collapse_id + `live_notification` payload).

## Scheduling (pg_cron)

Active cron jobs:

| Job | Schedule | Description |
|-----|----------|-------------|
| `queue-round-heads-up` | `*/5 * * * *` | Queue heads-up for rounds 25-45 min away |
| `queue-round-started` | `*/3 * * * *` | Queue round_started for rounds in 10-min window |
| `dispatch-pending-heartbeat` | `* * * * *` | Fallback dispatch for any pending items |
| `cleanup-notification-outbox` | `0 */6 * * *` | Delete terminal rows older than 48h |
| `cleanup-notification-user-windows` | `*/10 * * * *` | Remove expired cooldown windows |

## Live Activities / Live Notifications

Now supported:

- **iOS Live Activities:** ActivityKit + Widget extension + OneSignal Live Activities updates.
- **Android Live Notifications:** Notification Service Extension + `live_notification` payloads.

See `ios/ChessEverLiveActivity/` and `android/app/src/main/kotlin/com/chessEver/app/NotificationServiceExtension.kt`.
