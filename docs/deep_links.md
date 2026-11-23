# Deep links, pushes and in-app links: the routing matrix

The one place that says where every inbound link, push and in-app link lands,
which code sends it there, what an older build does with it, and which test
pins it. Read it before changing a route, a push payload, a share URL, the
Android intent filters, the web's apple-app-site-association, or the dock.

Audited 2026-11-22 against:

- mobile: `stable` at 93ac88f8 (39.2.6+3935) plus the uncommitted deep-link
  fixes in this working tree (not yet committed, bumped or shipped),
  including the follow-up that closed O7, O14 and O17 and added the real
  HomeScreen tests (`test/home_screen_link_landing_test.dart`), and the
  second follow-up that closed O20, O21, O22 and the phone side of O6 and
  put the Nudge markers back on Home's and the Collections tab's page tabs
  (`test/nudge_marker_anchors_test.dart`), and the third that stops Android
  drawing a OneSignal mirror's copy once the install has registered directly
  (O6) and covers O20's `/app` and Inbox path and O22's in-place links;
- web: `chessever_web_frontend` origin/main 173a9e17. The fixes for O1 and O4
  are on branch `fix/deep-link-audit-2026-11` (cdf2dcf0), PR #966: open, not
  merged or deployed. The tables below still describe origin/main;
- admin portal and gamebase as read by the producer audit (see "Push payload
  contract"). The fixes for O2, O6 (part), O10 (receiving side), O11 and O12
  are on branch `fix/push-routing-audit-o-items` (cfa224e), admin PR #19:
  open, migrations not applied, Worker not deployed.

Related: `docs/mobile-app-routes.md` (the `/app/...` catalog for admins; its
WebView paragraph predates the outside-link allowlist in rule 7 below),
`docs/push_notifications.md`, `docs/onesignal-removal.md`.

Line numbers are for this working tree. "Old builds" means every build up to
39.2.6; the live store build on 2026-11-22 was 38.11.0.

---

## 1. Entry points

| Transport | Native capture | Dart entry |
|---|---|---|
| Android App Links, iOS universal links, custom scheme `com.chessever.app://` | `app_links`. iOS (`SceneDelegate.swift`): a cold start's URL and activity are forwarded from `willConnectTo`; a universal link while the app runs reaches app_links only through `FlutterSceneDelegate`'s fallback to the plugins' application delegates (no explicit forward since the 2026-11-23 fix: both together delivered every link twice); `openURLContexts` (custom scheme, files) still forwards, and Dart drops the second delivery when the fallback also ran | `DeepLinkService.initialize` (`deep_link_service.dart:699`), started in MyApp's post-frame callback, not the scheduler (`main.dart:1264-1282`) → `handleDeepLink` (`:754`). The same link delivered again within 2 s of its first delivery is one tap (rule 3); that also catches app_links' replay of the launch link on its stream when this listener is the first one (it is usually supabase_flutter's, subscribed earlier, which takes the replay). There is no open-ended skip: the launch link tapped again later opens |
| OneLink (`get.chessever.com`, `chessever.onelink.me`) | AppsFlyer SDK | UDL `_handleUnifiedDeepLink` and GCD `payload['link']` (`appsflyer_service.dart:871-916`) → `handleDeepLink`. AppsFlyer starts in the `startup_deep_link_services` task, which now waits for a resume instead of being dropped (`main.dart:1282-1306`, `foreground_task_scheduler.dart:40-131`) |
| iOS "Open in ChessEver" `.pgn` | scene `openURLContexts` → `file://` | `handleDeepLink` iOS file branch (`:773-797`) → `PgnFileIntakeService.handlePgnFilePath` |
| Android `.pgn` VIEW / SEND / SEND_MULTIPLE | `receive_sharing_intent` (`AndroidManifest.xml:141-190`) | `PgnFileIntakeService.initialize` (`pgn_file_intake_service.dart:199`), same scheduled task as AppsFlyer |
| Direct FCM push tap | Firebase `onMessageOpenedApp` / `getInitialMessage` (`direct_push_service.dart:136,152`); iOS `AppDelegate.swift:67-93` (`gcm.message_id`, or OneSignal's `custom.i` as `onesignal:<id>`, `:54`); Android foreground re-show with a JSON payload (`handleForegroundMessage`, `:178-209`) | `DirectPushTapRouter` (dedupe by message id) → `DeepLinkService.ingestNotificationData` (`deep_link_service.dart:399`), which unwraps a OneSignal envelope (`onesignal_push_payload.dart`), buffered (8, newest wins) until `attachNotificationRouter` (`main.dart:1258`) |
| OneSignal-format push (a device that updated from an SDK build and has not registered directly yet, O6) | iOS: the tap above. Android: a data-only FCM message (`custom` JSON, `title`/`alert`) drawn by `DirectPushService.presentOneSignalPush` (`direct_push_service.dart:451`) from `onMessage` (`handleForegroundMessage`, `:178`) and the background handler (`:28`), payload the unwrapped data, notification id from `custom.i`. Drawn only while this install has not registered directly (no `direct_push_owner`, `_registeredDirectly`, `:501`, re-read in the background isolate); after that it is a mirror's duplicate and is dropped | Its local notification's tap (`onDidReceiveNotificationResponse`, launch details) → `ingestNotificationData`, routed like the same push sent directly |
| Apple Watch "open game" | `WatchCompanionService` | `handleNotificationData({type: game_started})` (`main.dart:773-781`) |
| In-app links | Inbox, Nudge "See", Botvinnik Inbox, news articles, My Space link shortcuts | `editorialLinkOpenerProvider` (`editorial_link_service.dart:123`) and `NewsReaderScreen._openLink` (`news_reader_screen.dart:195-212`) → `DeepLinkService.openLinkInPlace` (`:621`); `space_shortcut_navigator.dart:843` → `openLinkFromApp` (`:632`); `open*FromApp` / `open*ForShortcut` (`:448-611`) |

No local notification is ever scheduled (no `zonedSchedule` in any version);
the only local notifications are Android re-shows of a push (a foreground
push, and a OneSignal-format data message in the foreground or background
while the install has not registered directly), routed like the push. PiP, home-screen quick actions, Spotlight and Siri have no
inbound routing.

## 2. Rules every route follows

1. **Splash first.** Every navigation awaits `_appReadyCompleter` (splash
   finished, 30 s cap) before touching the navigator.
2. **Session and onboarding hold the link.** `_readyToOpen` (`:2689`) and
   `_awaitDestinationSession` (`:2387`) open only with a session (a guest is a
   session) and with no sign-in page alone on screen (`_signInOnScreen`,
   `:2535`: top route `/auth_screen`, `/onboarding` or
   `/player_selection_screen` with no Home shell under it). Otherwise the
   link or push is kept in one slot (`_pending`, 30 min) and replayed, with
   the trust it arrived with, by `drainPendingDestination` (`:2754`) when
   HomeScreen mounts (`home_screen.dart:133`). Signed out with no sign-in
   page showing, the content routes (game, event, scorecard, profile, book,
   folder, collection, smart event, prep) also open sign-in; `/app` routes
   and Inbox only hold. A guest's Sign up opened over Home does not hold
   links. **A sign-in, sign-out or account deletion under way**
   (`AppAuthStatus.loading` as data, `_authUnderWay`, `:2548`) holds every
   link and push, WebView targets included (O22, `_navigateToWebView`,
   `:2262`), without opening sign-in or the page, the game route
   included even though the guest's Supabase session is still there: sign-in
   over the guest's Sign up would remove Home, and a page opened then would
   be removed by the Home the finished sign-in builds anew (AuthScreen,
   AuthStateListener). That Home routes it. **A sign-in that ends without
   signing in** (Google's or Apple's sheet dismissed, a failure) builds no
   new Home, so the hold watches the attempt (`_watchSignInAttempt`,
   `:2582`) and then (`_resumeAfterAbandonedSignIn`, `:2636`, O20): with the
   guest's anonymous session still alive the held link opens now, as the
   guest; with sign-in or onboarding alone on screen it keeps waiting for the
   Home sign-in builds (a sign-out gets 3 s to put that page up); otherwise
   it is let go with a neutral "Sign in to open that link."
   (`kHeldLinkNeedsSignInMessage`). The auth state stays at
   `error` (a guest's upgrade) or `unauthenticated` until a token refresh,
   so `_readyToOpen` and `_awaitDestinationSession` count a live Supabase
   session under those states as the guest's
   (`_guestSessionOutlivesAuthState`, `:2563`): a link arriving then opens,
   never sign-in over Home. A WebView link needs no session otherwise (a
   reader with no session and no sign-in page in front gets it at once).
   In-app references (`openLinkInPlace`, `open*FromApp`,
   `open*ForShortcut`) are never held.
   `markOnboardingComplete` leaves Home as the only route
   (`player_selection_screen.dart:442`).
3. **The newest tap wins.** Every path takes `++_destinationGeneration` and
   stops after each await if a newer tap arrived. The same game twice within
   500 ms is one tap (`_navigateToGame`). **One tap delivered twice opens
   once:** a link from outside (`handleDeepLink`) equal to the previous one
   (`inboundLinkKey`: scheme and host lower-cased, no trailing slash, no
   fragment, the query as sent) within `outsideLinkRepeatWindow` (2 s) of
   its first delivery is dropped, for every kind of link (a `/webview` link
   stacked two WebViews, content routes were only absorbed by the newest-tap
   rule). Another link always opens; the same link after the window opens
   again. In-app links and pushes are not affected (pushes are deduped by
   message id, `DirectPushTapRouter`).
4. **Home is reused, never rebuilt.** `_ensureHomeRoot` (`:2489`) closes the
   pages over the registered home shell (`popToHomeShell`,
   `bottom_nav_bar.dart:381`) and builds `/home_screen` only when there is
   none, so HomeScreen's session count, ATT, Shorebird and review prompt do
   not re-run per tap. It always bumps `homeChromeRevealRequestProvider`
   (`bottom_nav_bar.dart:391`), which HomeScreen answers by showing the dock
   even when the section did not change. So does every inbound link not
   opened in place and every push, as it arrives (`_requestHomeChromeReveal`
   in `_handleDeepLink` and `handleNotificationData`), since a board, an
   event or a profile opens over Home without `_ensureHomeRoot`. HomeScreen
   answers with `ScrollChromeController.showAndHold` (`home_screen.dart`):
   the dock, the floating buttons and the header come back at once, and a
   coast of the section's list stops where it is, as a finger on it would.
   Left running, the coast paused under the page (a covered route's tickers
   are muted) and ran on after Back: the list moved and, reading down, sent
   the bars away again. The review prompt never opens over a page a tap
   pushed (`home_screen.dart:152-154`).
5. **Content pages.** A board replaces everything above the first route
   (`pushAndRemoveUntil(isFirst)`, `:1779`); an event does the same with
   `/tournament_detail_screen` (`:2896`). Collection, smart event, prep,
   Inbox and `/app/...` pages open over Home. Profiles, books and folders push
   over the current page. In-app references (`preserveCurrentRoute`) always
   push over the current page: `open*FromApp`, `open*ForShortcut`, and
   `openLinkInPlace` (`:621`, Inbox, Nudge and Botvinnik Inbox links, and a
   news article's links since O21), which
   carries every content path and `/app` route over the message (or article)
   (`_handleDeepLink(inPlace: true)`, the legacy `/app/games|broadcast/...`
   kinds included) and leaves the reader there with a snack when the
   destination cannot open. Dock sections still switch the dock, and an
   article still opens in Discovery's reader (Home › Discovery › News).
6. **Failure keeps the reader in place.** `_linkFailed` (`:2507`): with a
   Home shell standing, nothing moves and a danger snack says "Couldn't open
   that link." (`kLinkFailedMessage`), or why, through `userFacingError`, for
   a collection link (offline, gone); only a cold start falls back to Home
   (with a Sentry warning unless already reported). A collection push keeps
   its own "could not be opened / Try again" snack over Home.
7. **Two trust levels for `/webview?url=`.** Outside links (universal link,
   App Link, custom scheme) open only `https://chessever.com`, `www` and
   `broadcast.chessever.com` in the app's WebView
   (`isExternalWebViewTarget`, `webview_link.dart`); any other target goes to
   the system browser (`:724-746`). Push routes and in-app links (authored by
   ChessEver) may open any http(s) page.
8. **No chessever.com link is ignored.** A page under a claimed prefix that is
   no app screen (`isWebOnlyChesseverPage`, `:306`) and any other own-host
   path (`:1094`) opens in an in-app browser over the app
   (`_openUnroutedWebPage`, `:1118`). Own pages the app launches itself go
   through `openOwnWebPage` (`own_web_page.dart`): Custom Tabs on Android,
   Safari on iOS.
9. **Free vs Premium is decided at open, never by hiding content.** Archive
   (gamebase) games ask `ensurePremiumGameAccess` (`:1837`); Reports ask
   `game_reports` and the opening tree `opening_tree` inside
   `openAppDestination` (an Inbox link to Reports too); a Premium collection
   gates when one of its games opens. The past-event gate runs for My Space
   shortcuts and in-app references (`gatePastEvent`, `:2864`), never for a
   link, in place or not; see open item O8.
10. **Phone and tablet route identically.** The tablet rail and the phone dock
    write the same `selectedBottomNavBarItemProvider`; HomeScreen registers
    the shell in both layouts.

## 3. Inbound links

Claims: **A** = Android verified App Link filter (`AndroidManifest.xml:84-121`,
both `chessever.com` and `www`, path-scoped since this tree; old builds claim
every path). **I** = iOS AASA on web origin/main
(`public/.well-known/apple-app-site-association`). Web PR #966 adds the whole
`/app` catalogue (`/app` and `/app/*` stay unclaimed) and the L10 excludes;
the I column changes once it is deployed (O1).

| # | Shape | Claimed | Handler | Lands on | Old builds | Test |
|---|---|---|---|---|---|---|
| L1 | `/games/<id>[?fen=]` (8-char games.id or Lichess id, UUID, namespaced, Direct id) | A, I | `:830` → `_navigateToGame` (`:1559`); `getGameByAnyId` tries games.id before lichess_id (`game_repository.dart:1146-1156`) | Board over Home, opened on `fen` when given, round swipe context hydrated after | games.id ≠ lichess_id (478 games in 60 days, e.g. XBnzfSW7 / q83KAyaw) lands on Home | `deep_link_routing_regressions_test` "a game resolves by games.id first (issue 9)"; `game_repository_get_by_any_id_test`; `home_screen_link_landing_test` (real HomeScreen, phone and tablet) |
| L2 | `/games/<uuid>?src=gamebase` | A, I | `_openGamebaseGame` (`:1823`) | Archive game alone on the board, after the archive Premium gate | Same | none |
| L3 | `/broadcast/<slug>/<tourId>[?tab=about\|games\|bracket\|standings\|players]` | A, I | `:857-877` → `_navigateToEvent` (`:2783`) → `_resolveEventRouteContext` (`:3527`) | Event on the tab (`tour_detail_tabs.dart:123`), that category preselected | Same | `deep_link_notification_router_test` "tester broadcast URL opens event" |
| L4 | `/broadcast/<groupId>`, `/broadcast/<slug>/<groupId>` (legacy) | A, I | tour probe misses, group id used (`:3556-3586`) | Event, default category | Same | none |
| L5 | `/broadcast/<slug>/<id>/round/<roundId>` (web round page) | A, I | `:865-867` passes `roundId` | Event on Games, that round preselected | Event on its default round | regressions "opens the event on its round" |
| L6 | `/broadcast/<tourSlug>/<roundId>` (PGN BroadcastURL rebranded from Lichess) | A, I | probe that is no tour is tried as a round (`:3588-3610`) | Event on that round | Home | same test |
| L7 | `/broadcast/<tour>/<roundSlug>/<roundId>[/<gameId>]` (Lichess-shaped) | A, I | `lichessShapedBroadcastTarget` (`:277`, `:823`) | Round on its event, or the game | Home | regressions "Lichess broadcast game path", round test |
| L8 | `/broadcast/<slug>/<id>/player/<fideId>` | A, I | `_navigateToPlayerScorecard` (`:2976`) | Event on Standings, then `/scorecard_screen` once the player is in standings (20 s); else stays on the event | Same | `app_destination_service_test` "event scorecard delegates..." (route form only) |
| L9 | `/broadcast/<slug>/<id>/team/<name>` | A, I | `_navigateToTeamScorecard` (`:3119`) | Event on Standings, then `/team_scorecard_screen` | Same | none |
| L10 | `/broadcast/{signin,editor,settings,hubs}`, `/broadcast/<hub-slug>` (kebab-case; event ids never contain `-`, checked in production), `/broadcast/<slug>/teams`, `/games/search` | A, I | `isWebOnlyChesseverPage` (`:306`, `:814`) | That web page in an in-app browser over the app | Home (resolved as a bogus id) | regressions "... opens on the web, over the app" |
| L11 | `/player/<fideId>`, `/player/<slug>/<fideId>`, either with `/games`, `/events`, `/about`, `/news`; `-NN` and `-reused` suffixes; `memorial-<16 hex>` | A, I | `playerProfileLinkTarget` (`:251`) → `_navigateToPlayerProfile` (`:3278`) | PlayerProfileScreen over the current page on that tab (news, overview, streaming open About); unknown player on a warm app: stays, snack | A view suffix is read as the id: Home | regressions "player profile links with a view (issue 21)" |
| L12 | `/books/<shareToken>` | A, I | `_navigateToBookPreview` (`:1155`) | BookPreviewScreen | Signed out: auth screen, link lost | none |
| L13 | `/databases/<id>`, `/folders/<id>` | A; I only `/databases/*` | `_navigateToFolder` (`:1470`) | FolderContentsScreen when owned or subscribed; else stays (warm) or Home (cold) | Same; signed out link lost | none |
| L14 | `/collections/<slug>` | A, I | `collectionSlugFromUri` → `_navigateToCollection` (`:1211`) | CollectionScreen over Home for every reader; Premium gates when a game opens. Unpublished or unreadable: nothing closes, a snack says why (`userFacingError`); Home only on a cold start | No session check: session-less Home over sign-in; unreadable: every page over Home closes, no word | regressions "a collection link signed out waits for sign-in, then opens", "... while onboarding ... is held", "a collection link that cannot open keeps the reader in place (O14)" |
| L15 | `/news`, `/news/<id>[/<slug>]`, `/news/page/<n>`, `/news/partners/rookreview/<id>`, `/app/news...` | A, I | `NewsLink.parse` → `_navigateToAppDestination` (`:748-764`) | Home › Discovery › NewsScreen › article; the pages over Home close, warm or cold (`openAppDestination` opens Discovery through `_openHome`, the catalog reader's own Back path) | Same on builds that parse NewsLink | `news_links_test`, `news_universal_reader_test` |
| L16 | `/webview?url=`, `/app/webview?url=` | A, I | `:724-746` | Own pages: AppWebViewScreen (held while a sign-in is under way or sign-in/onboarding is alone on screen, O22). Any other host: system browser (rule 7) | Any host in the ChessEver WebView | `deep_link_notification_router_test` "outside ...", `webview_link_test` |
| L17 | `/app/...` catalog (table 3a) | A; I only `/app/news*`, `/app/webview` | `parseAppDestination` (`app_destination.dart:71`) → `_navigateToAppDestination` (`:2300`) → `openAppDestination` (`app_destination_service.dart:88`) | See 3a | 36.8.8+ parse `/app`; My Space 37.4.5+ | see 3a |
| L18 | Any other chessever.com page (`/account`, `/privacy-policy`, `/terms-of-use`, `/desktop`, `/premium`, `/calendar/...`) | not claimed (A, I) | browser; if it still reaches the app: `_openUnroutedWebPage` (`:1094`) | Browser | Android catch-all opens the app, which ignores it | `android_app_links_manifest_test`; regressions `/account`, `/privacy-policy` |
| L19 | `com.chessever.app://games\|player\|books\|databases\|folders\|broadcast\|collections\|app\|webview...` | scheme | `:890-943`, `collectionSlugFromUri`, `parseAppDestination` | Same as the https form. OAuth callbacks fall through harmlessly | Same | regressions `com.chessever.app://player/1503014/games` |
| L20 | `https://streaks.chessever.com/p/<fideId>` | none (web only) | parsed only for My Space link shortcuts (`:121`) | Web | Same | `streak_player_screen_test` |
| L21 | OneLink `https://get.chessever.com/<template>/<code>?deep_link_value=` | A (AppsFlyer assetlinks); I claimed in entitlements but the OneLink AASA is empty (open item O3) | AppsFlyer UDL → `handleDeepLink('https://chessever.com/<deep_link_value>')` | Same as the path | Same | `appsflyer_service_test` (attribution only, no routing) |
| L22 | iOS `file:///.../Inbox/*.pgn` | doc types | `:773-797` | One game: board; several: PgnImportPreviewScreen, after `ensurePgnImportAccess` | Same | none |
| L23 | Android `.pgn` VIEW/SEND/SEND_MULTIPLE | intent filters | `PgnFileIntakeService` | As L22. Started once per launch even if the launch was not in the foreground at +250 ms | The task could be dropped for the whole process | `foreground_task_scheduler_test` |

### 3a. The `/app/...` catalog

Same handling for `https://chessever.com/app/...`, `www`, port 443,
`com.chessever.app://app/...`, a push's `data.route` and an in-app link.

| Route | Lands on | Test |
|---|---|---|
| `/app`, `/app/home`, `/app/home/today` | Home dock tab, Today; dock shown | regressions "route ... lands on its dock tab with the dock in view"; `home_screen_link_landing_test` "a route to the section already open brings the dock back" (real HomeScreen) |
| `/app/home/my-space`, `/app/home/discovery`, `/app/my-space` | Home, that page | `app_destination_test` (parse); `home_screen_link_landing_test` "/app/my-space lands on Home, My Space" |
| `/app/events` | Events page over Home (Events left the dock for Profile) | `app_destination_test` (parse only) |
| `/app/collections` | Collections dock tab | regressions (dock tab test); `home_screen_link_landing_test` (phone dock and tablet rail) |
| `/app/collections/<slug>` | CollectionScreen over Home, no page paywall (game gate, as L14) | `app_destination_service_test` "Premium locked collection opens its page with no paywall" |
| `/app/feed` | Feed dock tab (never a second FeedScreen) | regressions (dock tab test) |
| `/app/likes[/<period>][?from&to&players]` | Most liked, period and range restored | `app_destination_service_test` (one pre-existing date failure, see section 9) |
| `/app/miniatures[/about\|games\|players]` | Miniatures on that tab | `deep_link_notification_router_test` "Miniatures ..." |
| `/app/reports[/<type>]` | Reports on that type, after the `game_reports` gate | `app_destination_service_test` (dismissed paywall consumes the route) |
| `/app/my-space/prep\|library\|likes`, `/app/my-prep`, `/app/library`, `/app/my-likes` | My Prep, Library (Databases), My Likes | `deep_link_notification_router_test` "My Space ...", `my_space_deep_link_share_test` |
| `/app/my-prep/<id>` | Prep profile; false (fallback) when this device does not hold it | `app_destination_test` (parse only) |
| `/app/library/database[?event=]` | TWIC contents, exact event filter | `app_destination_service_test` |
| `/app/calendar[?date=]`, `/app/favorites[/<section>]`, `/app/settings[/<section>]` | Calendar, favorites mode, Settings with the section expanded | `app_destination_service_test` (favorites, settings), `app_destination_test` (calendar parse) |
| `/app/players/<id>[/games\|events]`, `/app/players/<id>/openings` | Profile on that tab; opening tree after the `opening_tree` gate | `app_destination_service_test`, regressions Inbox test |
| `/app/streaks...` (flagged), `/app/explorer\|positions\|openings/<eco>` | Streaks, an isolated explorer seeded with the line | `app_destination_service_test` |
| `/app/inbox[/<id>]` | Inbox, or that exact message over the Inbox | `inbox_push_navigation_test`; `home_screen_link_landing_test` "an Inbox nudge route ..." |
| `/app/games\|books\|databases\|folders\|player\|broadcast/...` (legacy) | Routed as L1-L13, over Home; from an Inbox or Nudge link, over the message | `app_destination_test`, `app_destination_service_test` (team route), regressions "`/app/games/<id>` opens the board over the message (O7)" |

## 4. Inbound pushes

Precedence inside `handleNotificationData` (`:1932`):
`favorite_player_news` → `data.route` (WebView target, else app destination,
falling back to `inbox_message_id`) → `inbox_message_id` → `data.url` (native
chessever.com shapes route natively, other URLs open in the WebView) → `type`
switch (`:2118`) → id hints in the default branch → Home.

| Type (producer) | Data keys | Lands on | Build gate / old builds | Test |
|---|---|---|---|---|
| `game_started`, `game_finished` (dispatcher `index.ts:601,1097,3196`) | `game_id` (games.id), optional `round_id`, `group_broadcast_id`, `grouped_round_start_key` | Board over Home with round swipe (L1); during a sign-in under way, held for the Home it ends on | Old builds: Home when games.id ≠ lichess_id (80 such pushes in 14 days) | regressions issue 9 (cold and warm), "a game push replaces the surfaces with the board", "the newest tap wins"; `home_screen_link_landing_test` (from Search, phone and tablet; "a game push during a guest's Google sign-in ... (O17)") |
| `round_started` (dispatcher `:1694`) | `round_id`, `group_broadcast_id`, `grouped_round_start_key` | Event on Games, that category and round | Same | `home_screen_link_landing_test` "an event push opens the event over Home"; regressions O17 group |
| `round_started` (admin automation, `tournament_started`) | campaign data plus `url` → delivery turns it into `data.route` `/app/broadcast/<gb>/<tour>` | Event of that tour on Games (`route` wins over `round_id`) | Builds without `route` use type + ids | `app_destination_test` (legacy broadcast parse) |
| `round_heads_up` (`:705`), `round_finished` (`:1031`) | `round_id`, `tour_id`, `group_broadcast_id` (nulls arrive as `"null"` over FCM) | Event on Games on that round; `"null"` and `"undefined"` read as absent (`:2947`) | Old builds treated `"null"` as an id; the dispatcher drops nulls since 2026-11-22 (`compactPushData`, deployed, `bf65fcfc`, O5 closed) | regressions 'a round push whose ids arrived as the string "null"' |
| `collection_games_added` (gamebase outbox → dispatcher `:845`) | `collection_slug`, `collection_title?`, `added` (string) | CollectionScreen over Home, then "N new games just landed"; unreadable: Home with Try again | Handler 36.3.6+; older: Home | `collections_screen_test` (~2964), regressions "signed out opens sign-in, not Home", "a collection push lands over Home; Back returns to it", O17 group; `home_screen_link_landing_test` (over the Collections tab, Back returns to it) |
| `smart_event_games` (queue `20261117200000_smart_event_push_stories.sql`, types `smart_event_live` / `smart_event_digest`; dispatcher `:2505,2572`) | `smart_event_id`, `smart_event_kind`, `games`, `min_elo`, `max_elo`, `formats` (CSV), `eco_code?`, `label?`, `smart_event_name?`, `game_id?` | SmartEventScreen on Games over Home | Queue gate: a device on build 3676 (37.0.4)+; older devices of that user open `game_id` | `smart_event_push_tap_test`, regressions signed-out case and O17 group; `home_screen_link_landing_test` |
| `prep_games_added` (dispatcher `:890`) | `prep_profile_id`, `added` (string), `profile_name?` | PrepProfileScreen on Games over Home; profile not on this device: My Prep plus "starred on another device / Stop alerts" | 36.10.10+ | `my_prep_profile_flow_test` (~2159), regressions signed-out case and O17 group |
| `book_game_added\|updated\|removed`, `book_folder_*` (dispatcher `:933-970`) | `folder_id`, `analysis_id`; `url` `https://chessever.com/databases/<id>` → `data.route` `/app/databases/<id>` | FolderContentsScreen over Home (route path) | Same | none (no campaigns in 14 days) |
| `call_to_action` (Inbox publish, dispatcher `:469`; admin campaigns) | `inbox_message_id`, `inbox_record_id`, `route?`, `url?` | `route` if valid, else that Inbox message over Inbox over Home, else Home | Same | `inbox_push_navigation_test`, `deep_link_notification_router_test`, regressions "a push that names nothing returns to the same Home", "a configured route push signed out opens after sign-in" |
| Admin campaign with `data.route` | `/app/...` or a WebView wrapper / plain URL | Table 3a, or the WebView | `/app` since 36.8.8, WebView since 37.12.1 | `deep_link_notification_router_test` "WebView notification ..." |
| `favorite_player_news` (admin fan-out) | `news_id`, `news_source?` (`rookreview`) | Home › Discovery › News › article; other `news_source` values are a deliberate no-op | Handler 37.6.9+. ChessEver-source articles still go to every build (O2) | `favorite_player_news_test` |
| Generic fallback (`'ChessEver update'`, dispatcher `:3200`) | `type: <event_type>` | Home (no report) | Same | `deep_link_notification_router_test` (no-hints payload) |
| `live_game_update`, `user_timezone_refresh` | outbox only | never sent | n/a | n/a |
| OneSignal-format push to a device that updated but has not re-registered (O6) | iOS: `custom` {`i`, `a`, `u`}, no `gcm.message_id`. Android: data-only, `custom` as JSON text, `title`/`headings`, `alert`/`contents` | `custom.a` unwrapped into the normal data (values as strings; `type`/`route` set beside the envelope kept) and routed like the same push sent directly. `custom.u` is used only when the data names no destination and it is a chessever.com page the router opens (an `/app` route, news, a content path, a `/webview` wrapper of an own page); a browser URL is ignored. Android draws the message itself (one notification per OneSignal id, also remembered for 50 ids so a redelivery is not drawn again), only while this install has not registered directly: once `direct_push_owner` is stored the service sends the same push itself and the OneSignal copy, from a mirror the server has not dropped yet, is not drawn. iOS is unchanged: the system draws it, the app routes its tap once | Builds before this tree: iOS opens Home (the tap is dropped natively), Android shows nothing. Not on Android before the first launch of the new build (no background handler is registered until then; nothing client-side can draw it). iOS foreground presentation of such a push is left to the system default (not handled natively) | `onesignal_push_payload_test` (parser; Android drawing from the real background handler and the foreground handler, once per id, and not at all once registered, a registration made while the background isolate is up included; iOS tap dedupe), regressions O6 group (iOS shape opens the board, the drawn Android payload opens the collection, `custom.u` rules) |

## 5. In-app link surfaces

| Surface | Order of handling | Lands on | Test |
|---|---|---|---|
| Inbox message buttons and markdown, Nudge "See", Botvinnik Inbox (`editorial_link_service.dart:123-236`) | 1. ten bare hub paths (`editorialPageForUri`, `:51`; Feed and Collections switch the dock tab, `:95-98`); 2. `/collections/<slug>` (paywalled page, product call O9); 3. everything else the app opens → `DeepLinkService.openLinkInPlace`: `/webview?url=`, every `/app` route, every `newsInAppRoute` shape (`/app/my-space/*`, `/app/likes\|miniatures\|reports/<x>`, legacy game, event, scorecard, profile, book and folder paths, share-image shapes, news); 4. own pages → `openOwnWebPage`; 5. other sites → system browser | As section 3, over the message, so Back returns to it; Reports still ask `game_reports`; a destination that cannot open leaves the message with a snack. Dock sections switch the dock and news opens Discovery's reader (both close the message, by design) | regressions "Inbox and Nudge links open the whole catalog in place" (incl. the O7 cases), `editorial_link_service_test`; `home_screen_link_landing_test` (a link in a real Inbox message) |
| News article links (`news_reader_screen.dart:195-215`) | another article in place; `newsInAppRoute` → `openLinkInPlace` (O21); else browser | As section 3, over the article, so Back returns to it, by the rules of an Inbox link: a destination that cannot open leaves the article with a snack; an article not in the reader's list still opens in Discovery's reader | regressions "a news article's links open over the article (O21)" (real `NewsReaderScreen`: game, event, a game that cannot be found); `news_universal_reader_test` |
| My Space shortcuts (`space_shortcut_navigator.dart:158-186,817-843`) | `open*ForShortcut` with `preserveCurrentRoute`; link shortcuts via `openLinkFromApp` | Over My Space; event shortcuts pass the past-event gate | `my_space_navigator_test` |

## 6. State carried over from older builds

| Stored value | Read by | Mapping | Test |
|---|---|---|---|
| `default_bottom_tab_v1` (by `Enum.name`) | `readDefaultBottomTab` (`bottom_nav_bar.dart:456`); HomeScreen falls back to Home when the section is not on the bar | `search` (38.18-38.21) and `tournaments` (35.x) → Home; `collections` → Collections; `botvinnik` switched off → Home | `start_screen_test` ("a saved section that left the bar opens Home"), `settings_customization_test` |
| `for_you_last_tab_v1` | dropped each launch (`forgetForYouPageForLaunch`, `home_screen.dart:55,114`) | Today unless a Premium reader saved another page | `start_screen_test` |
| `default_foryou_tab_v1`, `default_events_tab_v1`, `default_collections_tab_v1` | by name | unknown names → default | `start_screen_test` |
| `search_tab_recents_v1` | `SearchRecentPick.fromJson` (tolerant) | the Search page reads the old tab's recents | `search_recents_store_test` |
| Discovery dot ids `home.nav.*`, `home.menu`, `drawer.*` | `bottomNavBarDotIds` (`bottom_nav_bar.dart:98`) | kept; the Profile tab carries `home.menu` | `home_shell_default_route_test` |
| Nudge marker ids `home.tab.*`, `collections.tab.*` (dark on 38.18-39.2.6: `ForYouPageTabs` carried no anchor) | `ForYouPageTabs(dotScope:)` (`for_you_screen.dart`): Home's header passes `home.tab`, the dock's Collections tab (`CollectionsRoot`) passes `collections.tab` | the same ids as the old segmented tabs; the dot sits off the word's shoulder, a tap or standing on the page retires it | `nudge_marker_anchors_test` (every catalog placement against the real shell's widget tree; drawn and retired on both tab rows) |
| My Space shortcut kinds | parsed by name; unknown → null | unchanged | `my_space_add_sheet_test` |

No tab state is persisted by index anywhere.

## 7. Outbound share URLs

| Share | Builder | URL | Web (origin/main) | iOS AASA | Android | App parse |
|---|---|---|---|---|---|---|
| Game | `game_share_utils.dart:606-649`, `space_share.dart:102` | `/games/<games.id>[?fen=][&src=gamebase]` | `games/[gameId]` | yes | yes | L1/L2 |
| Event, standings tab, scorecard, team | `event_context_menu.dart:79-105` (`buildEventShareUrl`) | `/broadcast/<tourSlug>/<tourId>[?tab=]`, `/player/<fideId>`, `/team/<name>`; fallback `/broadcast/<slugified title>/<groupId>` | `broadcast/[slug]/[id]`, `.../player/[fideId]`, `.../team/[teamName]` | yes | yes | L3, L4, L8, L9 |
| Player profile | `player_profile_share_utils.dart:19-24` | `/player/<slug>/<fideId>`, `/player/<routeId>` | `player/[[...parts]]` | yes | yes | L11 |
| Collection | `collection_share.dart:19` | `/collections/<slug>` | `collections/[slug]` (hand-off) | yes | yes | L14 |
| Book | `folder_card.dart:724,743`, `space_library_bridge.dart:290,332` | `/books/<token>` | `books/[shareToken]` | yes | yes | L12 |
| News | news reader share | `/news/<id>/<slug>` | `news/[id]/[slug]` | yes | yes | L15 |
| Discovery Feed / Likes / Reports / Miniatures | `discovery_share.dart:23`, `discovery_models.dart:199`, `reports_share.dart:22`, `miniatures_share.dart:23` | `/app/feed`, `/app/likes[/<period>]`, `/app/reports/<type>`, `/app/miniatures/<tab>` | pages under `src/app/app/` | **no** (O1) | yes | 3a |
| Discovery News | `discovery_share.dart:23` | `/app/news` | redirect to `/news` | yes | yes | L15 |
| Discovery Collections | `discovery_share.dart:23` | `/app/collections` | **404** | **no** | yes | 3a |
| My Space Prep / Library / Likes | `space_component_share.dart:21` | `/app/my-space/prep\|library\|likes` | **404** | **no** | yes | 3a |
| Exported / copied PGN | `pgn_link_rebrand.dart` | Lichess game → `/games/<id>`; BroadcastURL → `/broadcast/<tourSlug>/<roundId>`; every other Lichess link stays on Lichess | game: yes; round id: web resolver probes tours and groups only (O4) | yes | yes | L1, L6 |

`test/app_share_url_contract_test.dart` asserts every Discovery and My Space
share parses in the app and is either served by the web or listed in
`_knownWebGaps` (`/app/collections`, `/app/my-space/*` today). Remove an entry
when its web page ships. Web PR #966 adds all four pages: once it is deployed,
move them from `_knownWebGaps` to `_webServedAppPaths` (the test fails while
a path is in both) and update the "as of" date.

## 8. Push payload contract

- **Strings only.** FCM carries every data value as a string. The app reads
  `"null"` and `"undefined"` as absent. The dispatcher drops null and
  undefined keys before the hand-off and the legacy send
  (`compactPushData`, `notification_handoff.ts`), effective once
  `onesignal-dispatch` is deployed.
- **OneSignal's envelope is read too.** A push that reaches a device
  through its old OneSignal registration (O6) carries the same data under
  `custom.a`; the app unwraps it (`onesignal_push_payload.dart`), so a
  sender never needs a second payload shape. `custom.u` is read only as a
  chessever.com page the router opens, and only when the data names no
  destination. On Android the app draws such a message only until the
  install registers directly; after that the same push comes from the
  service, and the mirror's copy is dropped.
- **Route by data, never by `url`.** Every type above is routed from its
  data keys. `url` is turned into `data.route` by the delivery worker
  (`chessever-admin-portal shared/mobile-route.ts:171-185`); the dispatcher's
  OneSignal `url` (book pushes) is only used on the legacy path.
- **Ids.** `game_id` is games.id (the app resolves it before lichess_id).
  `round_id`, `tour_id`, `group_broadcast_id` resolve round → tour → group.
  `collection_slug`, `prep_profile_id`, `folder_id`, `inbox_message_id`,
  `news_id` are exact identities.
- **No tab indexes, no Search or sidebar targets.** Sections are named
  (`/app/home/today`, `/app/collections`); the admin catalog has no
  `/app/search` or `/app/profile`.
- **Build gates live server-side.** A new type or a new route reaches old
  builds unless the audience is gated (`device_matches_audience` minimum
  version, or the smart-event queue's build check). Existing gates: smart
  events build 3676+; RookReview news 37.8.5+; ChessEver news ungated (O2;
  gated at 37.6.9 by admin PR #19 once applied).
- **Collapse and image.** The hand-off sends title, body, data, url, ttl and
  sounds only; image and collapse key are dropped (O10). Admin PR #19 lets
  the delivery Worker accept optional `image` (https) and `collapseKey` (1-64
  printable ASCII). The dispatcher here does not send them yet. Add them only
  after that Worker is deployed: until then its ingest schema rejects unknown
  keys and would refuse the whole push.

## 9. Verification (2026-11-22)

- `flutter analyze --no-pub lib test`: 0 errors; no error or warning in any
  touched file (the remaining issues are pre-existing infos and warnings
  elsewhere, chiefly the repo-wide `package:flutter/material.dart`
  deprecation).
- 62 routing, notification and navigation test files (every test file that
  names the router, the catalog, the editorial opener, the dock, the shell,
  pushes, shares or the PGN rebrand): 1493 pass, 6 fail. All six fail the
  same way on a `git archive` export of `HEAD`, so they predate these
  changes: "Likes destination restores period, range and Players in its own
  scope" (`app_destination_service_test`, a UTC vs local `DateTime`), four
  `focus_surfaces_events_test` cases (the event focus menu now offers "Add
  to My Space"), and one `player_profile_preview_data_source_contract_test`
  case.
- `onesignal-dispatch` Deno suite (previous round, untouched since): 125
  pass; `deno check index.ts` clean.
- Mutation check: in a `/tmp` copy of the tree, each fix was reverted on its
  own (games.id lookup, round parse, round probe, Lichess shapes, web-only
  pages, `"null"` ids, session hold, Home reuse, dock reveal, newest tap,
  editorial catalog and WebView branches, Feed dock tab, outside WebView
  allowlist, scheduler resume, profile tab, own-page launch mode, iPad share
  origin, the old manifest, the old PGN rebrand). Every one of the 21 mutants
  makes a new test fail. The follow-up's 8 mutants (Inbox links back on
  `openLinkFromApp`, the legacy `/app` kinds not in place, the in-place game
  failure without a snack, a failed collection link closing the pages, the
  loading auth state read as signed out, the game route ignoring a sign-in
  under way, HomeScreen not draining a held link, HomeScreen ignoring the
  dock reveal) each fail at least one test too.
- The real `HomeScreen` is covered (`test/home_screen_link_landing_test.dart`,
  13 tests): game, event, collection (over the Collections tab), smart event,
  `/app/my-space`, `/app/collections` and an Inbox nudge route landing from
  the Search page on the same Home; a link inside the real Inbox message
  opening over it; the tablet rail for `/app/collections` and a game push;
  held links draining after the real `markOnboardingComplete`; the dock
  reveal on a route to the section already open; a game push during a
  guest's sign-in. Only the section pages, their background syncs and the
  repositories are stood in (`homeSectionPageOverrideProvider`).
- Independent check (2026-11-22, separate from the fixing rounds). Phone:
  25 routing, notification and navigation files gave 684 passes and 1
  failure, the known "Likes destination ..." date failure. Analyze is clean on
  the touched files. In a `/tmp` copy, three fixes were reverted one at a
  time, and each revert failed tests: Inbox links back on `openLinkFromApp`
  (10 tests), the sign-in-under-way hold removed (5), and a failed
  collection link sent Home (2). Web PR #966: its 5 touched test files and
  `app-hub-share.test.tsx` pass under the repo's `test:fast` runner, 51
  tests in all. Reverting each of these fails a test: the `/webview` host
  check, the round fallback in the Worker, the round fallback in
  `getBroadcastPreview`, and the hub flag. Admin PR #19: `tsc` is clean and
  its 5 touched test files pass (133 tests); removing each of the 4
  migrations fails 5, 2, 1 and 1 tests. A read-only production check found
  every anchor the migrations patch exactly once, and the live
  `admin_portal.devices` view matches the definition 20261122180300
  replaces. The dispatcher's `notification_handoff_test.ts` passes (3).
- Second follow-up (O6 phone side, O20, O21, O22, Nudge markers):
  `flutter analyze --no-pub lib test` has 0 errors and 0 warnings
  repo-wide; the touched files carry no issue beyond the repo-wide
  `package:flutter/material.dart` deprecation. 84 test files in one run:
  the 76 routing, notification, navigation and Nudge files (the list above
  plus the new ones) and 8 adjacent ones (auth screen, news reader,
  segmented tabs, Collections and Home tab state, push permission): 2215
  pass, 6 fail, the same six pre-existing failures named above. New: `nudge_marker_anchors_test` (8),
  `onesignal_push_payload_test` (13), regressions O21 (3), O22 (4), O20
  (4, a sign-out among them) and O6 (4), `home_screen_link_landing_test`
  O20 and O22 on the real HomeScreen with a real guest session (5). Mutation check, each reverted on
  its own in place and restored: `dotScope` off Home's header and the
  Collections root; news links back on `openLinkFromApp`; the WebView hold
  removed; the sign-in watch removed; the guest session dropped from
  `_readyToOpen`; the OneSignal unwrap removed at both entry points (one
  alone is covered by the other); the Android background drawing removed.
  Every one fails at least one test.
- Third follow-up (verifier round: O6 duplicates, O20 and O22 coverage).
  `flutter analyze --no-pub` on the touched files: 0 errors, 0 warnings
  (only the repo-wide `package:flutter/material.dart` deprecation). 17
  routing, notification and push files in one run (the push and routing
  files, the editorial opener, `webview_link_test`,
  `app_destination_service_test`): 522 pass, 1 fails, the known "Likes
  destination ..." date failure. New: `onesignal_push_payload_test` 7
  (not registered: drawn once per id from the background handler, the
  foreground handler and both; registered: nothing drawn from either, a
  ChessEver push in the foreground still shown; a registration the app
  makes while the background isolate is up stops the next mirror push
  there), `home_screen_link_landing_test` 4 (O20 through
  `_awaitDestinationSession`, `error` and `unauthenticated`: an `/app`
  route push held during the attempt opens as the guest; an Inbox push
  after the cancel opens the Inbox, no sign-in), regressions 2 (O22: a
  WebView link tapped in the app opens at once mid sign-in and with
  onboarding alone on screen). Mutation check, each reverted in place and
  restored byte for byte: the direct-registration gate removed (3 tests
  fail), the background re-read removed (1), the gate always closed (6),
  the foreground handler not drawing OneSignal messages (1), the
  remembered ids removed (4), the guest branch of `_awaitDestinationSession`
  removed (4, and nothing else in the landing and regressions files), the
  in-place exemption of `_navigateToWebView` removed (2).
- Not covered by a test: the review-prompt guard (the prompt itself never
  runs off a phone), book and folder links, team scorecard links, PGN intake,
  AppsFlyer routing, the trust a held link is replayed with, the native
  iOS capture of a OneSignal tap (`AppDelegate.swift`, Swift cannot run
  here: its Dart side and the tap router's dedupe are tested), and the
  real storage behind the O6 gate on a device: the tests use the in-memory
  stores (legacy `SharedPreferences` for `direct_push_owner`,
  `SharedPreferencesAsync` for the remembered ids), not Android's files
  shared between the app's isolate and FCM's background isolate. Inside
  pushed screens (an event, a player, a collection, Prep,
  Likes, Miniatures, Countrymen, Rankings, the board bar) the Nudge test
  checks each catalog id against the source (`dotScope` and its labels),
  not a pumped screen; the shell's placements are checked in the real
  widget tree.
- Not run on a device, by rule (AGENTS.md). Device checks: an unrouted
  chessever.com page (`/broadcast/signin`) opens in a Custom Tab and does not
  bounce back into the app; Manage subscription, Privacy and Terms open on
  Android; a collection link on a signed-out cold start opens after sign-in;
  a link tapped during onboarding opens on Home afterwards; iPad share
  sheets rise from the tapped button; an Inbox message's game link and its
  My Space sub-page links (`/app/my-space/prep`, `/library`, `/likes`) open
  over the message and Back returns to it, while the My Space root
  (`/app/my-space`) switches to Home › My Space and closes the message, as
  every Home page does (section 3a; dock sections, section 5); a push tapped while
  Google's account picker is up (guest Sign up) lands after sign-in on the
  new Home, never on a sign-in page.
  Added by the second follow-up: (1) a push tapped while Google's or
  Apple's sheet is up, then the sheet dismissed: the push opens over the
  same Home, as the guest, and no sign-in page is pushed over Home; a link
  opened right after the dismissal opens too. (2) A `/webview` push tapped
  mid sign-in opens after it (on the new Home) or after the cancel, never
  under the Sign up page. (3) In a news article, "Open Game" / "Open Event"
  and in-body game links open over the article; Back returns to the
  article. (4) A Nudge published on `home.tab.discovery` (and one on
  `collections.tab.authors`) shows its dot beside the tab word, inside the
  bar, in light and dark, and retires on a tap; a trail through
  `home.tab.my_space` lights the tab, then the Prep tile. (5) iOS,
  native change (`AppDelegate.swift` `captureDirectPushTap`,
  `oneSignalNotificationId`): build, then send a OneSignal-format push
  (OneSignal dashboard to a device still on its OneSignal mirror, or an
  APNs payload with `custom: {i, a: {type: game_started, game_id}}` and no
  `gcm.message_id`); a tap from a killed app and from the background opens
  the game, once. A foreground arrival is presented (or not) by the system
  default: check it, a native `willPresent` branch was deliberately not
  added. (6) Android: with the app in the foreground, and with it in the
  background, a data-only FCM message
  `{custom: '{"i":"<uuid>","a":{"type":"game_started","game_id":"..."}}', title, alert}`
  shows one ChessEver notification (sent twice: still one) whose tap opens
  the game; before the first launch of the new build nothing can show it
  (expected).
  Added by the third follow-up: (7) Android, on an install that has
  registered directly (signed in, launched once with a session), the same
  OneSignal-format message, foreground and background (app in recents, and
  swiped away), shows nothing, and a direct push still shows once. Before
  that registration (a fresh update, first push before the first launch
  with a session completes), it shows once. Sign out (detach) and it shows
  again.

### Fourth follow-up: the simulator report (2026-11-23)

The one-time iPhone and iPad simulator run (`/tmp/sim_checks`) found five
things; each is fixed with a test that drives the real code, and each fix
was reverted on its own and made its test fail.

- **Every universal link reached Dart twice.** Cause: `SceneDelegate`
  forwarded `scene(_:continue:)` to `AppLinks.shared.handleLink` after
  `super`, and `super` (Flutter 3.38+, `FlutterSceneDelegate`) already hands
  the activity to app_links through its application-delegate fallback (no
  scene plugin claims it: AppsFlyer returns NO). The explicit forward is
  gone (also from the unused `AppDelegate` path). `openURLContexts` keeps it:
  google_sign_in's scene handler returns no BOOL, so the fallback there is
  not certain. In Dart, `handleDeepLink` drops a repeat of the same link
  within 2 s (rule 3), which also covers app_links' replay of the launch
  link on its stream. A first version also skipped that replay with no time
  limit; the replay goes to supabase_flutter's listener (subscribed first),
  so the skip never cleared and the same link tapped minutes later did
  nothing. It is gone. Tests: regressions "one tap delivered twice opens
  once" (a `/webview` link twice: one WebView; another link inside the
  window and the same link after it still open; a game and a collection
  link twice: one board, one collection; a cold start: one WebView, a
  replay a second later opens nothing, the same link three minutes later
  opens a second WebView).
- **Home's bars stayed away after Back.** A push or link that opened a page
  while Home's dock, buttons and header were scrolled away left them away,
  and the list moved. Cause: the game route never asked for the bars, and a
  coast still running paused under the page and ran on after Back (moving
  the list and hiding the bars again). Every inbound link and push now asks
  as it arrives, and Home stops the coast (rule 4). Tests:
  `home_screen_link_landing_test` "Back from the page a game push / a
  collection push / an outside game link opened over Home finds its bars,
  at the place the reader left" (real HomeScreen, a real fling, the push
  or link mid-coast; the outside-link case fails without the link's
  request for the bars).
- **The device check's wording** (section 9 above) now matches sections 3a
  and 5: the My Space root closes an Inbox message by design.
- **iPad: Share Image and Share GIF on the board** rose from the screen's
  bottom centre over the overlay's action row. They now anchor at the tapped
  button (`shareOriginOf`, `share_card.dart`), as every other share does,
  measured again when the sheet opens (the row can move on its spring
  between the tap and the share). Test: `share_game_card_ipad_origin_test`
  (the real overlay to share_plus' channel on an 834x1194 surface: the
  origin is the button's box, within a few points of where it rests).
- **iPad Today: an empty left column beside the first event block.** Cause:
  the tablet paired events two to a row by index, and an event whose boards
  came back empty hides itself, leaving its partner alone. The tablet now
  pairs only the events that draw (`drawnForYouEvents`); the phone list is
  unchanged. Test: `for_you_feed_stall_test` "the tablet pairs the sections
  that draw".

Device checks (not run here, by rule): (1) iOS, native change: with the app
running, `xcrun simctl openurl booted https://chessever.com/webview?url=https://chessever.com/premium`
logs one `DeepLinkService: Received link` and opens one WebView, one Back
returns to Home; a game, event, profile and collection link log one line
each; a cold start from a link opens it once, and the same link tapped a
minute later opens it again; an AppsFlyer OneLink still
attributes; a custom-scheme link (`com.chessever.app://collections/<slug>`)
and an "Open in ChessEver" `.pgn` open once. (2) Scroll Today until the dock
leaves, tap a game push (and a collection push) while the list still
coasts: Back shows the dock, the Search button and the header, the list
where it stopped. (3) iPad: board › three dots › Share Game › Share Image
and Share GIF: the popover points at the tapped button. (4) iPad Today: no
event block stands beside an empty column.

Re-run on the simulators after the fixes (debug, iPhone and iPad,
`/tmp/reverify`): a `/webview` link and a game link each logged one
`Received link` line and opened one page, one Back returned to Home; a
game push sent mid-coast and Back found the dock, Search button and header
with the list where it stopped (offsets 279.2 and 1858.0, kept); Share
Image and Share GIF on the iPad pointed at their buttons; iPad Today drew
no empty column. That run predates removing the launch-replay skip and
measuring the share anchor again at share time; both are covered by the
tests above, and a cold start from a link followed by the same link a
minute later is device check (1).

### Admin PR #19 rehearsal on production (2026-11-22)

All four migrations of admin PR #19 (`20261122180000` News version gate,
`180100` tournament start covers the first round, `180200` trigger image and
collapse key, `180300` superseded OneSignal mirrors) ran on
oelbsuggrzyqwzmvidju inside one `begin; ... rollback;`: every drift guard
passed, `news_client_supported('chessever','ios','37.6.8')` = false and
`'39.2.7'` = true, and the new `admin_portal.devices` view drops 358 superseded
mirrors (6,439 to 6,081 rows; the PR estimated 359). After the rollback the
helper function is absent and the view is unchanged. Applying them after the
PR merges is the only step left on the database side.

### Full suite green (39.2.8, 2026-11-22)

`flutter test --no-pub test`: 9,745 passed, 42 skipped, 0 failed (`9c7c6314`);
the 14 failures carried since 39.2.x were stale tests (product changes the
tests never followed) plus a game card clock overflow at large text (39.2.6),
now fixed.

## 10. Open items

Status as of the 2026-11-22 second follow-up: **Fixed in this tree** (phone,
uncommitted), **In PR, awaiting merge and deploy** (web PR #966 or admin PR
#19, verified, nothing shipped), **Awaiting deploy** (code ready, nothing to
merge), **Console change**, or open.

| # | Item | Owner / why not fixed here |
|---|---|---|
| O1 | **Closed 2026-11-22: web PR #966 merged (`f875f04a`), live as chessever-web `bf8994c6`; Apple's CDN serves the new claims.** iOS never opens `/app/*` hub links (Feed, Likes, Reports, Miniatures, Collections, My Space, players, events) in the app; `/app/collections` and `/app/my-space/*` are 404 on the web. The PR makes both AASA files one identical document claiming the `/app` catalogue (`/app` and `/app/*` stay unclaimed), puts the L10 excludes before every claim, turns on `IOS_APP_OPENS_HUB_LINKS`, adds hand-off pages for `/app/collections` and `/app/my-space[/prep\|library\|likes]`, redirects `/app/{collections,games,books,broadcast,player}/...` to their web pages, and serves both AASA files and `assetlinks.json` as `application/json` (`public/_headers`). Still 404 in a browser, claim only: `/app/home*`, `/app/events`, `/app/inbox*`, `/app/settings*`, `/app/players/*`, `/app/calendar`, `/app/favorites*`, `/app/my-prep*`, `/app/library*`, `/app/my-likes`, `/app/streaks*`, `/app/explorer`, `/app/positions`, `/app/openings/*`. Installed iOS builds before 37.5.17 (before 36.8.8 for every `/app` path) now open these links on Home instead of the web page | Merge and deploy #966; Apple's CDN picks up the new file within about a day. Then move the four paths from `_knownWebGaps` to `_webServedAppPaths` (section 7) and update the I column. **Console change:** Cloudflare challenges the root `/apple-app-site-association` (403 for non-browser clients); Apple reads only the `.well-known` copy, so it does not block, but lift the challenge for both paths |
| O2 | **Closed 2026-11-22: admin PR #19 merged (`e7dab0f`), migration `20261122180000` applied (gate checked: 37.6.8 false, 39.2.8 true).** Favourite-player News (ChessEver source) goes to builds before 37.6.9 and to unknown-version OneSignal mirrors (about 19k deliveries in 14 days), which open Home. The migration gates the `chessever` source at 37.6.9 in `chessever_admin_news('tick')` and `news_delivery_eligible` (claim and authorize_send) through `admin_portal.news_client_supported`; partners keep 37.8.5; queued deliveries to older builds are skipped at claim | Apply the migration (rollback in its header) |
| O3 | OneLink hosts serve an empty AASA, so iOS OneLinks never open the installed app | AppsFlyer console: enable iOS Universal Links on template GXOt (Team N8J7TUZMYR, bundle com.chessever.app), then confirm on Apple's CDN |
| O4 | **Closed 2026-11-22: web PR #966 live.** The web does not resolve `/broadcast/<slug>/<roundId>` (rebranded PGN links); the web has no `/webview` route. The PR adds a rounds fallback to `getBroadcastPreview` and to the Worker's `resolveBroadcastTour`, plus a permanent redirect to `/broadcast/<slug>/<tourId>/round/<roundId>` that keeps the query. `/webview` and `/app/webview` redirect only to `https://chessever.com`, `www` and `broadcast.chessever.com`; anything else is a 404, never an open redirect. The same PR keeps `?tab=players` in the canonical URL, title and share image, hides "Open in ChessEver" on auxiliary News, and makes the shared-book page open the app only on a tap, with store fallbacks | Merge and deploy #966 |
| O5 | **Closed 2026-11-22.** `onesignal-dispatch` with `compactPushData` deployed to oelbsuggrzyqwzmvidju with `--no-verify-jwt` (`bf65fcfc`; live copy was identical to HEAD before the deploy; `check_edge_function_auth.sh` passed; `which_repo_owns_function.sh` reports this repo identical to live). Trigger campaigns in the 8 hours around the deploy carry no null data values | - |
| O6 | **Closed 2026-11-22 for every reachable case: phone side in 39.2.7; migration `20261122180300` applied (358 superseded mirrors out of reach) and the delivery Worker `58c3191f` deployed.** OneSignal-format pushes to an updated device that has not registered directly yet now route: iOS taps carrying OneSignal's `custom` (no `gcm.message_id`) are captured natively as `onesignal:<custom.i>` (`AppDelegate.swift`, native change, device check 5) and Dart unwraps `custom.a` (`onesignal_push_payload.dart`, at `ingestNotificationData` and `handleNotificationData`); Android data-only OneSignal messages are drawn by the app (`DirectPushService.presentOneSignalPush`, foreground `onMessage` and the background handler) with the unwrapped data as payload, one notification per OneSignal id, and only while this install has not registered directly (no `direct_push_owner`, read anew in the background isolate): until the migration below is applied a reader with both a mirror and a direct registration gets every push both ways, and the mirror's copy is dropped on the phone. `custom.u` is used only as a chessever.com page the router opens, and only when the data names no destination. The migration drops a OneSignal mirror from `admin_portal.devices` once the same account has registered directly on the same platform after the mirror was last seen (359 mirrors, 85k deliveries, 2 opens in 14 days). | Apply the migration. Still open, by nature: builds before this tree drop these taps (iOS) or show nothing (Android); Android cannot draw them before the first launch of the new build (no background handler is registered yet); an iOS OneSignal push arriving in the foreground is left to the system default (no native `willPresent` branch, by the no-unneeded-native-change rule) |
| O7 | **Fixed in this tree.** Inbox, Nudge and Botvinnik Inbox links of every shape go through `openLinkInPlace` and open over the message (the legacy `/app/games\|broadcast/...` kinds too); the Reports gate is kept; a failure leaves the message with a snack | Regressions "... over the message (O7)"; `home_screen_link_landing_test` |
| O8 | Links and pushes to past events skip the past-event Premium gate that every in-app entry applies | Product decision: links as a free entry (document it) or gate at open as shortcuts do |
| O9 | `/collections/<slug>` in an Inbox message paywalls the page; the same collection from a link, push or `/app/collections/<slug>` route gates at the game | Product decision |
| O10 | **Closed 2026-11-22: migration `20261122180200` applied, delivery Worker `58c3191f` deployed, dispatcher sends `image`/`collapseKey` (`1b215c14`, deployed).** Hand-off drops the push image and collapse key (Inbox images missing, Prep pushes stack). With the PR, `/internal/notifications` accepts optional `image` and `collapseKey`. FCM gets the image on Android and iOS, and the key becomes the Android notification tag and the `apns-collapse-id`. OneSignal gets `collapse_id`. Senders that don't send them are unchanged, and a bad value drops only that extra | In order: apply the migration, deploy the delivery Worker, then make `onesignal-dispatch` (`notification_handoff.ts`, this repo) send `image` and `collapseKey`, and deploy it. Sent earlier, the strict ingest rejects the whole push |
| O11 | **Closed 2026-11-22: migration `20261122180100` applied.** Event starrers get the admin "tournament started" campaign and the dispatcher's first `round_started`. With the PR, `observe` also suppresses the dispatcher's follower `round_started` when an all-user `tournament_started` is reserved for that section's first round, the same rule as `round_started`. Game alerts are unchanged | Apply the migration; the dispatcher already acts on `observe`'s answer |
| O12 | **Closed 2026-11-22: admin PR #19 merged and the admin Worker `f93a4588` deployed.** Admin Nudges list still describes the old shell (Events trail, no Feed/Botvinnik). With the PR, `shared/nudges.ts` follows the current dock, Home pages and Profile rows, keeps every legacy id with a version note, shows where each "See" link opens, refuses `/app/` links the app cannot open, and a test checks every marker id against this checkout | Deploy the admin portal after the merge Follow-up for that PR: `home.tab.*` and `collections.tab.*` are drawn again from the next phone build (Home's and the dock Collections tab's page tabs carry them, `ForYouPageTabs(dotScope:)`), so their `builds` note should read "all builds except 38.18 to 39.2.6" instead of "before 38.18 only", and the catalog's shell comment and its test ("ids older builds light ...") change with it. `test/nudge_marker_anchors_test.dart` here checks every catalog id against the real shell (sibling checkout or the pinned copy `test/fixtures/nudge_surfaces_pinned.ts`, refresh it when the catalog changes); only `drawer.desktop` is retired |
| O13 | Old Android builds keep the catch-all filter: own pages bounce back into them until they update | None client-side; optionally serve account and legal pages from an unclaimed host |
| O14 | **Fixed in this tree.** A collection link that cannot be read keeps the reader in place with a snack that says why (`_linkFailed`, `userFacingError`); a cold start still lands on Home | Regressions "a collection link that cannot open keeps the reader in place (O14)" |
| O15 | Unverified: AppsFlyer GCD routes `payload['link']` without checking `is_first_launch` (`appsflyer_service.dart:871-876`); whether `www.chessever.com` App Link verification survives a redirect | Device / AppsFlyer check |
| O16 | Game links and pushes with games.id ≠ lichess_id stay broken on old builds | Optional dispatcher change: send lichess_id in `game_id` when it differs (keep the collapse id on games.id) |
| O17 | **Fixed in this tree.** A sign-in, sign-out or deletion under way (`AppAuthStatus.loading` as data) holds the link or push (event, collection, smart event, prep, scorecards, profile, book, folder and the game route, which a guest's live Supabase session used to let through) without opening sign-in or the page; the Home the finished sign-in builds routes it (rule 2) | Regressions O17 group; `home_screen_link_landing_test` "a game push during a guest's Google sign-in ..." |
| O18 | The dispatcher's legacy OneSignal path (`sendLegacyOneSignal`, used when the notification service is off or not live) reaches no build since 37.6.11 and gives book pushes a browser `url` | Backend (low): make the path fail loudly instead of sending, drop `url` from book payloads (`folder_id` already routes) |
| O19 | Any outbox type without a builder sends 'ChessEver update / You have a new update.' that opens Home | Backend (low): skip unknown types instead of sending the generic copy |
| O20 | **Fixed in this tree.** A cancelled or failed Google or Apple sign-in leaves the auth state at `error` (a guest's upgrade) or `unauthenticated` while the guest's anonymous session lives on. A link or push held during the attempt now opens as the guest as soon as the attempt ends (`_watchSignInAttempt` / `_resumeAfterAbandonedSignIn`); with sign-in alone on screen it keeps waiting for the Home sign-in builds (a sign-out gets 3 s to put that page up); with no session and Home still standing it is let go with a neutral "Sign in to open that link.". A link arriving in that window reads the live Supabase session as the guest's (`_guestSessionOutlivesAuthState` in `_readyToOpen` and `_awaitDestinationSession`) and opens, never sign-in over Home | `home_screen_link_landing_test` "a guest's cancelled sign-in ..." (real HomeScreen, real guest session, `error` and `unauthenticated`); `home_screen_link_landing_test` "... opens the /app route push it held ..." and "... an Inbox push that arrives afterwards ..." (the `/app` catalog and the Inbox read the session in `_awaitDestinationSession`); regressions O20 group (no session: dropped quietly after the grace; sign-in alone, and a sign-out that ends there: still held, then routed). In that window an Inbox push opens the Inbox but not the message, which reads the app-wide account (below). Still the auth owner's (low): the app-wide `currentUser` stays null in that window until a token refresh; restoring the previous state after a cancelled upgrade would fix it everywhere |
| O21 | **Fixed in this tree.** News article links to a game, event, scorecard, profile or `/app` page (`NewsReaderScreen._openLink`) go through `openLinkInPlace` and open over the article, by the rules of an Inbox link (Back returns to the article; a failure leaves it with a snack) | Regressions "a news article's links open over the article (O21)" (real reader: game, event, missing game) |
| O22 | **Fixed in this tree.** `/webview?url=` links and push routes (`route`, `url` wrappers) wait while a sign-in, sign-out or deletion is under way and while sign-in or onboarding is alone on screen (`_navigateToWebView`), held for the Home that follows or for the cancel (O20). A WebView still needs no session; in-place links are never held | Regressions O22 group (push route and url wrapper mid sign-in, outside link during onboarding, Home in front opens at once, a link tapped in the app opens at once mid sign-in and with onboarding alone on screen); `home_screen_link_landing_test` "a WebView push held during the sign-in opens once it is cancelled (O22)" |

Deploy steps for the open PRs (none taken; production is
`oelbsuggrzyqwzmvidju`):

1. Admin PR #19: merge, then apply `20261122180000`, `20261122180100`,
   `20261122180200` and `20261122180300` in order (each one stops with an
   error if its anchor has changed), then deploy the portal and delivery
   Worker (`npm run deploy`). The order of the migrations and the Worker
   only matters for O10, and only once the dispatcher sends the extras.
2. Web PR #966: merge and deploy. Afterwards, check that
   `https://chessever.com/.well-known/apple-app-site-association` answers
   200 with `application/json`, and that Apple's CDN
   (`app-site-association.cdn-apple.com/a/v1/chessever.com`) shows the new
   claims. Lift the Cloudflare challenge on the root copy.
3. This repo: deploy `onesignal-dispatch` with `--no-verify-jwt`, then run
   `check_edge_function_auth.sh` (O5). Only after step 1, add `image` and
   `collapseKey` to the hand-off and deploy it again (O10). Commit the phone
   tree with its version bump, and move the `_knownWebGaps` entries after
   step 2.

## 11. Rules for future routing changes

Change these together, in the same commit or PR pair:

1. **A new https path the app opens:** `handleDeepLink`; both Android filters
   (`AndroidManifest.xml`, `chessever.com` and `www`) and
   `test/android_app_links_manifest_test.dart`; both AASA files on the web and
   `test/webview-association.test.mjs`; a web page or hand-off for people
   without the app; sections 3 and 7 here. Never add a host-only App Link
   filter.
2. **A new `/app/...` route:** `parseAppDestination` and `openAppDestination`;
   the admin catalog (`chessever-admin-portal shared/mobile-route.ts`,
   `NotificationDestination.tsx`); `docs/mobile-app-routes.md`; if the app
   shares it, `app_share_url_contract_test` and the web hand-off plus AASA
   claim (or a `_knownWebGaps` entry with an owner).
3. **A new push type:** the producer's payload (strings only, no nulls, ids not
   indexes); a `case` in `handleNotificationData` with a Home fallback for a
   missing id; a server-side minimum-version gate for every build that cannot
   route it; a regression test; section 4 here. Old builds in the wild will
   receive it otherwise.
4. **Dock and sections:** open a dock section through `_openHome` /
   `openHomeSection`, never by pushing a second copy; persist tabs by
   `Enum.name` and keep fallbacks for removed names (`search`, `tournaments`);
   keep discovery dot ids stable. A tab row, dock slot or menu row that is
   rebuilt keeps its Nudge anchor (`DiscoveryDotAnchor`, `dotScope`, the
   same ids); `test/nudge_marker_anchors_test.dart` fails when a placement
   the admin catalog offers has no surface in the shell. Change the admin
   catalog (`shared/nudges.ts`) and the pinned copy
   (`test/fixtures/nudge_surfaces_pinned.ts`) in the same PR pair.
5. **Navigation from the router:** use `_ensureHomeRoot`, `_linkFailed`,
   `_readyToOpen` (or `_awaitDestinationSession`) and the generation check;
   every destination, WebView included, waits while `_authUnderWay`, and a
   hold made then is watched (`_holdInbound`) so a cancelled sign-in never
   strands it; a link tapped on a page in the
   app that must keep that page goes through `openLinkInPlace`; never
   `pushNamedAndRemoveUntil('/home_screen', ...)` directly, never ignore a
   chessever.com link, never route on a raw string id without
   `_asNonEmptyString`. Links from outside enter through `handleDeepLink`
   (the duplicate-delivery rule); anything else the router routes as a link
   (a push's URL, a held link) calls `_handleDeepLink`, which asks Home for
   its bars unless the link opens in place.
6. **Own web pages:** `openOwnWebPage`, never `LaunchMode.externalApplication`
   for chessever.com.
7. **WebView:** outside links stay on the allowlist; only ChessEver-authored
   pushes and in-app links may open arbitrary pages.
8. **Shares:** every URL the app shares must parse in the app and open on the
   web (or be a listed gap). Changing a share shape means old builds receive
   it: keep the old shape routable.
9. **Old builds are permanent recipients.** A server or web change may never
   change the meaning of an existing path, key or type. Add, gate, and keep
   the legacy group-id and Lichess shapes resolvable.
10. **Cold start:** the push click listener stays registered from `main()`
    (via `StartupGate`) and taps buffer until `attachNotificationRouter`.
    Launch-once work (`DeepLinkService.initialize`, PGN intake, AppsFlyer)
    must not ride a fire-once `ForegroundTaskScheduler` task without
    `runWhenResumed`.
