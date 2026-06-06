# Live Activity Clock Handover - 2026-06-06

Branch: `release/19.7-live-activity-pip`

## Current Architecture

Live Activity updates now use an isolated transport:

```
app starts ActivityKit activity
  -> app upserts user_live_game_subscriptions
  -> data hub calls live-activity-refresh every second
  -> live-activity-refresh sends OneSignal Live Activity event
  -> OneSignal updates ActivityKit content state
```

This path must stay separate from regular push notifications.

- It does not insert `notification_outbox` rows.
- It does not call `https://api.onesignal.com/notifications`.
- It calls only `https://api.onesignal.com/apps/{app_id}/live_activities/{activity_id}/notifications`.
- It targets `live:<gameId>:<userId>`, matching the ID used by `OneSignal.LiveActivities.startDefault(...)`.
- `onesignal-dispatch` skips `live_game_update` rows as a defensive backstop.

## Production State

Supabase project: `oelbsuggrzyqwzmvidju`

- `live-activity-refresh` is deployed as version 9 with `verify_jwt=false`.
- `onesignal-dispatch` is deployed as version 82 with `verify_jwt=false`.
- Data hub commit `7d65849` schedules the isolated refresh job every second.
- Data hub live refresh files are clean in `/Users/berkay/projects/chessever_data_hub_monorepo`.
- Outbox live update triggers are disabled/removed by migration `20260606125511_live_activity_refresh_isolation.sql`.

## Covered Update Cases

The server payload is built from the latest `games` row plus user board settings and eval cache:

- Position/FEN: `fen`
- Move: `last_move`, `last_move_uci`, `last_move_san`, `last_move_numbered`
- Clocks: `white_clock_seconds`, `black_clock_seconds`, `clock_anchor_time`, `active_clock_color`, `active_clock_deadline`
- Eval: `eval_cp`, `eval_mate`
- Game state: `status`, `is_game_over`, `is_check`, `is_checkmate`
- Forced redraw key: `refresh_ts`

When a game is ongoing, the refresh function sends an `update` event. When the game reaches a finished status, it sends one final update and then an `end` event, and disables that subscription.

## iOS Countdown Decision

`Text(timerInterval:)` is a valid SwiftUI API, including in Apple Live Activity examples, but it rendered as a black rectangle on the real device in this widget. We are intentionally not using it.

The widget renders clock text with `Text(formatSeconds(...))`. The countdown is driven by server-pushed content state changes: every refresh updates `refresh_ts`, the widget redraws, and `remainingSeconds` recomputes from `active_clock_deadline`.

This means the countdown depends on ActivityKit accepting frequent remote updates. The app plist has:

- `NSSupportsLiveActivities=true`
- `NSSupportsLiveActivitiesFrequentUpdates=true`
- `remote-notification` background mode

Apple can still throttle Live Activity pushes. Device testing is the final proof.

## App-Side Behavior

`lib/screens/chessboard/chess_board_screen_new.dart` starts a Live Activity when the board backgrounds if Live Activity mode allows it. This is not gated by regular push notification settings.

The initial ActivityKit payload mirrors the board/PiP state:

- If the user is at the live tail, it follows the server state and clocks tick.
- If the user is viewing an older move, it uses the viewed FEN/SAN/UCI/clocks and sets `follow_live=false`, so the clock stays frozen.

On resume, the app logs native ActivityKit content before stopping the current game's activity:

```
[LiveUpdates] Debug state (before_resume_stop): ...
```

Use that log to separate delivery failures from widget render failures. If `content.refresh_ts`, `content.last_move`, and clocks are current, the server update reached ActivityKit.

## Validation Already Done

- `deno check supabase/functions/live-activity-refresh/index.ts` passed.
- `flutter analyze --no-pub lib/services/live_updates_service.dart` passed.
- Scoped analyze of `lib/services/live_updates_service.dart` and `lib/screens/chessboard/chess_board_screen_new.dart` exited 0 with existing non-fatal warnings in the board file.
- Native iOS compile check via `xcodebuild ... -scheme ChessEverLiveActivity ... CODE_SIGNING_ALLOWED=NO` succeeded and compiled both the widget and `AppDelegate.swift`.
- Supabase CLI JSON list verified `verify_jwt=false` for both relevant functions.
- A debug prod call returned OneSignal status `201` for a Live Activity update payload.

## Hard Rules

1. Do not use the normal push notification/outbox path for Live Activity clock ticks.
2. Do not re-enable `queue_live_game_update_on_eval_change`; eval writes are a firehose.
3. Keep `live-activity-refresh` and `onesignal-dispatch` deployed with `verify_jwt=false`.
4. Keep the widget clock as plain text unless a real device proves `Text(timerInterval:)` no longer black-rectangles this extension.
5. Keep bool decoding wire-type agnostic. App start payloads can use `1/0`; server update payloads use JSON booleans.
