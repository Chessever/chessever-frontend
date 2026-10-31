# Favorite-player News publication

The protected publisher writes explicit `subject` / `quotation` metadata and its
visible top `Players involved:` identity links together with a new article.
The publication migration verifies player identity and records only the first
eligible publication. Tournament participants, results, pairings, passing mentions,
imports, edits and republication do not create alerts. Scheduled articles qualify
only when due. These rules are unchanged by the account preference redesign.

Delivery belongs to the admin notification service. It consumes the publication
ledger from its existing scheduler and uses the same device list, queue, claim,
Firebase / OneSignal transport and delivery tracking as game/event notifications.
This producer does not send push messages, issue device challenges, register
subscriptions, or read notification preferences.

The phone exposes `user_notification_preferences.favorite_player_news_alerts` as
one account setting shared by all devices, independent of game/event preferences.
It defaults to enabled, matching the previous News toggle; master push permission
and existing device opt-in still apply. The app reloads account preferences on resume.
The service checks it during recipient selection, claim and immediately before
provider submission. One article produces at most one queued delivery per eligible
device, regardless of how many favorite players match. Taps open the exact News ID;
notification copy is generic and spoiler-safe. Traffic already accepted by a push
provider cannot be recalled.

Review together: admin PR #6, phone PR #404, web PR #823.
The following migrations are already applied and verified in production, in order:
1. Phone `20261031051924_favorite_player_news.sql`.
2. Phone `20261031051929_account_news_preferences.sql`.
3. Admin `20261031051935_favorite_player_news_transport.sql`.

These filenames match production's recorded versions. Their SQL contents are
unchanged; do not apply them again under the former timestamps. The removed
`20261031010000_news_destination_possession.sql` migration was never applied.
The application PRs remain unmerged; no service deployment, app release or real
push was performed. Existing registration trust applies; there is no News-only
destination-possession guarantee.

Local validation uses synthetic transports only. From the admin root:
`FAVORITE_NEWS_PHONE_ROOT=../chessever-frontend FAVORITE_NEWS_WEB_ROOT=../chessever-web-frontend npm test`
and `npx tsc --noEmit`. The cross-owner tests require both companion PR checkouts.
From the phone root: scoped `flutter analyze --no-pub` and `flutter test --no-pub`
for `account_news_preferences_test.dart`, `favorite_player_news_test.dart`,
`favorite_player_notification_prefs_contract_test.dart` and `direct_push_tap_router_test.dart`;
from `supabase/tests`: `npm run test:favorite-news`.

Owner device acceptance remains separate: change News on one signed-in device,
resume another device and verify the same setting; verify exact article taps,
account switching, logout, and unchanged game/event alerts. No app build/run or
physical-device delivery has been performed by this source update.
