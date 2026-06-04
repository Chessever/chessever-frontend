# Chessever Frontend PR Report

Generated: 2026-06-03 18:42:52 UTC
Repository: https://github.com/Chessever/chessever-frontend
Times: UTC from GitHub metadata. `Completed` is `mergedAt` for merged PRs, `closedAt` for unmerged closed PRs, and blank for open PRs.

Total PRs: 210
Open: 8
Merged: 160
Closed without merge: 42

## Index

| PR | State | Title | Purpose / what it does | Created | Completed | Author |
| --- | --- | --- | --- | --- | --- | --- |
| [#212](https://github.com/Chessever/chessever-frontend/pull/212) | OPEN | Feat/pip | No PR description provided; inferred from title/branch only: Feat/pip. | 2026-06-03 16:18:13 UTC | Not done / open | arunn10 |
| [#211](https://github.com/Chessever/chessever-frontend/pull/211) | OPEN | fix: rank phone engine arrow prominence | Keeps the existing engine arrow count and color ordering intact. Adds rank-based opacity and chessground arrow scale so the first recommendation is thickest/most prominent and lower-ranked arrows progressively soften. Applies the same visual hierarchy to normal PV arrows and threats-mode arrows without adding labels. | 2026-06-02 15:19:30 UTC | Not done / open | dagidici |
| [#210](https://github.com/Chessever/chessever-frontend/pull/210) | OPEN | fix: show opening game count cue on player Games tab | Shows a temporary game-count cue on the player profile Games tab after selecting an opening from About, e.g. Games 56. Clears the cue when the Games tab is opened or the opening filter is removed. Keeps the existing in-Games filter/count UI as the primary detail view. | 2026-06-02 02:20:40 UTC | Not done / open | dagidici |
| [#209](https://github.com/Chessever/chessever-frontend/pull/209) | OPEN | Add My Likes organization tools | Rename the special liked-games database presentation to **My Likes** with a heart icon and no manual add/rename controls. Add premium-gated search/filter/sort/tag/export tools for My Likes, with export moved into the 3-dot menu. Add official personal tags to the Save Analysis / edit sheet and persist them through saved analysis reload/update flows. Preserve My Likes as an automatic like/unlike database by disablin... | 2026-06-01 23:26:55 UTC | Not done / open | dagidici |
| [#208](https://github.com/Chessever/chessever-frontend/pull/208) | OPEN | Fix round-start pushes before moves | Requires an actual game move (games.last_move_time) before queuing or dispatching round_started push notifications. Adds an Edge Function safety net so already-queued false starts are skipped as round_not_live_yet instead of sent. Adjusts round-start event naming so grouped multi-section events can include the raw tour section, while single/non-grouped events avoid redundant Open labeling. Adds regression coverage... | 2026-06-01 18:36:14 UTC | Not done / open | dagidici |
| [#207](https://github.com/Chessever/chessever-frontend/pull/207) | OPEN | Fix phone Events search relevance for historical queries | Tightens phone Events tournament relevance scoring for specific multi-token searches like norway chess 2015. Keeps close event-name matches such as Norway Chess 2026, but filters out generic chess-only/current-event matches such as unrelated championships. Re-scores Supabase event search results before displaying them instead of treating every backend result as an equal 100 score, then sorts by relevance before date. | 2026-06-01 17:05:52 UTC | Not done / open | dagidici |
| [#206](https://github.com/Chessever/chessever-frontend/pull/206) | OPEN | fix: refresh Android board audio after resume | Refreshes the Android SoLoud engine/assets after the app truly backgrounds and resumes. Keeps transient inactive/hidden states ignored, matching the previous fix that avoided teardown during short lifecycle transitions. Forces asset flags to clear on forced initialization even if SoLoud no longer reports initialized, so stale handles cannot be reused. | 2026-05-31 17:48:18 UTC | Not done / open | dagidici |
| [#205](https://github.com/Chessever/chessever-frontend/pull/205) | OPEN | Fix board move taps toggling liked games | suppress the board double-tap like/unlike shortcut when the gesture is actually tap-to-move input track the two board squares involved in a quick tap sequence and ignore like/unlike if the first tap selected the side-to-move piece and the second tap lands on another square/piece keep true same-square double-tap available for like/unlike | 2026-05-31 17:16:22 UTC | Not done / open | dagidici |
| [#204](https://github.com/Chessever/chessever-frontend/pull/204) | MERGED | Fix TWIC player event titles (recover parent event from Site URL) | #200 tried to recover the canonical parent event by reading tour_id / tournament_id / tourSlug from gamebase player-games rows. **Those fields do not exist** on any gamebase row (verified live against service.chessever.com). For round-labeled broadcast games the PGN Event is a per-round pairing label (e.g. Round 7: Nazli, Sertan - Akal, Muhammed Furkan), so #200's helper returned that label unchanged — the bug rem... | 2026-05-31 14:15:57 UTC | 2026-05-31 14:16:10 UTC | devberkay |
| [#203](https://github.com/Chessever/chessever-frontend/pull/203) | CLOSED | Fix phone stale live round ordering | Adds time-control-specific freshness checks for phone live-round status: blitz 10m, rapid 20m, standard/classical 120m. Treats recent move activity as the live signal even when backend live_round_ids is stale, so old rounds like Saturday Night Blitz Round 2 stop staying pinned above newer active rounds. Recomputes round status when game last_move_time changes and reselects the best auto round unless the user manua... | 2026-05-31 11:28:15 UTC | 2026-05-31 13:49:03 UTC | dagidici |
| [#202](https://github.com/Chessever/chessever-frontend/pull/202) | MERGED | Fix phone forward arrow engine move fallback | Removes the phone bottom-nav right-arrow fallback that appended/played an engine/PV move at the end of notation. Keeps the arrow limited to real notation navigation or already-active PV-preview navigation. Leaves explicit PV/engine UI actions as the only path for inserting/committing engine moves. | 2026-05-31 02:02:06 UTC | 2026-05-31 13:54:17 UTC | dagidici |
| [#201](https://github.com/Chessever/chessever-frontend/pull/201) | MERGED | fix: keep save icon for liked games | Keeps the game header save/edit action visible during double-tap like animations. Shows liked state only as the small red heart badge on the save/edit button. Updates like-flight comments so future changes do not reintroduce full-heart replacement in the AppBar. | 2026-05-30 23:02:55 UTC | 2026-05-31 13:55:12 UTC | dagidici |
| [#200](https://github.com/Chessever/chessever-frontend/pull/200) | CLOSED | Fix TWIC player event titles | prefer canonical TWIC event names from player-game rows when PGN Event is only a round/pairing label build TWIC player Events tab from canonical game grouping to avoid showing each round as a separate event add TWIC event identity helper tests | 2026-05-30 16:19:19 UTC | 2026-05-31 14:16:07 UTC | dagidici |
| [#199](https://github.com/Chessever/chessever-frontend/pull/199) | MERGED | Split phone Library folders and databases | Splits the phone Library model into explicit folder/database node types (nodeType) so folders are organizational and databases hold games. Updates Library creation, card/menu labels, folder contents, save-analysis, add-to-library, bulk add, and PGN import flows to use only databases as save/import targets. Adds a safe Supabase migration mirroring the desktop cleanup for legacy mixed nodes, plus a regression test f... | 2026-05-30 01:04:28 UTC | 2026-05-31 14:27:08 UTC | dagidici |
| [#198](https://github.com/Chessever/chessever-frontend/pull/198) | MERGED | Fix Norway Chess scoring display | preserve per-player custom broadcast points from game player JSON into player cards show Norway classical custom points on board rows (3-0 wins, 1-1 draws) keep Armageddon board rows simple as 1-0, while player scorecards can show the 0.5 bonus preserve official source standings scores instead of recalculating custom broadcasts as standard chess points | 2026-05-29 00:53:54 UTC | 2026-05-31 14:11:06 UTC | dagidici |
| [#197](https://github.com/Chessever/chessever-frontend/pull/197) | CLOSED | Fix grouped round-start notification dedupe metadata | Follow-up to PR #186 / Berkay local notification dedupe work; this is additive and does not replace the existing dispatcher changes. Includes round_name and starts_at in round-start notification data, so the existing sent-row duplicate check has the metadata it compares. Tightens grouped round-start collapse/dedupe identity to group_broadcast_id + normalized round_name + exact starts_at, matching the requested vis... | 2026-05-28 20:49:05 UTC | 2026-05-28 22:06:30 UTC | dagidici |
| [#196](https://github.com/Chessever/chessever-frontend/pull/196) | CLOSED | feat: scroll active bottom tab to top | Re-tapping the already-selected bottom navigation tab now emits a scroll-to-top request instead of doing nothing. Events scrolls the currently visible For You / Current / Past / Search list to the top without changing the selected subtab. Calendar and Library listen for their active-tab re-tap and scroll their current root list to the top, including Library search results. | 2026-05-28 17:40:34 UTC | 2026-05-28 22:06:27 UTC | dagidici |
| [#195](https://github.com/Chessever/chessever-frontend/pull/195) | CLOSED | Feature/event no spoilers | No PR description provided; inferred from title/branch only: Feature/event no spoilers. | 2026-05-28 11:52:02 UTC | 2026-05-28 22:06:40 UTC | dagidici |
| [#194](https://github.com/Chessever/chessever-frontend/pull/194) | CLOSED | feat: add event no-spoilers mode | Add a per-event No Spoilers toggle in the event ⋮ menu, persisted locally by event id. Hide finished-game result text/score markers in event cards and player rows while no-spoilers is enabled. Hide finished-game eval bars and suppress final board-ending animation until the user navigates to the final position from an earlier move. | 2026-05-27 17:54:44 UTC | 2026-05-27 23:07:28 UTC | dagidici |
| [#193](https://github.com/Chessever/chessever-frontend/pull/193) | CLOSED | Fix one-day event date labels | show one-day event dates as a single date instead of duplicated ranges like May 23 - 23, 2026 route calendar event detail date formatting through the shared event date formatter so detail/list behavior stays consistent add focused coverage for one-day and same-month multi-day event ranges | 2026-05-27 15:03:27 UTC | 2026-05-27 23:00:28 UTC | dagidici |
| [#192](https://github.com/Chessever/chessever-frontend/pull/192) | CLOSED | fix: keep pinned games in board order | keep pinned/auto-pinned event games promoted ahead of non-pinned games while ordering pinned peers by board number reuse the same ordering helper for normal event lists, filtered views, and knockout round sections add focused regression coverage for pinned board-order sorting and missing-board fallback behavior | 2026-05-27 15:02:18 UTC | 2026-05-27 23:00:29 UTC | dagidici |
| [#191](https://github.com/Chessever/chessever-frontend/pull/191) | CLOSED | Add phone board coordinates toggle | add a Board Coordinates toggle to phone Board Settings near the existing bottom settings persist the setting through BoardSettingsNew, local cache, and Supabase user_engine_settings.enable_coordinates apply the preference to the main phone board, gamebase board preview, and event/list board cards while keeping share/export overlays coordinate-free | 2026-05-26 17:42:00 UTC | 2026-05-27 23:11:02 UTC | dagidici |
| [#190](https://github.com/Chessever/chessever-frontend/pull/190) | CLOSED | feat: add calendar event detail favorite star | add a favorite star action to the phone Calendar community-event detail header reuse the same calendar-event favorite id/model as the month-list event cards so detail/list/Favorites stay synced truncate the header title to one line so long event names leave room for the star | 2026-05-26 16:49:26 UTC | 2026-05-27 23:13:38 UTC | dagidici |
| [#189](https://github.com/Chessever/chessever-frontend/pull/189) | CLOSED | Fix phone event refresh missing later rounds | Fetch tournament games by tour id in explicit 1000-row pages instead of relying on the default Supabase/PostgREST page. Preserve existing limit/offset behavior for callers that request a bounded page. Add a focused pagination continuation test. | 2026-05-26 15:50:16 UTC | 2026-05-27 23:14:58 UTC | dagidici |
| [#188](https://github.com/Chessever/chessever-frontend/pull/188) | CLOSED | Fix custom broadcast scoring | preserve official/source standings scores for broadcasts with custom point systems, e.g. Norway Chess classical wins worth 3 points parse per-game player customPoints and show them in the phone board/player result badge when they differ from standard chess scoring keep standard scoring unchanged when custom points are absent or equal to the normal result | 2026-05-26 15:35:39 UTC | 2026-05-27 23:17:55 UTC | dagidici |
| [#187](https://github.com/Chessever/chessever-frontend/pull/187) | CLOSED | Remove third-party product wording | Replaces remaining named third-party database product wording in comments/source labels with neutral reference/legacy database wording. Keeps the existing URL source detection behavior without exposing the product name in source text. | 2026-05-26 11:59:09 UTC | 2026-05-27 23:22:29 UTC | dagidici |
| [#186](https://github.com/Chessever/chessever-frontend/pull/186) | CLOSED | Fix duplicate grouped event notifications | Dedupe OneSignal external user IDs before every push send so a user matching both players in the same game is only targeted once. Add game/round collapse ids to notification payloads so duplicate device-level deliveries collapse for the same notification target. Keep game-start pushes scoped to favorite-player recipients only; event-starred users continue to get round/event-level notifications instead of a second... | 2026-05-26 03:05:46 UTC | 2026-05-27 23:26:01 UTC | dagidici |
| [#184](https://github.com/Chessever/chessever-frontend/pull/184) | CLOSED | fix: keep favorite current events visible in for you | Ensures favorited current events missing from the first For You page are fetched from group_broadcasts_current and merged into the initial For You feed. Keeps pagination offset based on the original Supabase page size so injected favorites do not skip later events. De-dupes later paginated results so an injected favorite cannot appear twice. Adds focused regression coverage for missing-favorite merge behavior. | 2026-05-24 19:16:01 UTC | 2026-05-27 23:27:52 UTC | dagidici |
| [#183](https://github.com/Chessever/chessever-frontend/pull/183) | CLOSED | Fix scorecard K=10 for selected 2400+ rating | Move the score-card FIDE rating-change math into a small tested helper. Lock the simple K-factor rule Vasif requested: after selecting the rating used for the calculation, any selected rating of 2400+ uses K=10. Add focused tests covering 2400/2491/2610 => K=10 and a draw vs a higher-rated opponent using the K=10 result. | 2026-05-24 14:55:03 UTC | 2026-05-27 23:30:55 UTC | dagidici |
| [#182](https://github.com/Chessever/chessever-frontend/pull/182) | CLOSED | Trust server-side standings on chess-results-flagged tours | For tours the data hub has flagged as canonically sorted by chess-results.com (info.standingsSource == 'chess-results', info.standingsUpdatedAt set), the standings UI now preserves the server's array order instead of re-computing score → Buchholz Cut-1 → rating client-side. All per-player enrichment (score, Buchholz for display, rating diff, etc.) **still runs** — only the final ordering is taken from the backend.... | 2026-05-04 18:15:14 UTC | 2026-05-04 21:16:40 UTC | devberkay |
| [#181](https://github.com/Chessever/chessever-frontend/pull/181) | CLOSED | Altering sign Evaluation Fix | Inverting sign fix Stockfish FLow | 2026-04-04 16:23:46 UTC | 2026-05-15 21:04:45 UTC | ThiruDev50 |
| [#180](https://github.com/Chessever/chessever-frontend/pull/180) | CLOSED | Remove Sentry Logs | No PR description provided; inferred from title/branch only: Remove Sentry Logs. | 2026-04-03 13:06:38 UTC | 2026-05-15 21:04:47 UTC | flutterdev77 |
| [#179](https://github.com/Chessever/chessever-frontend/pull/179) | MERGED | Fix iOS cold-start deeplink forwarding for scene lifecycle | No PR description provided; inferred from title/branch only: Fix iOS cold-start deeplink forwarding for scene lifecycle. | 2026-04-02 15:41:08 UTC | 2026-04-02 15:48:28 UTC | flutterdev77 |
| [#178](https://github.com/Chessever/chessever-frontend/pull/178) | MERGED | Fix delayed game deeplink opening and add share flow Sentry logs | No PR description provided; inferred from title/branch only: Fix delayed game deeplink opening and add share flow Sentry logs. | 2026-04-01 14:28:07 UTC | 2026-04-01 16:30:22 UTC | flutterdev77 |
| [#177](https://github.com/Chessever/chessever-frontend/pull/177) | CLOSED | Fix aggregated live notifications for favorites and starred events | No PR description provided; inferred from title/branch only: Fix aggregated live notifications for favorites and starred events. | 2026-04-01 14:27:33 UTC | 2026-05-15 21:04:49 UTC | flutterdev77 |
| [#176](https://github.com/Chessever/chessever-frontend/pull/176) | MERGED | Sentry log for deeplink | No PR description provided; inferred from title/branch only: Sentry log for deeplink. | 2026-03-31 09:03:27 UTC | 2026-03-31 21:02:47 UTC | flutterdev77 |
| [#175](https://github.com/Chessever/chessever-frontend/pull/175) | MERGED | Fix Incorrect K-factor being used for rating | No PR description provided; inferred from title/branch only: Fix Incorrect K-factor being used for rating. | 2026-03-31 08:18:53 UTC | 2026-03-31 20:55:01 UTC | flutterdev77 |
| [#174](https://github.com/Chessever/chessever-frontend/pull/174) | CLOSED | Fix starred events notified should be default | No PR description provided; inferred from title/branch only: Fix starred events notified should be default. | 2026-03-31 08:18:28 UTC | 2026-05-15 21:04:51 UTC | flutterdev77 |
| [#173](https://github.com/Chessever/chessever-frontend/pull/173) | MERGED | Change default notations to figurative from settings | No PR description provided; inferred from title/branch only: Change default notations to figurative from settings. | 2026-03-30 14:35:01 UTC | 2026-03-30 20:12:44 UTC | flutterdev77 |
| [#172](https://github.com/Chessever/chessever-frontend/pull/172) | MERGED | Remove live option | No PR description provided; inferred from title/branch only: Remove live option. | 2026-03-30 14:34:56 UTC | 2026-03-30 20:19:51 UTC | flutterdev77 |
| [#171](https://github.com/Chessever/chessever-frontend/pull/171) | MERGED | Fix Eval Bar issue | No PR description provided; inferred from title/branch only: Fix Eval Bar issue. | 2026-03-30 14:34:51 UTC | 2026-03-30 20:17:53 UTC | flutterdev77 |
| [#170](https://github.com/Chessever/chessever-frontend/pull/170) | MERGED | Fix Kasparov Issues | No PR description provided; inferred from title/branch only: Fix Kasparov Issues. | 2026-03-30 14:34:48 UTC | 2026-03-30 20:27:33 UTC | flutterdev77 |
| [#169](https://github.com/Chessever/chessever-frontend/pull/169) | MERGED | Fix link not inside the picture | No PR description provided; inferred from title/branch only: Fix link not inside the picture. | 2026-03-30 14:34:46 UTC | 2026-03-30 20:09:53 UTC | flutterdev77 |
| [#168](https://github.com/Chessever/chessever-frontend/pull/168) | MERGED | Evaluation Bar with plus and minus sign | No PR description provided; inferred from title/branch only: Evaluation Bar with plus and minus sign. | 2026-03-30 14:31:29 UTC | 2026-03-30 20:25:59 UTC | flutterdev77 |
| [#167](https://github.com/Chessever/chessever-frontend/pull/167) | MERGED | Mate bug fix | No PR description provided; inferred from title/branch only: Mate bug fix. | 2026-03-30 03:20:35 UTC | 2026-03-30 19:46:24 UTC | ThiruDev50 |
| [#166](https://github.com/Chessever/chessever-frontend/pull/166) | MERGED | Fix For You candidates should show the round that is on the top in ga… | …me list view | 2026-03-27 14:07:04 UTC | 2026-03-27 19:35:42 UTC | flutterdev77 |
| [#165](https://github.com/Chessever/chessever-frontend/pull/165) | MERGED | Deeplink Sentry Log | No PR description provided; inferred from title/branch only: Deeplink Sentry Log. | 2026-03-27 13:26:07 UTC | 2026-03-27 20:24:23 UTC | flutterdev77 |
| [#164](https://github.com/Chessever/chessever-frontend/pull/164) | MERGED | FIDE Candidates 2026 event | No PR description provided; inferred from title/branch only: FIDE Candidates 2026 event. | 2026-03-27 11:39:03 UTC | 2026-03-27 12:53:56 UTC | flutterdev77 |
| [#163](https://github.com/Chessever/chessever-frontend/pull/163) | MERGED | Forward iOS universal links to app_links in AppDelegate | No PR description provided; inferred from title/branch only:  Forward iOS universal links to app_links in AppDelegate. | 2026-03-26 12:33:19 UTC | 2026-03-26 12:43:00 UTC | flutterdev77 |
| [#162](https://github.com/Chessever/chessever-frontend/pull/162) | MERGED | Fix shared game deep links opening home instead of target game | No PR description provided; inferred from title/branch only: Fix shared game deep links opening home instead of target game. | 2026-03-26 09:58:59 UTC | 2026-03-26 10:36:25 UTC | flutterdev77 |
| [#161](https://github.com/Chessever/chessever-frontend/pull/161) | MERGED | Fix random moves on the board | No PR description provided; inferred from title/branch only: Fix random moves on the board. | 2026-03-25 16:59:27 UTC | 2026-03-25 18:15:46 UTC | flutterdev77 |
| [#160](https://github.com/Chessever/chessever-frontend/pull/160) | MERGED | Remove the Border for Open Explorer | Consistent UI across hamburger menu | 2026-03-25 15:54:56 UTC | 2026-03-25 16:06:33 UTC | flutterdev77 |
| [#159](https://github.com/Chessever/chessever-frontend/pull/159) | MERGED | Fix : Add Debugger and fix the issue in For You Tab | Add Sentry Debugger, Add a retry button and proper error handler | 2026-03-25 15:50:09 UTC | 2026-03-25 16:17:12 UTC | flutterdev77 |
| [#158](https://github.com/Chessever/chessever-frontend/pull/158) | MERGED | Align For You event games with Games tab logic | Use the same selected-tour, ordering, and pin logic as Games tab for For You events, and render the first 4 games without round headers. Also adds parity coverage for tour selection and game ordering. Fix the unpin feature in For You, Implement 0 reload for for you tab | 2026-03-25 03:58:49 UTC | 2026-03-25 07:34:18 UTC | flutterdev77 |
| [#157](https://github.com/Chessever/chessever-frontend/pull/157) | MERGED | Add a safeguard | When a free user click 4th favorite inside favorites (players), it adds a heart instead of pushing the paywall. | 2026-03-24 21:20:54 UTC | 2026-03-24 21:41:39 UTC | flutterdev77 |
| [#156](https://github.com/Chessever/chessever-frontend/pull/156) | CLOSED | Fix For You tab not updating on sub-tour selection change | Games were cached and not immediately refreshed when the user changed the sub-tour in the Games Tab. Added a ref.listen on selectedTourForEventProvider in forYouEventGamesWithAutoRefreshProvider to explicitly invalidate eventGamesProvider on selection change, mirroring the existing live-round refresh pattern. | 2026-03-24 20:46:32 UTC | 2026-03-24 22:17:18 UTC | flutterdev77 |
| [#155](https://github.com/Chessever/chessever-frontend/pull/155) | MERGED | Android Launcher Icon and Board Settings Design | Color consistent in Board Settings and Changed Android Launcher Icon | 2026-03-24 14:52:31 UTC | 2026-03-24 20:53:21 UTC | flutterdev77 |
| [#154](https://github.com/Chessever/chessever-frontend/pull/154) | MERGED | fix(notifications): align defaults and harden heads-up event filter | favoriteEventAlerts default changed false → true to match the Supabase column default — new users now see the correct opted-in state in the UI Fixed eventAllowed check in filterHeadsUpRecipients from strict === true to !== false, matching the consistent fail-open pattern used across all other filter functions | 2026-03-23 20:38:51 UTC | 2026-03-23 21:38:05 UTC | flutterdev77 |
| [#153](https://github.com/Chessever/chessever-frontend/pull/153) | MERGED | fix: shared game links, PGN copy, and share across all game sources | Games.fromJson crashed on null search column → silent home redirect getGameById used bare SELECT * instead of _gameListSelectColumns Added getGameByAnyId to resolve both Supabase UUIDs and Lichess short IDs shareGameBtnClicked fetched PGN from Supabase only, breaking TWIC/gamebase/analysis board games | 2026-03-23 20:06:07 UTC | 2026-03-25 15:14:44 UTC | flutterdev77 |
| [#152](https://github.com/Chessever/chessever-frontend/pull/152) | MERGED | Engine cold start issue | Engine warmup Cold start fix First time visibility engine eval time to 800ms Guard to prevent duplicate calls | 2026-03-23 19:16:26 UTC | 2026-03-23 22:11:09 UTC | ThiruDev50 |
| [#151](https://github.com/Chessever/chessever-frontend/pull/151) | MERGED | Default thinking time to be 5 seconds | Shift to 5 second default think timing | 2026-03-23 13:02:53 UTC | 2026-03-23 22:07:50 UTC | flutterdev77 |
| [#150](https://github.com/Chessever/chessever-frontend/pull/150) | MERGED | New Hamburger Menu | > Add a new UI for Hamburger Menu | 2026-03-23 12:15:40 UTC | 2026-03-23 21:27:16 UTC | flutterdev77 |
| [#149](https://github.com/Chessever/chessever-frontend/pull/149) | MERGED | New Explore Design | Implement new Explore Design from Figma | 2026-03-19 15:19:25 UTC | 2026-03-19 18:22:19 UTC | flutterdev77 |
| [#148](https://github.com/Chessever/chessever-frontend/pull/148) | MERGED | fix: favorites not pinning in events | Country code comparison used == instead of CountryCodeMatcher.matches(), causing ISO2/ISO3 mismatches (e.g. "GB" vs "ENG") to never pin Empty countryCode on a saved favorite now falls back to name-only match toggleFavorite() fideId guard was blocking favoritesVersionProvider bump for players without a fideId, leaving auto-pins stale | 2026-03-18 21:00:25 UTC | 2026-03-19 17:25:50 UTC | flutterdev77 |
| [#147](https://github.com/Chessever/chessever-frontend/pull/147) | MERGED | Thiru/negative sign engine issue | Fixing local stockfish negative issue | 2026-03-18 10:08:10 UTC | 2026-03-18 11:50:16 UTC | ThiruDev50 |
| [#146](https://github.com/Chessever/chessever-frontend/pull/146) | MERGED | Fix Notation and Duplicate Games | Add _deduplicateGames helper that filters by game ID, applied in _decodeGamesInIsolate (covers ~24 methods) and the two inline-decode methods (getGamesByRoundId, getGamesByPlayerName). Move numbers (e.g., "1.", "12...") were being colored the same as the move text in variation and annotation contexts. Split the move number prefix from the SAN move so only the actual move notation receives the variation/annotation... | 2026-03-17 19:18:34 UTC | 2026-03-18 20:33:42 UTC | flutterdev77 |
| [#145](https://github.com/Chessever/chessever-frontend/pull/145) | MERGED | Add per-user event notification mute toggle | Allow users to mute/unmute notifications for individual events via the 3-dot menu. Adds user_muted_events table, Riverpod provider for mute state, and edge function filtering to suppress notifications for muted events. | 2026-03-17 17:52:59 UTC | 2026-03-17 19:07:11 UTC | flutterdev77 |
| [#144](https://github.com/Chessever/chessever-frontend/pull/144) | CLOSED | Fix hot reload | No PR description provided; inferred from title/branch only: Fix hot reload. | 2026-03-17 11:01:02 UTC | 2026-05-15 21:04:54 UTC | flutterdev77 |
| [#143](https://github.com/Chessever/chessever-frontend/pull/143) | MERGED | Fix live game real-time updates for game cards and chessboard | Decouple liveGameCardProvider family key from baseGame object so polling doesn't recreate the Supabase stream — game cards now update in real-time without manual refresh Update lastSeenMoveCount when auto-jumping via wasViewingLastMove, fixing stale new-move badges Add generation guard to parseMoves() to prevent concurrent calls from overwriting fresh state with stale data | 2026-03-17 11:00:21 UTC | 2026-03-17 19:23:34 UTC | flutterdev77 |
| [#142](https://github.com/Chessever/chessever-frontend/pull/142) | MERGED | Open Feedback form after 3 app opens | No PR description provided; inferred from title/branch only: Open Feedback form after 3 app opens. | 2026-03-15 14:06:17 UTC | 2026-03-15 15:19:53 UTC | flutterdev77 |
| [#141](https://github.com/Chessever/chessever-frontend/pull/141) | MERGED | Limit 3 favorite | Limit free users to 3 favorites in onboarding and later. onboarding favoite choice, do not allow choosing after 3 | 2026-03-14 21:54:50 UTC | 2026-03-14 22:35:05 UTC | flutterdev77 |
| [#140](https://github.com/Chessever/chessever-frontend/pull/140) | MERGED | Fix castling annotation badge position | Description: When a castling move is marked as a blunder, mistake, or inaccuracy, the annotation badge is currently shown on the rook’s original square (h1, a1, h8, a8) instead of the king’s destination square (g1, c1, g8, c8). This happens because dartchess encodes castling in king-captures-rook format, and the current destination-square logic uses the move’s raw to/last square value without accounting for castli... | 2026-03-14 20:50:10 UTC | 2026-03-14 22:25:26 UTC | flutterdev77 |
| [#139](https://github.com/Chessever/chessever-frontend/pull/139) | MERGED | Fix Failed King move | Fix : https://trello.com/c/FRJER2wa/276-when-the-game-is-over-clicking-the-animated-king-and-try-to-make-move-with-king-doesnt-work | 2026-03-14 12:03:22 UTC | 2026-03-14 22:23:31 UTC | flutterdev77 |
| [#138](https://github.com/Chessever/chessever-frontend/pull/138) | MERGED | Fix the order | The full priority order is now: Session selection (in-memory) Saved selection (SQLite — persists user's explicit choice) Live tours (active games) | 2026-03-14 09:32:32 UTC | 2026-03-14 22:13:18 UTC | flutterdev77 |
| [#137](https://github.com/Chessever/chessever-frontend/pull/137) | MERGED | Fix live filter for you tab | No PR description provided; inferred from title/branch only: Fix live filter for you tab. | 2026-03-13 21:32:32 UTC | 2026-03-13 21:43:18 UTC | flutterdev77 |
| [#136](https://github.com/Chessever/chessever-frontend/pull/136) | MERGED | Fix evail bar hiding on itself | No PR description provided; inferred from title/branch only: Fix evail bar hiding on itself. | 2026-03-13 21:05:20 UTC | 2026-03-13 21:06:47 UTC | flutterdev77 |
| [#135](https://github.com/Chessever/chessever-frontend/pull/135) | MERGED | Fix the constrains, annotations style and about page | Fix constrains exceptions in About screen, Fix annotations style, Add Powered By | 2026-03-13 20:35:32 UTC | 2026-03-13 20:48:17 UTC | flutterdev77 |
| [#134](https://github.com/Chessever/chessever-frontend/pull/134) | MERGED | Flutterdev/fix question mark notation | Fix : https://trello.com/c/LBEusclm/271-fix-notation-for-signs Fix : https://trello.com/c/hmUVuXFO/274-question-marks-are-showing-for-the-next-move-that-does-not-have-question-for Fix : https://trello.com/c/EaPgPWAA/275-when-the-move-on-the-right-file-symbols-look-weird | 2026-03-13 18:36:02 UTC | 2026-03-13 19:00:21 UTC | flutterdev77 |
| [#133](https://github.com/Chessever/chessever-frontend/pull/133) | MERGED | for completed games, go to first move | for completed games, go to first move | 2026-03-13 16:00:09 UTC | 2026-03-13 18:50:38 UTC | flutterdev77 |
| [#132](https://github.com/Chessever/chessever-frontend/pull/132) | CLOSED | fix: prevent annotation badge from bleeding onto next move | Remove fallback logic that showed the previous move's annotation when the current move had none, causing question marks to appear on unannotated moves. Extract resolveBoardAnnotation into a testable function and add unit tests. | 2026-03-12 20:19:36 UTC | 2026-03-12 20:59:29 UTC | flutterdev77 |
| [#131](https://github.com/Chessever/chessever-frontend/pull/131) | MERGED | Hide Options | No PR description provided; inferred from title/branch only: Hide Options. | 2026-03-11 20:39:13 UTC | 2026-03-11 20:47:27 UTC | flutterdev77 |
| [#130](https://github.com/Chessever/chessever-frontend/pull/130) | MERGED | Paywall the Opening Explorer Player filter for non-premium users | Use ref.watch(subscriptionProvider.select((s) => s.isSubscribed)) for the premium check. Wrap const _PlayerSearchInput() with GestureDetector + AbsorbPointer for the locked state. | 2026-03-11 19:38:05 UTC | 2026-03-11 22:12:49 UTC | flutterdev77 |
| [#129](https://github.com/Chessever/chessever-frontend/pull/129) | MERGED | Fill For You events to 4 available boards | Update For You event selection to show up to four started boards per event instead of stopping at a single latest round or tour. When the primary round has fewer than four games, backfill from other started rounds or sibling tours in the same event while preserving pin priority, match-event behavior, and existing For You view modes. Also keep the 4-board cap consistent across phone and tablet rendering. | 2026-03-11 13:56:11 UTC | 2026-03-12 14:21:16 UTC | flutterdev77 |
| [#128](https://github.com/Chessever/chessever-frontend/pull/128) | MERGED | pipeline GIF export and reduce share-card memory usage | Replace the batch GIF export path with a pipelined worker-based flow. move GIF planning, worker protocol, and fallback encoding into a dedicated helper overlap frame capture and GIF encoding instead of waiting for all frames first cap memory by limiting in-flight frames instead of buffering the full export | 2026-03-11 10:37:24 UTC | 2026-03-12 14:00:10 UTC | flutterdev77 |
| [#127](https://github.com/Chessever/chessever-frontend/pull/127) | MERGED | Fix live game board opening flash by seeding initial position from FEN | Seed the live chessboard’s initial render from game.fen instead of the default starting position. This removes the brief flash to Chess.initial when opening ongoing games, while keeping PGN parsing as the source of truth for move history, navigation, and live auto-follow behavior. | 2026-03-11 08:09:02 UTC | 2026-03-12 18:42:44 UTC | flutterdev77 |
| [#126](https://github.com/Chessever/chessever-frontend/pull/126) | MERGED | Migrate legacy 5s engine thinking time to unlimited | Add a one-time per-user migration that rewrites legacy saved search_time_index=0 values to unlimited while preserving future user-selected 5s values, and align cached engine fallback defaults with the current unlimited default. | 2026-03-11 07:41:14 UTC | 2026-03-12 19:11:30 UTC | flutterdev77 |
| [#125](https://github.com/Chessever/chessever-frontend/pull/125) | MERGED | Add local-only auto-pin preferences with user-scoped SQLite storage | Introduce two global auto-pin toggles (Favorite Players: on by default, Countrymen: off by default) stored in user-scoped SQLite cache_store. Move per-tournament auto-pin disable to user-scoped storage with legacy key compatibility fallback. Add Auto Pin section to Board Settings page. | 2026-03-10 17:02:09 UTC | 2026-03-12 20:06:38 UTC | flutterdev77 |
| [#124](https://github.com/Chessever/chessever-frontend/pull/124) | CLOSED | Fix `_CountryFlag` constructor missing `super.key` | _CountryFlag was missing super.key in its constructor, triggering the use_key_in_widget_constructors lint from flutter_lints. Reintroduced super.key as an optional named parameter in _CountryFlag's constructor ```dart // Before | 2026-03-09 15:11:38 UTC | 2026-03-09 15:23:27 UTC | app/copilot-swe-agent |
| [#123](https://github.com/Chessever/chessever-frontend/pull/123) | MERGED | Fixes for Trello tasks and Figma Updates | Fixes : Heart is eliminated from current list and stars are shown, Share image now has co-ordinates, Evail bar is now shown correctly when opened from explorer, | 2026-03-09 12:26:38 UTC | 2026-03-09 17:04:34 UTC | flutterdev77 |
| [#122](https://github.com/Chessever/chessever-frontend/pull/122) | MERGED | Figma : Update in About Screen | > Add standingsUrl and tourUrl to open the link to respective domains using URL launcher Trello : https://trello.com/c/3LHxISfP/249-about-page-lichess-update | 2026-03-09 11:49:33 UTC | 2026-03-09 20:03:39 UTC | flutterdev77 |
| [#121](https://github.com/Chessever/chessever-frontend/pull/121) | CLOSED | Add Patrol signed-in mobile E2E suite | add a Patrol-based signed-in mobile E2E stack with isolated E2E startup, real Supabase test-user bootstrap, and prompt suppression add stable E2E selectors across the app and a deep support layer for seeded live-data routing, board assertions, notation taps, move traversal, and game swipes document local and Codemagic operation in patrol_test/README.md, plus root-level README entrypoints and .env.e2e.example | 2026-03-07 04:50:43 UTC | 2026-05-15 21:04:56 UTC | devberkay |
| [#120](https://github.com/Chessever/chessever-frontend/pull/120) | CLOSED | Fix event card parsing, live flag guard, and favorite-player fallback | Fix parsing of numeric fields for group broadcasts/tours so avg ELO and player data no longer disappear when Supabase returns non-int types. Add fallback to derive favorite players from games when tour player lists are empty. Prevent live dot from showing outside the event date window. | 2026-01-13 07:32:38 UTC | 2026-05-15 21:04:37 UTC | devberkay |
| [#118](https://github.com/Chessever/chessever-frontend/pull/118) | CLOSED | Subscription Setup | > Create Subscription in Google Play and App Store, > Setup and load entitlements in revenue cat and connect products from respective stores > Create Pop-up for subscription based on state, > Enable sandbox and testing, | 2025-10-26 08:47:27 UTC | 2026-05-15 21:04:58 UTC | flutterdev77 |
| [#117](https://github.com/Chessever/chessever-frontend/pull/117) | CLOSED | Flutter dev/fix duplicate team name | No PR description provided; inferred from title/branch only: Flutter dev/fix duplicate team name. | 2025-10-22 18:17:12 UTC | 2026-05-15 21:05:01 UTC | devberkay |
| [#116](https://github.com/Chessever/chessever-frontend/pull/116) | MERGED | Feature/fix group event bugs | No PR description provided; inferred from title/branch only: Feature/fix group event bugs. | 2025-10-22 18:08:20 UTC | 2025-10-22 18:08:46 UTC | devberkay |
| [#115](https://github.com/Chessever/chessever-frontend/pull/115) | CLOSED | Fix : Team Event Issue | > Fix Duplicate team Event Name, > Implement Search feature in group Event view and show result from the Entire game, > Display the Score of the team at the end, | 2025-10-22 14:11:40 UTC | 2025-10-22 18:22:24 UTC | flutterdev77 |
| [#114](https://github.com/Chessever/chessever-frontend/pull/114) | CLOSED | Fix the null issue in navigation | Send the original games list model with all the sorted games | 2025-10-22 13:27:37 UTC | 2025-10-22 18:22:37 UTC | flutterdev77 |
| [#113](https://github.com/Chessever/chessever-frontend/pull/113) | MERGED | Add missing login checker | No PR description provided; inferred from title/branch only: Add missing login checker. | 2025-10-22 13:03:35 UTC | 2025-10-22 13:37:06 UTC | flutterdev77 |
| [#112](https://github.com/Chessever/chessever-frontend/pull/112) | MERGED | Group Event Update | > Update to Normal Games Card, > Display Scores of the Game at the Top, > Display Top Rated 4 Player, else show none, > Cleanup UI and manage state and business logic in it's own provider, | 2025-10-22 07:38:28 UTC | 2025-10-22 07:50:11 UTC | flutterdev77 |
| [#111](https://github.com/Chessever/chessever-frontend/pull/111) | MERGED | Display the list of players | No PR description provided; inferred from title/branch only: Display the list of players. | 2025-10-22 00:09:55 UTC | 2025-10-22 00:10:02 UTC | devberkay |
| [#110](https://github.com/Chessever/chessever-frontend/pull/110) | MERGED | Don't display players | Hide Players in About Screen | 2025-10-21 19:49:10 UTC | 2025-10-21 23:46:59 UTC | flutterdev77 |
| [#109](https://github.com/Chessever/chessever-frontend/pull/109) | MERGED | Test pr 108 merge | No PR description provided; inferred from title/branch only: Test pr 108 merge. | 2025-10-21 15:09:24 UTC | 2025-10-21 15:09:54 UTC | devberkay |
| [#108](https://github.com/Chessever/chessever-frontend/pull/108) | MERGED | Players View Fix and update app dropdown | > Reload Players View accurately after changing tournament, > Fix the Dropdown Layout issues, | 2025-10-19 04:41:22 UTC | 2025-10-21 15:09:56 UTC | flutterdev77 |
| [#107](https://github.com/Chessever/chessever-frontend/pull/107) | CLOSED | Fix Players View | > Reload Players View accurately after changing tournament, > Fix the Dropdown Layout issues, | 2025-10-19 04:40:08 UTC | 2025-10-19 04:40:25 UTC | flutterdev77 |
| [#106](https://github.com/Chessever/chessever-frontend/pull/106) | MERGED | Fix native dependencies for downloading image | 🤖 Generated with Claude Code | 2025-10-18 19:25:33 UTC | 2025-10-18 20:44:09 UTC | devberkay |
| [#105](https://github.com/Chessever/chessever-frontend/pull/105) | MERGED | age | No PR description provided; inferred from title/branch only: age. | 2025-10-18 17:11:35 UTC | 2025-10-18 17:11:50 UTC | devberkay |
| [#104](https://github.com/Chessever/chessever-frontend/pull/104) | MERGED | Feature/complete view mode fix main3 | No PR description provided; inferred from title/branch only: Feature/complete view mode fix main3. | 2025-10-18 17:09:50 UTC | 2025-10-18 17:09:58 UTC | devberkay |
| [#103](https://github.com/Chessever/chessever-frontend/pull/103) | MERGED | Save User's selection and pre-select active tour | > The tour selected by the user if exists, > the live tournament if exists, > the tournament that completed recently | 2025-10-17 20:43:00 UTC | 2025-10-18 13:20:34 UTC | flutterdev77 |
| [#102](https://github.com/Chessever/chessever-frontend/pull/102) | MERGED | Fix Feedbacks | > Fix the Past Events long load time by caching the favorites as well, > Fix the name comparison in the reverse order or normal order, > Add Missing details for the Player Information, > Sort using the score, | 2025-10-17 16:19:13 UTC | 2025-10-17 17:19:10 UTC | flutterdev77 |
| [#101](https://github.com/Chessever/chessever-frontend/pull/101) | MERGED | make computer icon button active color white | No PR description provided; inferred from title/branch only: make computer icon button active color white. | 2025-10-17 03:21:45 UTC | 2025-10-17 03:21:58 UTC | devberkay |
| [#100](https://github.com/Chessever/chessever-frontend/pull/100) | MERGED | Feature/stabilize before analysis mode | No PR description provided; inferred from title/branch only: Feature/stabilize before analysis mode. | 2025-10-17 02:56:30 UTC | 2025-10-17 02:58:53 UTC | devberkay |
| [#99](https://github.com/Chessever/chessever-frontend/pull/99) | MERGED | Group Event Screen | > Create Switched View, > Allow Numeric Round Selection, > Create Hide Reveal Animation, | 2025-10-16 16:40:27 UTC | 2025-10-21 17:36:04 UTC | flutterdev77 |
| [#98](https://github.com/Chessever/chessever-frontend/pull/98) | MERGED | Fix Games navigation From Scorecard View | > Fix favorite -> Scorecard -> Chess Board New Screen Navigation, | 2025-10-16 14:55:27 UTC | 2025-10-17 03:19:16 UTC | flutterdev77 |
| [#97](https://github.com/Chessever/chessever-frontend/pull/97) | MERGED | Fix state for show/hide and pin | > Show, hide completed games, show all games > Unpin Fix, > Disable auto pin, enable auto pin, > Clear all pins, | 2025-10-16 10:47:45 UTC | 2025-10-16 10:51:30 UTC | flutterdev77 |
| [#96](https://github.com/Chessever/chessever-frontend/pull/96) | CLOSED | Show/Hide Games, Autopin enable/disable | > Show, hide completed games, show all games > Enable/disable autopin, > Unpin Fix | 2025-10-16 10:05:56 UTC | 2025-10-16 10:24:55 UTC | flutterdev77 |
| [#95](https://github.com/Chessever/chessever-frontend/pull/95) | MERGED | Feature/fix pv cards | No PR description provided; inferred from title/branch only: Feature/fix pv cards. | 2025-10-14 18:12:08 UTC | 2025-10-14 18:15:36 UTC | devberkay |
| [#94](https://github.com/Chessever/chessever-frontend/pull/94) | MERGED | Feature/fix clock reduntant countdown | No PR description provided; inferred from title/branch only: Feature/fix clock reduntant countdown. | 2025-10-14 18:10:26 UTC | 2025-10-14 18:17:34 UTC | devberkay |
| [#93](https://github.com/Chessever/chessever-frontend/pull/93) | MERGED | Favorite Update | No PR description provided; inferred from title/branch only: Favorite Update. | 2025-10-14 14:42:39 UTC | 2025-10-14 18:15:35 UTC | flutterdev77 |
| [#92](https://github.com/Chessever/chessever-frontend/pull/92) | MERGED | Favorites Update | > Favorite option in Players View, > Player Screen with Fav Support, > Sort based on favorite, > Cleanup Fav Logic, | 2025-10-14 06:30:22 UTC | 2025-10-14 14:42:15 UTC | flutterdev77 |
| [#91](https://github.com/Chessever/chessever-frontend/pull/91) | MERGED | Fix board behaviours | This PR includes fixes for board behaviours and streaming race conditions. | 2025-10-14 00:38:54 UTC | 2025-10-14 00:39:42 UTC | devberkay |
| [#90](https://github.com/Chessever/chessever-frontend/pull/90) | MERGED | Feature/fix board behaviours | No PR description provided; inferred from title/branch only: Feature/fix board behaviours. | 2025-10-14 00:35:16 UTC | 2025-10-14 18:14:19 UTC | devberkay |
| [#89](https://github.com/Chessever/chessever-frontend/pull/89) | MERGED | Flutter dev/favorite screen feature | > Implemented favorite screen with search feature, > Implement large heap size for android and hardware acceleration for better performance, | 2025-10-13 19:54:07 UTC | 2025-10-13 22:16:46 UTC | flutterdev77 |
| [#88](https://github.com/Chessever/chessever-frontend/pull/88) | MERGED | Feature/commentout analysis features | No PR description provided; inferred from title/branch only: Feature/commentout analysis features. | 2025-10-12 15:43:44 UTC | 2025-10-12 16:35:58 UTC | devberkay |
| [#87](https://github.com/Chessever/chessever-frontend/pull/87) | MERGED | Update Clarity initialization | > Fix Clarity initialization > Setup API keys in .env | 2025-10-11 23:17:21 UTC | 2025-10-12 05:25:52 UTC | flutterdev77 |
| [#86](https://github.com/Chessever/chessever-frontend/pull/86) | MERGED | Flutter dev/fix calendar view | > Search in calendar view, > Search and Filter Options in calendar detail view, > Reset and Favorite sorting in calendar view, | 2025-10-11 22:40:23 UTC | 2025-10-11 23:04:02 UTC | flutterdev77 |
| [#85](https://github.com/Chessever/chessever-frontend/pull/85) | MERGED | Analysis merge with main | Analysis Board and main changes merged into one | 2025-10-10 12:25:42 UTC | 2025-10-10 13:12:23 UTC | flutterdev77 |
| [#84](https://github.com/Chessever/chessever-frontend/pull/84) | MERGED | Feature/colorful notations | Analysis Feature + Move Impact Analysis ("!!","!?","!","?","??") | 2025-10-09 17:43:41 UTC | 2025-10-10 04:12:11 UTC | devberkay |
| [#83](https://github.com/Chessever/chessever-frontend/pull/83) | CLOSED | Fix moves not to be clicked | > Fix moves not being clicked when clicked on arrows, > Remove Chat icon | 2025-10-09 12:14:30 UTC | 2025-10-10 18:32:36 UTC | flutterdev77 |
| [#82](https://github.com/Chessever/chessever-frontend/pull/82) | MERGED | Flutter dev/auto pin games | > Favorites players are pinned at the top, > Country men are pinned after favorites, > If all the players are from the same country, then the pins no longer appear, > Country pins and fav pins can be unpinned, | 2025-10-08 11:13:53 UTC | 2025-10-08 12:13:05 UTC | flutterdev77 |
| [#81](https://github.com/Chessever/chessever-frontend/pull/81) | MERGED | Fix Round exception | > Sort the rounds based on date, > Cleanup old boilerplate, | 2025-10-07 19:54:17 UTC | 2025-10-08 12:00:51 UTC | flutterdev77 |
| [#80](https://github.com/Chessever/chessever-frontend/pull/80) | MERGED | Automatically manage encryption in Testflight | No PR description provided; inferred from title/branch only: Automatically manage encryption in Testflight. | 2025-10-06 20:45:21 UTC | 2025-10-07 19:55:20 UTC | flutterdev77 |
| [#79](https://github.com/Chessever/chessever-frontend/pull/79) | MERGED | Fix Freeze issue | > Load the Audios in unawaited method in a microtask and avoid parallel cache, > Update main to have proper hierarchy for less errors and deadlocks, | 2025-10-06 12:36:22 UTC | 2025-10-06 15:30:05 UTC | flutterdev77 |
| [#78](https://github.com/Chessever/chessever-frontend/pull/78) | MERGED | Fix Duplicate Star Events | > Duplicate events fix for Past Events, > Enhance favorite and reload | 2025-10-06 05:35:45 UTC | 2025-10-06 09:58:45 UTC | flutterdev77 |
| [#77](https://github.com/Chessever/chessever-frontend/pull/77) | MERGED | Group Event Optimization | > 15 mins cache for group events, > Cleanup code and view, | 2025-10-06 04:03:41 UTC | 2025-10-06 04:27:16 UTC | flutterdev77 |
| [#76](https://github.com/Chessever/chessever-frontend/pull/76) | MERGED | PGN Copy & Sort | Sort in past games PGN Copy Make sure Evaluiation is proper | 2025-10-05 16:26:42 UTC | 2025-10-05 19:10:35 UTC | ThiruDev50 |
| [#75](https://github.com/Chessever/chessever-frontend/pull/75) | MERGED | Feature : Games List Grid View and lazy building enhancement | > Add Grid View mode for games list, > Connect scroll filter, top list visible and scroll to index feature on view toggle and navigation, > Remove pre-load widgets in memory and add lazy loading approach for optimization, | 2025-10-03 19:42:47 UTC | 2025-10-03 20:08:08 UTC | flutterdev77 |
| [#74](https://github.com/Chessever/chessever-frontend/pull/74) | MERGED | Add chess analysis features with board navigation and evaluation display | Refactored local storage repository class naming for clarity Implemented analysis mode with interactive board navigation Added principal variation display for engine lines Created chess game navigator and line display components | 2025-10-01 10:48:10 UTC | 2025-10-10 13:12:24 UTC | devberkay |
| [#73](https://github.com/Chessever/chessever-frontend/pull/73) | MERGED | Update Package Name | > com.chessever.app | 2025-09-29 18:26:57 UTC | 2025-09-30 13:01:27 UTC | flutterdev77 |
| [#72](https://github.com/Chessever/chessever-frontend/pull/72) | MERGED | Fix Auth Route and cleanup auth state | No PR description provided; inferred from title/branch only: Fix Auth Route and cleanup auth state. | 2025-09-29 17:43:06 UTC | 2025-09-29 17:52:10 UTC | flutterdev77 |
| [#71](https://github.com/Chessever/chessever-frontend/pull/71) | CLOSED | Re "UI Adaptions for analysis board" | Reverts Chessever/chessever-frontend#70 | 2025-09-29 12:23:14 UTC | 2026-05-15 21:05:03 UTC | varunpvp |
| [#70](https://github.com/Chessever/chessever-frontend/pull/70) | MERGED | Revert "UI Adaptions for analysis board" | Reverts Chessever/chessever-frontend#69 | 2025-09-29 11:35:24 UTC | 2025-09-29 11:35:35 UTC | varunpvp |
| [#69](https://github.com/Chessever/chessever-frontend/pull/69) | MERGED | UI Adaptions for analysis board | Initial changes for UI Adaptations Board Theme Bottom navigation bar Settings of Analysis mode matched to the old one (Drag, zoom behaviour) | 2025-09-29 10:55:44 UTC | 2025-09-29 10:55:54 UTC | ThiruDev50 |
| [#68](https://github.com/Chessever/chessever-frontend/pull/68) | CLOSED | Inital changes for UI adaptations | Initial changes for UI Adaptations | 2025-09-29 01:32:05 UTC | 2026-05-15 21:05:06 UTC | ThiruDev50 |
| [#67](https://github.com/Chessever/chessever-frontend/pull/67) | MERGED | Fix live game clocks and evaluations | Fix live game clocks and evaluations | 2025-09-29 00:24:24 UTC | 2025-09-29 17:44:53 UTC | devberkay |
| [#66](https://github.com/Chessever/chessever-frontend/pull/66) | CLOSED | Thiru/UI adaptations for analysis board | No PR description provided; inferred from title/branch only: Thiru/UI adaptations for analysis board. | 2025-09-28 08:32:22 UTC | 2025-09-28 08:32:57 UTC | ThiruDev50 |
| [#65](https://github.com/Chessever/chessever-frontend/pull/65) | MERGED | Fix Apple and Google Sign in | > Fix Apple Sign in, > Fix Google in, | 2025-09-27 18:57:06 UTC | 2025-09-27 19:59:59 UTC | flutterdev77 |
| [#64](https://github.com/Chessever/chessever-frontend/pull/64) | MERGED | Preventing unnecessary supabase call | Preventing unnecessary supabase call When in Current screen tournament, Not rendering the other tabs (Past & Upcoming) Thus preventing.. and applicable for all the tabs Removed unnecessary function which will query entire data from a table | 2025-09-27 14:10:21 UTC | 2025-09-27 19:12:54 UTC | ThiruDev50 |
| [#63](https://github.com/Chessever/chessever-frontend/pull/63) | MERGED | Preserve Board State | > Remove autodispose from the state | 2025-09-27 08:59:57 UTC | 2025-09-27 20:01:11 UTC | flutterdev77 |
| [#62](https://github.com/Chessever/chessever-frontend/pull/62) | CLOSED | Core Analysis Board Structure and Navigation Logic | This PR introduces the foundational data structure and state management required to transform the static game preview board into a **full-featured analysis board**. The key change is the implementation of a hierarchical game structure that fully supports multiple moves and variations. ** **New Data Model (ChessGame, ChessMove, ChessLine)**: | 2025-09-27 07:04:17 UTC | 2026-05-15 21:04:37 UTC | varunpvp |
| [#61](https://github.com/Chessever/chessever-frontend/pull/61) | MERGED | Feature/fix evalbar and clocks | Fix everything regarding evalbar clocks and wrong game redirection from score card screen | 2025-09-26 19:49:52 UTC | 2025-09-26 19:58:03 UTC | devberkay |
| [#60](https://github.com/Chessever/chessever-frontend/pull/60) | MERGED | Fallback to Stockfish | > Fix the lichess api error case using local stockfish | 2025-09-26 13:07:18 UTC | 2025-09-26 19:58:49 UTC | flutterdev77 |
| [#59](https://github.com/Chessever/chessever-frontend/pull/59) | MERGED | Show or Hide games | Show or Hide finished games | 2025-09-26 02:51:57 UTC | 2025-09-26 08:46:49 UTC | ThiruDev50 |
| [#58](https://github.com/Chessever/chessever-frontend/pull/58) | MERGED | Fix Pinning Issue | > Fix the Incorrect use of Parent Widget causing grey screen in Release | 2025-09-25 13:14:39 UTC | 2025-09-25 13:18:24 UTC | flutterdev77 |
| [#57](https://github.com/Chessever/chessever-frontend/pull/57) | MERGED | Fix Pagination Issue | Remove the duplicate events created during pagination | 2025-09-25 12:01:32 UTC | 2025-09-25 13:04:34 UTC | flutterdev77 |
| [#56](https://github.com/Chessever/chessever-frontend/pull/56) | MERGED | Fix the stream of fen and last move | > use route observer to setup or destroy stream, > fix navigation and remove listeners from widgets, > update model to support stream update | 2025-09-25 11:40:32 UTC | 2025-09-25 13:05:38 UTC | flutterdev77 |
| [#55](https://github.com/Chessever/chessever-frontend/pull/55) | MERGED | Fix evaluation bar showing 0.0 and improve time streaming | Fixed evaluation validation logic to accept legitimate 0.0 evaluations (balanced positions) Resolved database constraint errors preventing eval persistence Improved error handling for Lichess API failures with proper fallback Enhanced comprehensive game streaming for real-time clock updates | 2025-09-24 17:54:40 UTC | 2025-09-24 18:15:51 UTC | devberkay |
| [#54](https://github.com/Chessever/chessever-frontend/pull/54) | MERGED | Remove three dots | > Remove 3 dots from events card and add haptic feedback, > Remove three dots from games card and fix the scacing | 2025-09-24 08:49:45 UTC | 2025-09-24 08:50:05 UTC | flutterdev77 |
| [#53](https://github.com/Chessever/chessever-frontend/pull/53) | CLOSED | Remove 3 dots | > remove 3 dots from events card and add haptic feedback on long press, -> remove 3 dots from games card and update the spacing | 2025-09-24 08:46:40 UTC | 2025-09-24 08:47:18 UTC | flutterdev77 |
| [#52](https://github.com/Chessever/chessever-frontend/pull/52) | MERGED | feat: Implement comprehensive favorites system and fix player standings | Created unified favorites system for both players and events Added dedicated favorite cards for players and events in favorites screen Implemented player games screen to display complete game history for favorited players Fixed player standings calculation to use actual Supabase games instead of local storage | 2025-09-24 00:18:33 UTC | 2025-09-24 04:19:06 UTC | devberkay |
| [#51](https://github.com/Chessever/chessever-frontend/pull/51) | MERGED | Update PGN to fen based approach for list view | > Remove pgn fetcher for games list view (board mode), > Create last_move and fen data streamer and connect to GameCard and ChessBoardFromFENNew, | 2025-09-23 21:43:48 UTC | 2025-09-24 04:19:59 UTC | flutterdev77 |
| [#50](https://github.com/Chessever/chessever-frontend/pull/50) | MERGED | Fix FIDE Elo calculation and improve score display | Corrected K-factor calculation to use standard FIDE values (K=20 for <2400, K=10 for 2400+) Removed unnecessary (W), (L), (D) letters from game results, showing only numeric scores Changed performance rating display to one decimal place for better readability 🤖 Generated with Claude Code | 2025-09-23 13:22:57 UTC | 2025-09-23 18:53:53 UTC | devberkay |
| [#49](https://github.com/Chessever/chessever-frontend/pull/49) | MERGED | Feature/fix time remaining issues | fix all time remaining issues and add live countdown for live games. | 2025-09-22 15:54:27 UTC | 2025-09-24 03:55:14 UTC | devberkay |
| [#48](https://github.com/Chessever/chessever-frontend/pull/48) | MERGED | Fix Load Background Issue | > use a listener based approach for live ids for tournaments to prevent from rebuilding, | 2025-09-22 14:30:54 UTC | 2025-09-22 15:16:24 UTC | flutterdev77 |
| [#47](https://github.com/Chessever/chessever-frontend/pull/47) | MERGED | Search Enhancement for Events | > Fix the search to have max matches >70%, > Use sql rpc for accurate result based on query | 2025-09-22 13:36:46 UTC | 2025-09-22 15:13:42 UTC | flutterdev77 |
| [#46](https://github.com/Chessever/chessever-frontend/pull/46) | MERGED | Implement Pin Feature in FEN Board | > Add Haptic Feedback on long press in Chess Board with FEN, > Show Options when long press in games Board with FEN widget, | 2025-09-22 10:39:07 UTC | 2025-09-22 13:33:50 UTC | flutterdev77 |
| [#45](https://github.com/Chessever/chessever-frontend/pull/45) | MERGED | Eval bar abrupt fix | EValuation bar abrupt fix | 2025-09-21 17:23:11 UTC | 2025-09-21 17:23:33 UTC | ThiruDev50 |
| [#44](https://github.com/Chessever/chessever-frontend/pull/44) | MERGED | Pin Feature in Search view and normal view | > Users can pin the game during search mode, > After search view is removed , the pinned items will come to top, > The Refresh cleans up the search view and gets back to normal view, > Fix the Search Overflow, | 2025-09-19 04:09:32 UTC | 2025-09-19 05:57:44 UTC | flutterdev77 |
| [#43](https://github.com/Chessever/chessever-frontend/pull/43) | MERGED | feat: preserve scroll position when returning from chessboard | Add callback mechanism to capture returned game index from chessboard Update GameCardWrapperWidget to handle navigation result Implement scrolling to returned game position in GamesListView Pass callback through component hierarchy from ContentBody to GameCard | 2025-09-18 21:30:56 UTC | 2025-09-19 04:21:19 UTC | devberkay |
| [#42](https://github.com/Chessever/chessever-frontend/pull/42) | MERGED | feat: add Shorebird integration for over-the-air updates | Integrated Shorebird for seamless app updates without app store releases Updated .gitignore to track pubspec.lock and Podfile.lock files Added shorebird.yaml configuration file Updated iOS project settings to support Shorebird | 2025-09-18 19:45:35 UTC | 2025-09-19 04:17:39 UTC | devberkay |
| [#41](https://github.com/Chessever/chessever-frontend/pull/41) | MERGED | Update chess piece sound effects | Updated piece_castling.wav Updated piece_check.wav Updated piece_checkmate.wav Updated piece_takeover.wav | 2025-09-18 11:38:05 UTC | 2025-09-18 19:47:06 UTC | devberkay |
| [#40](https://github.com/Chessever/chessever-frontend/pull/40) | MERGED | Feature/improved score card screen and bug fix page scroll forward in chessboard | No PR description provided; inferred from title/branch only: Feature/improved score card screen and bug fix page scroll forward in chessboard. | 2025-09-18 01:37:41 UTC | 2025-09-18 10:13:50 UTC | devberkay |
| [#39](https://github.com/Chessever/chessever-frontend/pull/39) | MERGED | Flutter dev/fix auth | > Add Apple Sing in configuration in .env, > Remove riverpod generator, > Update Sign in with apple, | 2025-09-17 22:25:10 UTC | 2025-09-18 10:16:30 UTC | flutterdev77 |
| [#38](https://github.com/Chessever/chessever-frontend/pull/38) | MERGED | Re-Write Games Tour Screen and Fix existing bugs | > Fix the round based filter using scrollable_positioned_list, > Changing from Fen to Games will keep the scroll position intact for the top item, > Cleanup listeners from UI and implement it on scroll controller provider, > Fix null issue for groupBroadcastProvider, | 2025-09-17 19:37:22 UTC | 2025-09-17 20:49:51 UTC | flutterdev77 |
| [#37](https://github.com/Chessever/chessever-frontend/pull/37) | MERGED | Upsert in Supabase | No PR description provided; inferred from title/branch only: Upsert in Supabase. | 2025-09-17 16:44:52 UTC | 2025-09-17 16:45:42 UTC | ThiruDev50 |
| [#36](https://github.com/Chessever/chessever-frontend/pull/36) | MERGED | Implement real-time chess clock countdown with atomic rebuilds | Add lastMoveTime field to Games and GamesTourModel with DateTime support Create date_time_provider.dart with StreamProvider for real-time updates Update GameCard and PlayerFirstRowDetailWidget with atomic HookConsumer rebuilds Implement countdown logic that only updates time text, not parent widgets | 2025-09-16 22:51:21 UTC | 2025-09-17 13:51:40 UTC | devberkay |
| [#35](https://github.com/Chessever/chessever-frontend/pull/35) | MERGED | Display Games Result based on Rounds and Fix Past Event Sorting | > Past events should be sorted based on their date of completion, > Games Search Result ordered by Rounds in Games Tab, | 2025-09-16 19:16:11 UTC | 2025-09-17 07:11:25 UTC | flutterdev77 |
| [#34](https://github.com/Chessever/chessever-frontend/pull/34) | MERGED | Fix event card search navigation - clicking on search result goes to … | …correct event Previously, when searching for events and clicking on a search result, users were always redirected to the 0th indexed event instead of the correct one. Root cause: The main events list (_groupBroadcastList) is populated from category-specific local storage, while search results come from global Supabase search. When a search result tournament wasn't found in the limited category list, the orElse fa... | 2025-09-16 18:27:51 UTC | 2025-09-16 18:29:42 UTC | devberkay |
| [#33](https://github.com/Chessever/chessever-frontend/pull/33) | MERGED | IOS Release update | > Add missing info.plist config, > Update build for release mode | 2025-09-16 17:10:33 UTC | 2025-09-16 17:45:13 UTC | flutterdev77 |
| [#32](https://github.com/Chessever/chessever-frontend/pull/32) | MERGED | Feature/fide flag and more sfx | No PR description provided; inferred from title/branch only: Feature/fide flag and more sfx. | 2025-09-16 16:59:22 UTC | 2025-09-16 17:12:01 UTC | devberkay |
| [#31](https://github.com/Chessever/chessever-frontend/pull/31) | MERGED | Mate in Eval bar | Mate in Eval bar Including new prop called mate in Principal variation | 2025-09-16 16:00:35 UTC | 2025-09-16 16:00:44 UTC | ThiruDev50 |
| [#30](https://github.com/Chessever/chessever-frontend/pull/30) | MERGED | Remove Negative evaluation | > The values of evaluation bar should not be in negative, > reduce the width of evaluation bar in games tour screen board view, | 2025-09-16 07:15:05 UTC | 2025-09-16 16:20:03 UTC | flutterdev77 |
| [#29](https://github.com/Chessever/chessever-frontend/pull/29) | MERGED | Convert UTC to local Time | Convert UTC to Local Time, Update AppBar to show local time, | 2025-09-15 13:17:35 UTC | 2025-09-15 16:31:09 UTC | flutterdev77 |
| [#28](https://github.com/Chessever/chessever-frontend/pull/28) | MERGED | Update Search Result and Enhance the Switcher Widget | > Enhance Group Search to be sorted based on Datetime, > Fix the top segmented switcher to switch the state properly based on selection, | 2025-09-15 09:31:49 UTC | 2025-09-15 12:17:02 UTC | flutterdev77 |
| [#27](https://github.com/Chessever/chessever-frontend/pull/27) | MERGED | Best moves by arrows | Best moves indicated by arrows in Analysis mode as well Normal mode | 2025-09-14 15:21:36 UTC | 2025-09-14 15:22:13 UTC | ThiruDev50 |
| [#26](https://github.com/Chessever/chessever-frontend/pull/26) | MERGED | Don't Throw Exception on null check | > Update the state to be in loading if the Id is null, > Remove exception and pass the null id in the notifier, | 2025-09-14 08:16:05 UTC | 2025-09-14 12:00:03 UTC | flutterdev77 |
| [#25](https://github.com/Chessever/chessever-frontend/pull/25) | MERGED | Fix missing country flags for chess federation codes | Add comprehensive federation code to ISO country code mapping (180+ codes) (Taken from FIDE website) Update LocationService.getValidCountryCode() with multiple fallback strategies Fix GameCard widget to use mapped country code instead of raw federation code Ensure flags display correctly for players like Bluebaum, Matthias (GER -> DE) | 2025-09-12 22:02:37 UTC | 2025-09-12 22:16:34 UTC | devberkay |
| [#24](https://github.com/Chessever/chessever-frontend/pull/24) | MERGED | Improve game dropdown readability in chess board screen | Increase dropdown width from 200w to 300w for better readability Implement smart name formatting that prioritizes full names over abbreviation Progressive abbreviation logic that preserves family names while shortening first/middle names only when necessary Different width constraints for dropdown header vs items for optimal space usage | 2025-09-12 19:47:40 UTC | 2025-09-12 22:17:11 UTC | devberkay |
| [#23](https://github.com/Chessever/chessever-frontend/pull/23) | MERGED | Pin Feature update and Fix wrong game PGN data | > Save pin to local storage based on tournament id, > Fix unexpected scroll on pinning game, > Fix wrong game PGN data, > Enhance the search mechanism, | 2025-09-12 19:31:20 UTC | 2025-09-12 22:15:20 UTC | flutterdev77 |
| [#22](https://github.com/Chessever/chessever-frontend/pull/22) | MERGED | Add results display for finished games on board and list view | Modified PlayerFirstRowDetailWidget to show game results (1, 0, ½) for finished games when at the latest move Refactored widget to accept GamesTourModel and calculate player data internally 🤖 Commit Comments Generated with Claude Code | 2025-09-12 18:29:16 UTC | 2025-09-12 19:18:39 UTC | devberkay |
| [#21](https://github.com/Chessever/chessever-frontend/pull/21) | MERGED | Fix Search and pin feature and update the Group Event Screen | > Fix search dismiss feature, > Enhance Round filtering, > Fix Pin feature > Update Group Event to be Paginated for Past Tab, | 2025-09-12 12:42:24 UTC | 2025-09-12 14:23:53 UTC | flutterdev77 |
| [#20](https://github.com/Chessever/chessever-frontend/pull/20) | MERGED | Add chessboard sound effects functionality | Add AudioPlayerService singleton for managing sound effects Integrate flutter_soloud package for audio playback Add piece_move.wav sound effect asset Implement sound on chess moves in chess_board_screen_new.dart | 2025-09-12 09:22:18 UTC | 2025-09-12 09:34:23 UTC | devberkay |
| [#19](https://github.com/Chessever/chessever-frontend/pull/19) | MERGED | Update search to game screen | > Cleanup and update the screen | 2025-09-11 15:41:26 UTC | 2025-09-11 15:41:37 UTC | flutterdev77 |
| [#18](https://github.com/Chessever/chessever-frontend/pull/18) | MERGED | Update games tour screen | > Fix the riverpod flow, > Directly pass the model instead of a new riverpod for id, | 2025-09-11 09:11:50 UTC | 2025-09-11 09:12:00 UTC | flutterdev77 |
| [#17](https://github.com/Chessever/chessever-frontend/pull/17) | MERGED | Flutter dev/updates and fixes | > Combined Search feature using Supabase, > Update Upcoming View, > Create Past Tab, > Cleanup Riverpod and structure more properly | 2025-09-10 14:51:48 UTC | 2025-09-10 14:51:57 UTC | flutterdev77 |
| [#16](https://github.com/Chessever/chessever-frontend/pull/16) | MERGED | Stockfish cascade fix | Removed stockfish singleton - Cancel old evaluation & only priortize new evaluation Provider cache fix upsert in postion tables for safety | 2025-09-07 14:52:58 UTC | 2025-09-07 14:54:03 UTC | ThiruDev50 |
| [#15](https://github.com/Chessever/chessever-frontend/pull/15) | CLOSED | Cascasde eval | No PR description provided; inferred from title/branch only: Cascasde eval. | 2025-09-07 14:44:32 UTC | 2025-09-07 14:52:41 UTC | ThiruDev50 |
| [#14](https://github.com/Chessever/chessever-frontend/pull/14) | MERGED | Fix chessboard order of games to be correct | No PR description provided; inferred from title/branch only: Fix chessboard order of games to be correct. | 2025-09-06 08:12:48 UTC | 2025-09-07 16:53:49 UTC | flutterdev77 |
| [#13](https://github.com/Chessever/chessever-frontend/pull/13) | MERGED | Board Updates and Country Selector Updates | > Setup initial Fen data, > Add Error catchers for country selection button, > Enhance Games Tour Screen to load once for the same session and for same game, | 2025-09-02 20:56:14 UTC | 2025-09-03 10:48:28 UTC | flutterdev77 |
| [#12](https://github.com/Chessever/chessever-frontend/pull/12) | MERGED | Skipping evaluation for analysis mode | Skipping evaluation for analysis mode | 2025-09-02 14:01:03 UTC | 2025-09-02 14:01:11 UTC | ThiruDev50 |
| [#11](https://github.com/Chessever/chessever-frontend/pull/11) | MERGED | Initial changes for analysis mode | Initial changes for analysis mode | 2025-09-02 13:48:50 UTC | 2025-09-02 13:48:59 UTC | ThiruDev50 |
| [#10](https://github.com/Chessever/chessever-frontend/pull/10) | CLOSED | Analysis mode beta | No PR description provided; inferred from title/branch only: Analysis mode beta. | 2025-09-02 13:07:48 UTC | 2025-09-02 13:49:24 UTC | ThiruDev50 |
| [#9](https://github.com/Chessever/chessever-frontend/pull/9) | MERGED | Evail bar fixes and tournament screen updates | > Fix the evaluation bar not to bounce off, > Create a no tournament found screen, | 2025-09-01 20:11:32 UTC | 2025-09-02 19:32:54 UTC | flutterdev77 |
| [#8](https://github.com/Chessever/chessever-frontend/pull/8) | MERGED | Flutter dev/cleanup optimize | > Cleanup and enhance Favorite, > Fix the move to next move in board, > Fix latest round to appear at the top in Games Screen, > Cleanup games app bar logic | 2025-08-31 20:12:10 UTC | 2025-09-01 10:38:05 UTC | flutterdev77 |
| [#7](https://github.com/Chessever/chessever-frontend/pull/7) | MERGED | Flutter dev/cleanup optimize | > Remove old dart files, > Relocate Files and Folder in their respective sub-directory, > Rename and Refactor | 2025-08-30 19:33:07 UTC | 2025-08-31 01:42:17 UTC | flutterdev77 |
| [#6](https://github.com/Chessever/chessever-frontend/pull/6) | MERGED | Board theme and Tournament name fix | Board theme Width for tournament name | 2025-08-27 16:04:51 UTC | 2025-08-27 16:04:59 UTC | ThiruDev50 |
| [#5](https://github.com/Chessever/chessever-frontend/pull/5) | MERGED | ChessBoard from FEN using chessground package | ChessBoardFromFen widget using chessground package | 2025-08-24 14:12:45 UTC | 2025-08-24 14:19:13 UTC | ThiruDev50 |
| [#4](https://github.com/Chessever/chessever-frontend/pull/4) | MERGED | Replacing Board with chessground package | using chessground package Inlcuding dartchess package for supporting functionalities | 2025-08-24 13:51:52 UTC | 2025-08-24 13:52:00 UTC | ThiruDev50 |
| [#3](https://github.com/Chessever/chessever-frontend/pull/3) | MERGED | Improvements in sliding board | Improvements in Sliding board Better view for Tournament selection Changes for these Tasks: https://www.notion.so/Sliding-on-the-board-should-be-improved-23ba1076c72a80b9b672cb978ea0f718 | 2025-08-17 14:16:19 UTC | 2025-08-17 17:07:32 UTC | ThiruDev50 |
| [#2](https://github.com/Chessever/chessever-frontend/pull/2) | CLOSED | Switch to Chessground board and dartchess logic | replace AdvancedChessBoard with Chessground widget migrate chess logic to dartchess Game objects remove legacy advanced_chess_board package and update dependencies | 2025-08-16 14:20:57 UTC | 2025-09-27 07:04:25 UTC | hwuebben |
| [#1](https://github.com/Chessever/chessever-frontend/pull/1) | MERGED | only relevant tournaments | created a view in supabase that entails only the relevant tournaments. pull from this view. | 2025-07-13 22:12:10 UTC | 2025-07-14 09:13:34 UTC | hwuebben |

## Details

### #212 Feat/pip

- URL: https://github.com/Chessever/chessever-frontend/pull/212
- State: OPEN
- Author: arunn10 (Arun N)
- Branch: feat/pip -> dev
- Created: 2026-06-03 16:18:13 UTC
- Updated: 2026-06-03 16:18:13 UTC
- Completed: Not done / open
- Merge commit: n/a
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feat/pip.

PR description:

_No PR description provided._

---

### #211 fix: rank phone engine arrow prominence

- URL: https://github.com/Chessever/chessever-frontend/pull/211
- State: OPEN
- Author: dagidici
- Branch: fix/phone-engine-arrow-hierarchy -> dev
- Created: 2026-06-02 15:19:30 UTC
- Updated: 2026-06-02 15:22:28 UTC
- Completed: Not done / open
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Keeps the existing engine arrow count and color ordering intact. Adds rank-based opacity and chessground arrow scale so the first recommendation is thickest/most prominent and lower-ranked arrows progressively soften. Applies the same visual hierarchy to normal PV arrows and threats-mode arrows without adding labels.

PR description:

## Summary
- Keeps the existing engine arrow count and color ordering intact.
- Adds rank-based opacity and chessground arrow scale so the first recommendation is thickest/most prominent and lower-ranked arrows progressively soften.
- Applies the same visual hierarchy to normal PV arrows and threats-mode arrows without adding labels.

## Validation
- `flutter analyze --no-pub lib/screens/chessboard/provider/chess_board_screen_provider_new.dart`
- `git diff --check`

## QA
- Open a phone board with engine analysis and max 5 arrows enabled.
- Confirm arrow colors/order are unchanged.
- Confirm the 1st arrow is visually dominant, then 2nd/3rd/4th/5th progressively thinner/softer.

---

### #210 fix: show opening game count cue on player Games tab

- URL: https://github.com/Chessever/chessever-frontend/pull/210
- State: OPEN
- Author: dagidici
- Branch: fix/phone-player-opening-count-badge -> dev
- Created: 2026-06-02 02:20:40 UTC
- Updated: 2026-06-02 02:34:30 UTC
- Completed: Not done / open
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Shows a temporary game-count cue on the player profile Games tab after selecting an opening from About, e.g. Games 56. Clears the cue when the Games tab is opened or the opening filter is removed. Keeps the existing in-Games filter/count UI as the primary detail view.

PR description:

## Summary
- Shows a temporary game-count cue on the player profile Games tab after selecting an opening from About, e.g. `Games 56`.
- Clears the cue when the Games tab is opened or the opening filter is removed.
- Keeps the existing in-Games filter/count UI as the primary detail view.

## Validation
- `flutter analyze lib/screens/player_profile/player_profile_screen.dart lib/screens/player_profile/tabs/player_about_tab.dart`
- `git diff --check`

Note: `dart format --output=none --set-exit-if-changed` on these large legacy files reports formatter changes outside this narrow patch; broad formatter churn was not committed.

---

### #209 Add My Likes organization tools

- URL: https://github.com/Chessever/chessever-frontend/pull/209
- State: OPEN
- Author: dagidici
- Branch: feature/phone-my-likes-database-tools -> dev
- Created: 2026-06-01 23:26:55 UTC
- Updated: 2026-06-01 23:26:56 UTC
- Completed: Not done / open
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Rename the special liked-games database presentation to **My Likes** with a heart icon and no manual add/rename controls. Add premium-gated search/filter/sort/tag/export tools for My Likes, with export moved into the 3-dot menu. Add official personal tags to the Save Analysis / edit sheet and persist them through saved analysis reload/update flows. Preserve My Likes as an automatic like/unlike database by disablin...

PR description:

## Summary
- Rename the special liked-games database presentation to **My Likes** with a heart icon and no manual add/rename controls.
- Add premium-gated search/filter/sort/tag/export tools for My Likes, with export moved into the 3-dot menu.
- Add official personal tags to the Save Analysis / edit sheet and persist them through saved analysis reload/update flows.
- Preserve My Likes as an automatic like/unlike database by disabling swipe-delete inside that protected view.
- Update the board save action icon toward the save-sheet/bookmark style.

## Verification
- `dart format --set-exit-if-changed lib/repository/library/library_repository.dart lib/screens/chessboard/chess_board_screen_new.dart lib/screens/chessboard/provider/chess_board_screen_provider_new.dart lib/screens/chessboard/widgets/save_analysis_sheet.dart lib/screens/library/folder_contents_screen.dart lib/screens/library/utils/load_saved_analysis.dart lib/screens/library/widgets/folder_card.dart`
- `flutter analyze --no-pub lib/screens/library/folder_contents_screen.dart lib/screens/library/widgets/folder_card.dart lib/repository/library/library_repository.dart lib/screens/chessboard/widgets/save_analysis_sheet.dart lib/screens/chessboard/provider/chess_board_screen_provider_new.dart lib/screens/library/utils/load_saved_analysis.dart lib/screens/chessboard/chess_board_screen_new.dart` — exits 0; reports existing warnings/infos in `chess_board_screen_new.dart` only.
- `flutter test --no-pub` — not clean on this branch; observed existing unrelated failures in `gamebase_explorer_filter_paywall_test.dart`, `notation_token_builder_test.dart`, and `widget_test.dart`.

## QA notes for Berkay
- Open Library -> My Likes: title should show **My Likes**, heart icon, no plus/add and no rename/edit action.
- Free user: tapping search/tag/filter/export should show paywall; search should not filter the list.
- Premium user: search, tag chips, sort/filter, and export should work inside My Likes.
- Like/unlike a game from board: membership should still be automatic; My Likes entries should not be manually swipe-deleted.
- Save Analysis/edit saved game: Tags row appears under Game Details, supports the official tags, and persists after reopening the saved analysis.

---

### #208 Fix round-start pushes before moves

- URL: https://github.com/Chessever/chessever-frontend/pull/208
- State: OPEN
- Author: dagidici
- Branch: fix/round-start-move-gated -> dev
- Created: 2026-06-01 18:36:14 UTC
- Updated: 2026-06-01 18:40:16 UTC
- Completed: Not done / open
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Requires an actual game move (games.last_move_time) before queuing or dispatching round_started push notifications. Adds an Edge Function safety net so already-queued false starts are skipped as round_not_live_yet instead of sent. Adjusts round-start event naming so grouped multi-section events can include the raw tour section, while single/non-grouped events avoid redundant Open labeling. Adds regression coverage...

PR description:

## Summary
- Requires an actual game move (`games.last_move_time`) before queuing or dispatching `round_started` push notifications.
- Adds an Edge Function safety net so already-queued false starts are skipped as `round_not_live_yet` instead of sent.
- Adjusts round-start event naming so grouped multi-section events can include the raw tour section, while single/non-grouped events avoid redundant `Open` labeling.
- Adds regression coverage for move-gating and round-start title formatting.

## Why
The Norway Chess 2026 Armageddon round row was scheduled, but no Armageddon game had moved yet. The previous queue logic used `rounds.starts_at`, which allowed a false “first moves have been played” push.

## Validation
- `/opt/data/home/.local/bin/pytest test_notification_dispatch_dedupe.py -q` ✅
- `git diff --check` ✅
- `deno check supabase/functions/onesignal-dispatch/index.ts` not run: `deno` is not installed in this Hermes environment.

## QA / rollout notes
- Deploy the new Supabase migration and redeploy `onesignal-dispatch` together.
- Verify a scheduled Armageddon/tiebreak round with zero moved games stays unsent/skipped.
- Verify the same round sends only after at least one game has `last_move_time`.
- For grouped events, verify the displayed event label is specific only when multiple non-combined sections exist; single/non-grouped `Open` events should not get an extra `Open` suffix.

---

### #207 Fix phone Events search relevance for historical queries

- URL: https://github.com/Chessever/chessever-frontend/pull/207
- State: OPEN
- Author: dagidici
- Branch: fix/phone-events-search-relevance -> dev
- Created: 2026-06-01 17:05:52 UTC
- Updated: 2026-06-01 17:08:16 UTC
- Completed: Not done / open
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Tightens phone Events tournament relevance scoring for specific multi-token searches like norway chess 2015. Keeps close event-name matches such as Norway Chess 2026, but filters out generic chess-only/current-event matches such as unrelated championships. Re-scores Supabase event search results before displaying them instead of treating every backend result as an equal 100 score, then sorts by relevance before date.

PR description:

## Summary
- Tightens phone Events tournament relevance scoring for specific multi-token searches like `norway chess 2015`.
- Keeps close event-name matches such as `Norway Chess 2026`, but filters out generic chess-only/current-event matches such as unrelated championships.
- Re-scores Supabase event search results before displaying them instead of treating every backend result as an equal `100` score, then sorts by relevance before date.

## Test Plan
- `flutter test --no-pub test/search_scorer_test.dart`
- `flutter analyze --no-pub lib/widgets/search/search_scorer.dart lib/screens/group_event/providers/supabase_combined_search_provider.dart test/search_scorer_test.dart`
- `git diff --check`

## QA
- Search Events for `norway chess 2015` on phone.
- Expected: Norway Chess-related results may appear, but unrelated current events should not fill the list just because they contain generic terms like “Chess”.

---

### #206 fix: refresh Android board audio after resume

- URL: https://github.com/Chessever/chessever-frontend/pull/206
- State: OPEN
- Author: dagidici
- Branch: fix/phone-board-sound-resume -> dev
- Created: 2026-05-31 17:48:18 UTC
- Updated: 2026-06-01 19:11:56 UTC
- Completed: Not done / open
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Refreshes the Android SoLoud engine/assets after the app truly backgrounds and resumes. Keeps transient inactive/hidden states ignored, matching the previous fix that avoided teardown during short lifecycle transitions. Forces asset flags to clear on forced initialization even if SoLoud no longer reports initialized, so stale handles cannot be reused.

PR description:

## Summary
- Refreshes the Android SoLoud engine/assets after the app truly backgrounds and resumes.
- Keeps transient inactive/hidden states ignored, matching the previous fix that avoided teardown during short lifecycle transitions.
- Forces asset flags to clear on forced initialization even if SoLoud no longer reports initialized, so stale handles cannot be reused.

## Root cause / why
Android can return from a real background pause with SoLoud still reporting `isInitialized`, while the native output session or loaded handles no longer produce board SFX. The existing resume logic skipped recovery in that state because it only reinitialized when `isInitialized == false`.

## Validation
- `dart format --set-exit-if-changed lib/utils/audio_player_service.dart`
- `flutter analyze --no-pub lib/utils/audio_player_service.dart`
- `git diff --check HEAD~1 HEAD`

## QA
Please verify on Android device:
1. Open a game with board sound enabled.
2. Switch to other apps and leave Chess Ever backgrounded for a while.
3. Return to Chess Ever.
4. Move/navigate moves and confirm board SFX still plays.

Berkay should review before merge.

---

### #205 Fix board move taps toggling liked games

- URL: https://github.com/Chessever/chessever-frontend/pull/205
- State: OPEN
- Author: dagidici
- Branch: fix/phone-liked-save-overlay -> dev
- Created: 2026-05-31 17:16:22 UTC
- Updated: 2026-05-31 17:24:45 UTC
- Completed: Not done / open
- Merge commit: n/a
- Labels: none
- Purpose / what it does: suppress the board double-tap like/unlike shortcut when the gesture is actually tap-to-move input track the two board squares involved in a quick tap sequence and ignore like/unlike if the first tap selected the side-to-move piece and the second tap lands on another square/piece keep true same-square double-tap available for like/unlike

PR description:

## Summary
- suppress the board double-tap like/unlike shortcut when the gesture is actually tap-to-move input
- track the two board squares involved in a quick tap sequence and ignore like/unlike if the first tap selected the side-to-move piece and the second tap lands on another square/piece
- keep true same-square double-tap available for like/unlike

## Testing
- dart format --set-exit-if-changed lib/screens/chessboard/chess_board_screen_new.dart
- flutter analyze --no-pub lib/screens/chessboard/chess_board_screen_new.dart *(fails only on pre-existing warnings/infos elsewhere in the file; no changed-line issues)*
- git diff --check

---

### #204 Fix TWIC player event titles (recover parent event from Site URL)

- URL: https://github.com/Chessever/chessever-frontend/pull/204
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: fix/twic-event-grouping-site-slug -> dev
- Created: 2026-05-31 14:15:57 UTC
- Updated: 2026-05-31 14:16:12 UTC
- Completed: 2026-05-31 14:16:10 UTC
- Merge commit: 17db9bcfd394f6e1d777933cdf6d5d9e5f03afbf
- Labels: none
- Purpose / what it does: #200 tried to recover the canonical parent event by reading tour_id / tournament_id / tourSlug from gamebase player-games rows. **Those fields do not exist** on any gamebase row (verified live against service.chessever.com). For round-labeled broadcast games the PGN Event is a per-round pairing label (e.g. Round 7: Nazli, Sertan - Akal, Muhammed Furkan), so #200's helper returned that label unchanged — the bug rem...

PR description:

Supersedes #200.

## Problem
#200 tried to recover the canonical parent event by reading `tour_id` / `tournament_id` / `tourSlug` from gamebase player-games rows. **Those fields do not exist** on any gamebase row (verified live against `service.chessever.com`). For round-labeled broadcast games the PGN `Event` is a per-round pairing label (e.g. `Round 7: Nazli, Sertan - Akal, Muhammed Furkan`), so #200's helper returned that label unchanged — the bug remained. Its tests only passed because they hand-fed `tourSlug`, a path real data never hits.

## Fix
The canonical parent event survives only in the Lichess `Site` URL:
`https://lichess.org/broadcast/<parent-slug>/round-N/<roundId>/<chapterId>`.
- `eventTitleFromBroadcastSite()` extracts `<parent-slug>` and title-cases it (collapsing `--` separators).
- `preferredTwicEventTitle()` gains a `site` param, used as the fallback before the raw round label.
- Threaded `site` into both TWIC game builders and the board info sheet. Player-events grouping already keys off `tourSlug` (now the parent name), so rounds collapse into one event card.

Builds on #200's commits (kept its round-label detection + grouping scaffold).

## Verification
- `flutter test test/twic_event_identity_test.dart` (7 pass, incl. real Akal/Drogheda site cases)
- `flutter analyze` touched files — only pre-existing legacy warnings, no new issues
- Verified live: player `b21543df…` games all carry `Site` broadcast URLs and no tour fields

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

### #203 Fix phone stale live round ordering

- URL: https://github.com/Chessever/chessever-frontend/pull/203
- State: CLOSED
- Author: dagidici
- Branch: fix/phone-live-round-freshness -> dev
- Created: 2026-05-31 11:28:15 UTC
- Updated: 2026-05-31 13:49:03 UTC
- Completed: 2026-05-31 13:49:03 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Adds time-control-specific freshness checks for phone live-round status: blitz 10m, rapid 20m, standard/classical 120m. Treats recent move activity as the live signal even when backend live_round_ids is stale, so old rounds like Saturday Night Blitz Round 2 stop staying pinned above newer active rounds. Recomputes round status when game last_move_time changes and reselects the best auto round unless the user manua...

PR description:

## Summary
- Adds time-control-specific freshness checks for phone live-round status: blitz 10m, rapid 20m, standard/classical 120m.
- Treats recent move activity as the live signal even when backend `live_round_ids` is stale, so old rounds like Saturday Night Blitz Round 2 stop staying pinned above newer active rounds.
- Recomputes round status when game `last_move_time` changes and reselects the best auto round unless the user manually selected a round.

## Test Plan
- `flutter test test/tour_detail_round_ordering_test.dart`
- `dart format --set-exit-if-changed lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart test/tour_detail_round_ordering_test.dart`
- `flutter analyze --no-pub lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart test/tour_detail_round_ordering_test.dart`
- `flutter analyze --no-pub lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart` *(reports existing legacy `avoid_print`, unused helper, and empty-catch warnings; no new type errors from this change)*
- `git diff --check`

## QA
- Open a live/preplanned blitz event with a stale backend live round and newer move activity in a later round.
- Confirm the stale round no longer appears at the top unless it has move activity within 10 minutes.
- Confirm rapid uses a 20-minute freshness window and standard/classical uses a 120-minute window.

Requested reviewer: @devberkay

---

### #202 Fix phone forward arrow engine move fallback

- URL: https://github.com/Chessever/chessever-frontend/pull/202
- State: MERGED
- Author: dagidici
- Branch: fix/phone-analysis-arrow-no-engine-fallthrough -> dev
- Created: 2026-05-31 02:02:06 UTC
- Updated: 2026-05-31 13:54:20 UTC
- Completed: 2026-05-31 13:54:17 UTC
- Merge commit: cc09a20926afa7aab19a20ca1ed2e28bbbdd2ac8
- Labels: none
- Purpose / what it does: Removes the phone bottom-nav right-arrow fallback that appended/played an engine/PV move at the end of notation. Keeps the arrow limited to real notation navigation or already-active PV-preview navigation. Leaves explicit PV/engine UI actions as the only path for inserting/committing engine moves.

PR description:

## Summary
- Removes the phone bottom-nav right-arrow fallback that appended/played an engine/PV move at the end of notation.
- Keeps the arrow limited to real notation navigation or already-active PV-preview navigation.
- Leaves explicit PV/engine UI actions as the only path for inserting/committing engine moves.

## Validation
- `flutter analyze --no-pub lib/screens/chessboard/chess_board_screen_new.dart` *(reports existing warnings/infos in this legacy file; no new errors from this change)*
- `flutter test --no-pub test/chess_game_navigator_variation_test.dart`
- `git diff --check`

## Notes for QA
- In phone notation mode, go to the end of the current notation and tap the forward arrow: it should stop/disable and must not create an engine/PV move.
- If PV preview is already active, arrows should still navigate within the preview line while moves remain available.

## Known baseline caveats
- `dart format --output=none --set-exit-if-changed lib/screens/chessboard/chess_board_screen_new.dart` wants to reformat unrelated legacy lines in the large file, so I avoided broad formatter churn.
- `flutter test --no-pub test/notation_token_builder_test.dart` has pre-existing failures unrelated to this diff.

---

### #201 fix: keep save icon for liked games

- URL: https://github.com/Chessever/chessever-frontend/pull/201
- State: MERGED
- Author: dagidici
- Branch: fix/phone-liked-save-overlay -> dev
- Created: 2026-05-30 23:02:55 UTC
- Updated: 2026-05-31 13:55:14 UTC
- Completed: 2026-05-31 13:55:12 UTC
- Merge commit: cc79535baccd96af944af69abedc0944e14aa26e
- Labels: none
- Purpose / what it does: Keeps the game header save/edit action visible during double-tap like animations. Shows liked state only as the small red heart badge on the save/edit button. Updates like-flight comments so future changes do not reintroduce full-heart replacement in the AppBar.

PR description:

## Summary
- Keeps the game header save/edit action visible during double-tap like animations.
- Shows liked state only as the small red heart badge on the save/edit button.
- Updates like-flight comments so future changes do not reintroduce full-heart replacement in the AppBar.

## Test Plan
- `flutter pub get`
- `flutter analyze --no-pub lib/screens/chessboard/chess_board_screen_new.dart lib/screens/chessboard/widgets/like_flight.dart` *(reports existing warnings/infos in `chess_board_screen_new.dart`; no new errors from this change)*
- `git diff --check`

## QA
- Open an unliked game: header should show the normal save/edit icon with no heart badge.
- Double-tap the board to like: the save/edit icon should stay visible and only gain the small red heart badge.
- Swipe/open another unliked game: it should still show the normal save/edit icon, not a full red heart.

---

### #200 Fix TWIC player event titles

- URL: https://github.com/Chessever/chessever-frontend/pull/200
- State: CLOSED
- Author: dagidici
- Branch: fix/phone-twic-event-grouping -> dev
- Created: 2026-05-30 16:19:19 UTC
- Updated: 2026-05-31 14:16:07 UTC
- Completed: 2026-05-31 14:16:07 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: prefer canonical TWIC event names from player-game rows when PGN Event is only a round/pairing label build TWIC player Events tab from canonical game grouping to avoid showing each round as a separate event add TWIC event identity helper tests

PR description:

## Summary
- prefer canonical TWIC event names from player-game rows when PGN Event is only a round/pairing label
- build TWIC player Events tab from canonical game grouping to avoid showing each round as a separate event
- add TWIC event identity helper tests

## Test plan
- flutter test test/twic_event_identity_test.dart
- flutter analyze lib/screens/player_profile/utils/twic_event_identity.dart lib/screens/player_profile/provider/player_profile_provider.dart lib/screens/player_profile/tabs/player_events_tab.dart test/twic_event_identity_test.dart

## QA
- Search player -> select TWIC -> open games list -> open board -> tap i; title should be parent event, not Round 13/pairing label
- Player statistics Events tab for TWIC should group games by parent event instead of one card per round

---

### #199 Split phone Library folders and databases

- URL: https://github.com/Chessever/chessever-frontend/pull/199
- State: MERGED
- Author: dagidici
- Branch: feature/phone-folder-database-model -> dev
- Created: 2026-05-30 01:04:28 UTC
- Updated: 2026-05-31 14:27:11 UTC
- Completed: 2026-05-31 14:27:08 UTC
- Merge commit: f59f9593dabb6d8e7e9da563f02a4663e63aebf0
- Labels: none
- Purpose / what it does: Splits the phone Library model into explicit folder/database node types (nodeType) so folders are organizational and databases hold games. Updates Library creation, card/menu labels, folder contents, save-analysis, add-to-library, bulk add, and PGN import flows to use only databases as save/import targets. Adds a safe Supabase migration mirroring the desktop cleanup for legacy mixed nodes, plus a regression test f...

PR description:

## Summary
- Splits the phone Library model into explicit folder/database node types (`nodeType`) so folders are organizational and databases hold games.
- Updates Library creation, card/menu labels, folder contents, save-analysis, add-to-library, bulk add, and PGN import flows to use only databases as save/import targets.
- Adds a safe Supabase migration mirroring the desktop cleanup for legacy mixed nodes, plus a regression test for legacy/default node type handling.

## Product rules preserved
- Folders can contain folders/databases, but do not directly contain games.
- Databases contain games and are the only save/import targets.
- User-facing copy avoids “subdatabase” / “database inside database” language.
- Legacy hybrid nodes are split safely rather than preserved as hybrids.

## Validation
- `flutter analyze lib/repository/library/library_repository.dart lib/repository/library/models/library_folder.dart lib/repository/library/models/library_folder.mapper.dart lib/screens/chessboard/widgets/save_analysis_sheet.dart lib/screens/library/folder_contents_screen.dart lib/screens/library/library_screen.dart lib/screens/library/providers/library_folders_provider.dart lib/screens/library/utils/folder_pgn_exporter.dart lib/screens/library/widgets/add_to_folder_sheet.dart lib/screens/library/widgets/add_to_library_sheet.dart lib/screens/library/widgets/bulk_add_to_folder_sheet.dart lib/screens/library/widgets/create_folder_dialog.dart lib/screens/library/widgets/folder_card.dart lib/screens/library/widgets/import_pgn_to_folder_sheet.dart test/library_folder_node_type_test.dart`
- `flutter test test/library_folder_node_type_test.dart`
- `git diff --check`

## Notes
- This is the phone-app counterpart to the desktop folder/database cleanup so both platforms use the same Library model.
- Desktop PR reference: Chessever/chessever_frontend_desktop#79

---

### #198 Fix Norway Chess scoring display

- URL: https://github.com/Chessever/chessever-frontend/pull/198
- State: MERGED
- Author: dagidici
- Branch: fix/norway-scoring-display -> dev
- Created: 2026-05-29 00:53:54 UTC
- Updated: 2026-05-31 14:11:07 UTC
- Completed: 2026-05-31 14:11:06 UTC
- Merge commit: bd62d94fba857825eae9576c1e7673d0eadc317c
- Labels: none
- Purpose / what it does: preserve per-player custom broadcast points from game player JSON into player cards show Norway classical custom points on board rows (3-0 wins, 1-1 draws) keep Armageddon board rows simple as 1-0, while player scorecards can show the 0.5 bonus preserve official source standings scores instead of recalculating custom broadcasts as standard chess points

PR description:

## Summary
- preserve per-player custom broadcast points from game player JSON into player cards
- show Norway classical custom points on board rows (3-0 wins, 1-1 draws)
- keep Armageddon board rows simple as 1-0, while player scorecards can show the 0.5 bonus
- preserve official source standings scores instead of recalculating custom broadcasts as standard chess points

## Verification
- dart format lib/utils/broadcast_custom_scoring.dart lib/screens/chessboard/widgets/player_first_row_detail_widget.dart lib/screens/standings/score_card_screen.dart test/broadcast_custom_scoring_test.dart
- flutter test test/broadcast_custom_scoring_test.dart
- flutter analyze lib/utils/broadcast_custom_scoring.dart lib/screens/chessboard/widgets/player_first_row_detail_widget.dart lib/screens/standings/score_card_screen.dart test/broadcast_custom_scoring_test.dart

---

### #197 Fix grouped round-start notification dedupe metadata

- URL: https://github.com/Chessever/chessever-frontend/pull/197
- State: CLOSED
- Author: dagidici
- Branch: fix/grouped-round-start-followup -> dev
- Created: 2026-05-28 20:49:05 UTC
- Updated: 2026-05-28 22:06:31 UTC
- Completed: 2026-05-28 22:06:30 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Follow-up to PR #186 / Berkay local notification dedupe work; this is additive and does not replace the existing dispatcher changes. Includes round_name and starts_at in round-start notification data, so the existing sent-row duplicate check has the metadata it compares. Tightens grouped round-start collapse/dedupe identity to group_broadcast_id + normalized round_name + exact starts_at, matching the requested vis...

PR description:

## Summary
- Follow-up to PR #186 / Berkay local notification dedupe work; this is additive and does not replace the existing dispatcher changes.
- Includes `round_name` and `starts_at` in round-start notification data, so the existing sent-row duplicate check has the metadata it compares.
- Tightens grouped round-start collapse/dedupe identity to `group_broadcast_id + normalized round_name + exact starts_at`, matching the requested visible round identity and avoiding accidental collapse of distinct named rounds.
- Adds a Supabase migration that updates `queue_round_start_notifications()` to use the same grouped visible-round dedupe key shape.
- Extends focused regression coverage for the follow-up behavior.

## Why
PR #186 / Berkay's local follow-up already added the main notification dedupe pieces on `dev`, but the dispatcher compared prior sent rows by `payload.starts_at` while sent round-start notification data did not include `starts_at`. This follow-up makes that duplicate check deterministic and aligned with the visible-event rule: one visible grouped round-start notification = one push.

## Validation
- `pytest -q test_notification_dispatch_dedupe.py` — 8 passed
- `python3 -m py_compile test_notification_dispatch_dedupe.py`
- `git diff --check HEAD~1 HEAD`
- `npm --cache /tmp/npm-cache exec --yes --package=esbuild esbuild -- supabase/functions/onesignal-dispatch/index.ts --bundle --platform=neutral --format=esm '--external:jsr:*' '--external:npm:*' --outfile=/tmp/onesignal-dispatch-followup-check.js`

## Notes
- Base: `dev`, because the PR #186/Berkay notification dedupe pieces are already present on `origin/dev` and not on `origin/main`.
- Scope is intentionally narrow: no notification wording/UI/preference changes, no unrelated push categories, no production data mutation.

---

### #196 feat: scroll active bottom tab to top

- URL: https://github.com/Chessever/chessever-frontend/pull/196
- State: CLOSED
- Author: dagidici
- Branch: feature/bottom-nav-retap-scroll-top -> main
- Created: 2026-05-28 17:40:34 UTC
- Updated: 2026-05-28 22:06:28 UTC
- Completed: 2026-05-28 22:06:27 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Re-tapping the already-selected bottom navigation tab now emits a scroll-to-top request instead of doing nothing. Events scrolls the currently visible For You / Current / Past / Search list to the top without changing the selected subtab. Calendar and Library listen for their active-tab re-tap and scroll their current root list to the top, including Library search results.

PR description:

## Summary
- Re-tapping the already-selected bottom navigation tab now emits a scroll-to-top request instead of doing nothing.
- Events scrolls the currently visible For You / Current / Past / Search list to the top without changing the selected subtab.
- Calendar and Library listen for their active-tab re-tap and scroll their current root list to the top, including Library search results.

## Test Plan
- `dart format --set-exit-if-changed lib/screens/home/widget/bottom_nav_bar.dart lib/screens/group_event/group_event_screen.dart lib/screens/calendar/calendar_screen.dart lib/screens/library/library_screen.dart lib/screens/library/widgets/library_search_results_view.dart test/bottom_nav_bar_retap_test.dart`
- `flutter analyze --no-fatal-infos --no-fatal-warnings lib/screens/home/widget/bottom_nav_bar.dart lib/screens/group_event/group_event_screen.dart lib/screens/calendar/calendar_screen.dart lib/screens/library/library_screen.dart lib/screens/library/widgets/library_search_results_view.dart test/bottom_nav_bar_retap_test.dart` *(passes with existing non-fatal warnings/infos in touched files)*
- `flutter test test/bottom_nav_bar_retap_test.dart`

## Notes for reviewer
- Pull-to-refresh behavior is untouched; this only animates the active scroll controller to offset 0.
- Switching to a different bottom tab keeps the existing navigation analytics behavior.
- Re-tapping Events preserves the active Events subtab and only scrolls that visible list.

Review requested: @devberkay

---

### #195 Feature/event no spoilers

- URL: https://github.com/Chessever/chessever-frontend/pull/195
- State: CLOSED
- Author: dagidici
- Branch: feature/event-no-spoilers -> main
- Created: 2026-05-28 11:52:02 UTC
- Updated: 2026-05-28 22:06:40 UTC
- Completed: 2026-05-28 22:06:40 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feature/event no spoilers.

PR description:

_No PR description provided._

---

### #194 feat: add event no-spoilers mode

- URL: https://github.com/Chessever/chessever-frontend/pull/194
- State: CLOSED
- Author: dagidici
- Branch: feature/event-no-spoilers -> main
- Created: 2026-05-27 17:54:44 UTC
- Updated: 2026-05-27 23:07:28 UTC
- Completed: 2026-05-27 23:07:28 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Add a per-event No Spoilers toggle in the event ⋮ menu, persisted locally by event id. Hide finished-game result text/score markers in event cards and player rows while no-spoilers is enabled. Hide finished-game eval bars and suppress final board-ending animation until the user navigates to the final position from an earlier move.

PR description:

## Summary
- Add a per-event `No Spoilers` toggle in the event `⋮` menu, persisted locally by event id.
- Hide finished-game result text/score markers in event cards and player rows while no-spoilers is enabled.
- Hide finished-game eval bars and suppress final board-ending animation until the user navigates to the final position from an earlier move.

## Test Plan
- `dart format lib/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart`
- `git diff --check`
- `flutter analyze lib/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart` ✅
- `flutter analyze lib/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart lib/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart lib/screens/tour_detail/games_tour/widgets/game_card.dart lib/screens/chessboard/widgets/chess_board_from_fen_new.dart lib/screens/chessboard/widgets/player_first_row_detail_widget.dart lib/screens/chessboard/chess_board_screen_new.dart` ⚠️ reports existing warnings/infos in large touched files; no new compile errors.

## Notes
- Synced/rebased against `origin/main` before opening.
- Scope is intentionally local to event surfaces, not a global Settings toggle.

---

### #193 Fix one-day event date labels

- URL: https://github.com/Chessever/chessever-frontend/pull/193
- State: CLOSED
- Author: dagidici
- Branch: fix/one-day-event-date-label -> main
- Created: 2026-05-27 15:03:27 UTC
- Updated: 2026-05-27 23:00:28 UTC
- Completed: 2026-05-27 23:00:28 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: show one-day event dates as a single date instead of duplicated ranges like May 23 - 23, 2026 route calendar event detail date formatting through the shared event date formatter so detail/list behavior stays consistent add focused coverage for one-day and same-month multi-day event ranges

PR description:

## Summary
- show one-day event dates as a single date instead of duplicated ranges like `May 23 - 23, 2026`
- route calendar event detail date formatting through the shared event date formatter so detail/list behavior stays consistent
- add focused coverage for one-day and same-month multi-day event ranges

## Tests
- `git diff --check`
- `flutter test test/time_utils_test.dart`
- `flutter analyze lib/utils/time_utils.dart lib/screens/calendar/calendar_event_detail_screen.dart test/time_utils_test.dart`

---

### #192 fix: keep pinned games in board order

- URL: https://github.com/Chessever/chessever-frontend/pull/192
- State: CLOSED
- Author: dagidici
- Branch: fix/phone-pinned-games-board-order -> main
- Created: 2026-05-27 15:02:18 UTC
- Updated: 2026-05-27 23:00:29 UTC
- Completed: 2026-05-27 23:00:29 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: keep pinned/auto-pinned event games promoted ahead of non-pinned games while ordering pinned peers by board number reuse the same ordering helper for normal event lists, filtered views, and knockout round sections add focused regression coverage for pinned board-order sorting and missing-board fallback behavior

PR description:

## Summary
- keep pinned/auto-pinned event games promoted ahead of non-pinned games while ordering pinned peers by board number
- reuse the same ordering helper for normal event lists, filtered views, and knockout round sections
- add focused regression coverage for pinned board-order sorting and missing-board fallback behavior

## Test Plan
- `git diff --check`
- `flutter test test/game_display_sort_test.dart`
- `flutter analyze lib/screens/tour_detail/games_tour/utils/game_display_sort.dart test/game_display_sort_test.dart`
- `flutter analyze lib/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart lib/screens/tour_detail/games_tour/widgets/games_tour_content_body.dart lib/screens/tour_detail/games_tour/utils/game_display_sort.dart test/game_display_sort_test.dart` *(reports pre-existing issues in `games_tour_content_body.dart`: unnecessary non-null assertion and existing `print` calls; new helper/test are clean)*

## Acceptance
- pinned games stay above non-pinned games
- within the pinned group, Board 10 appears before Board 20 regardless of pin/auto-pin creation order
- non-pinned games continue below in board order

---

### #191 Add phone board coordinates toggle

- URL: https://github.com/Chessever/chessever-frontend/pull/191
- State: CLOSED
- Author: dagidici
- Branch: feature/phone-board-coordinates-toggle -> main
- Created: 2026-05-26 17:42:00 UTC
- Updated: 2026-05-27 23:11:03 UTC
- Completed: 2026-05-27 23:11:02 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: add a Board Coordinates toggle to phone Board Settings near the existing bottom settings persist the setting through BoardSettingsNew, local cache, and Supabase user_engine_settings.enable_coordinates apply the preference to the main phone board, gamebase board preview, and event/list board cards while keeping share/export overlays coordinate-free

PR description:

## Summary
- add a Board Coordinates toggle to phone Board Settings near the existing bottom settings
- persist the setting through BoardSettingsNew, local cache, and Supabase `user_engine_settings.enable_coordinates`
- apply the preference to the main phone board, gamebase board preview, and event/list board cards while keeping share/export overlays coordinate-free

## Tests
- `flutter test --no-pub test/board_settings_coordinates_test.dart`
- `flutter analyze --no-pub lib/providers/board_settings_provider_new.dart lib/repository/board_settings/models/board_settings_model.dart lib/repository/board_settings/models/board_settings_model.mapper.dart lib/screens/chessboard/chess_board_settings_page.dart lib/screens/gamebase/gamebase_explorer_screen.dart test/board_settings_coordinates_test.dart`
- `git diff --check`

Note: a broader focused analyze that includes legacy large board widgets still reports pre-existing warnings in `chess_board_screen_new.dart` and `chess_board_from_fen_new.dart`; the new coordinates/model/settings subset is clean.

---

### #190 feat: add calendar event detail favorite star

- URL: https://github.com/Chessever/chessever-frontend/pull/190
- State: CLOSED
- Author: dagidici
- Branch: feature/phone-calendar-event-detail-star -> main
- Created: 2026-05-26 16:49:26 UTC
- Updated: 2026-05-27 23:13:38 UTC
- Completed: 2026-05-27 23:13:38 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: add a favorite star action to the phone Calendar community-event detail header reuse the same calendar-event favorite id/model as the month-list event cards so detail/list/Favorites stay synced truncate the header title to one line so long event names leave room for the star

PR description:

## Summary
- add a favorite star action to the phone Calendar community-event detail header
- reuse the same calendar-event favorite id/model as the month-list event cards so detail/list/Favorites stay synced
- truncate the header title to one line so long event names leave room for the star

## Testing
- `git diff --check`
- `flutter analyze lib/screens/calendar/calendar_event_detail_screen.dart test/screens/calendar/calendar_event_detail_screen_test.dart`
- `flutter test test/screens/calendar/calendar_event_detail_screen_test.dart`

Note: direct push to `Chessever/chessever-frontend` was denied for `dagidici`, so this branch is pushed from the fork.

---

### #189 Fix phone event refresh missing later rounds

- URL: https://github.com/Chessever/chessever-frontend/pull/189
- State: CLOSED
- Author: dagidici
- Branch: fix/phone-event-rounds-fetch-all -> main
- Created: 2026-05-26 15:50:16 UTC
- Updated: 2026-05-27 23:14:58 UTC
- Completed: 2026-05-27 23:14:58 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Fetch tournament games by tour id in explicit 1000-row pages instead of relying on the default Supabase/PostgREST page. Preserve existing limit/offset behavior for callers that request a bounded page. Add a focused pagination continuation test.

PR description:

## Summary
- Fetch tournament games by tour id in explicit 1000-row pages instead of relying on the default Supabase/PostgREST page.
- Preserve existing limit/offset behavior for callers that request a bounded page.
- Add a focused pagination continuation test.

## Why
Large live broadcasts such as Titled Tuesday can exceed the default 1000-row response. The phone app then keeps refreshing/reopening the event with only the first page of games, so later live rounds do not appear even though desktop can show them.

## Tests
- `git diff --check`
- `flutter test test/game_repository_tour_games_pagination_test.dart`
- `flutter analyze lib/repository/supabase/game/game_repository.dart test/game_repository_tour_games_pagination_test.dart` *(fails on pre-existing warnings/infos in game_repository.dart: avoid_print, unnecessary_null_comparison/type_check, unused_element; no new issue from the changed pagination helper/path observed)*

---

### #188 Fix custom broadcast scoring

- URL: https://github.com/Chessever/chessever-frontend/pull/188
- State: CLOSED
- Author: dagidici
- Branch: fix/broadcast-custom-scoring -> main
- Created: 2026-05-26 15:35:39 UTC
- Updated: 2026-05-27 23:17:55 UTC
- Completed: 2026-05-27 23:17:55 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: preserve official/source standings scores for broadcasts with custom point systems, e.g. Norway Chess classical wins worth 3 points parse per-game player customPoints and show them in the phone board/player result badge when they differ from standard chess scoring keep standard scoring unchanged when custom points are absent or equal to the normal result

PR description:

## Summary
- preserve official/source standings scores for broadcasts with custom point systems, e.g. Norway Chess classical wins worth 3 points
- parse per-game player customPoints and show them in the phone board/player result badge when they differ from standard chess scoring
- keep standard scoring unchanged when custom points are absent or equal to the normal result

## Tests
- flutter analyze lib/utils/broadcast_custom_scoring.dart lib/repository/supabase/game/games.dart lib/screens/tour_detail/games_tour/models/games_tour_model.dart lib/screens/tour_detail/player_tour/player_tour_screen_provider.dart lib/screens/chessboard/widgets/player_first_row_detail_widget.dart test/broadcast_custom_scoring_test.dart
- flutter test test/broadcast_custom_scoring_test.dart

---

### #187 Remove third-party product wording

- URL: https://github.com/Chessever/chessever-frontend/pull/187
- State: CLOSED
- Author: dagidici
- Branch: chore/remove-third-party-product-wording -> main
- Created: 2026-05-26 11:59:09 UTC
- Updated: 2026-05-27 23:22:29 UTC
- Completed: 2026-05-27 23:22:29 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Replaces remaining named third-party database product wording in comments/source labels with neutral reference/legacy database wording. Keeps the existing URL source detection behavior without exposing the product name in source text.

PR description:

## Summary
- Replaces remaining named third-party database product wording in comments/source labels with neutral reference/legacy database wording.
- Keeps the existing URL source detection behavior without exposing the product name in source text.

## Why
Vasif asked us to reduce avoidable trademark/copying optics in public GitHub text.

## Verification
- `git grep -i -n "<removed third-party product term>" -- . ':(exclude)pubspec.lock' ':(exclude).dart_tool' ':(exclude)build'` → no matches
- `flutter analyze lib/screens/chessboard/widgets/save_analysis_sheet.dart lib/utils/location_service_provider.dart`
- `git diff --check`

---

### #186 Fix duplicate grouped event notifications

- URL: https://github.com/Chessever/chessever-frontend/pull/186
- State: CLOSED
- Author: dagidici
- Branch: fix/favorite-notification-dedupe -> main
- Created: 2026-05-26 03:05:46 UTC
- Updated: 2026-05-27 23:26:01 UTC
- Completed: 2026-05-27 23:26:01 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Dedupe OneSignal external user IDs before every push send so a user matching both players in the same game is only targeted once. Add game/round collapse ids to notification payloads so duplicate device-level deliveries collapse for the same notification target. Keep game-start pushes scoped to favorite-player recipients only; event-starred users continue to get round/event-level notifications instead of a second...

PR description:

## Summary
- Dedupe OneSignal external user IDs before every push send so a user matching both players in the same game is only targeted once.
- Add game/round collapse ids to notification payloads so duplicate device-level deliveries collapse for the same notification target.
- Keep game-start pushes scoped to favorite-player recipients only; event-starred users continue to get round/event-level notifications instead of a second game-start push.
- Collapse grouped-event round-start notifications by exact `group_broadcast_id + starts_at`, so Open/Women/Combined tours starting at the same time produce one visible start push.
- Suppress `round_finished` result notifications for tours named/sluggified as `Combined`, while keeping real Open/Women event-result notifications and favorite game-result notifications intact.

## Tests
- `pytest -q test_notification_dispatch_dedupe.py`
- `python3 -m py_compile test_notification_dispatch_dedupe.py`
- `git diff --check`
- `npm --cache /tmp/npm-cache exec --yes --package=esbuild esbuild -- supabase/functions/onesignal-dispatch/index.ts --bundle --platform=neutral --format=esm --external:jsr:* --external:npm:* --outfile=/tmp/onesignal-dispatch-check.js`

---

### #184 fix: keep favorite current events visible in for you

- URL: https://github.com/Chessever/chessever-frontend/pull/184
- State: CLOSED
- Author: dagidici
- Branch: fix/for-you-live-event-ranking -> main
- Created: 2026-05-24 19:16:01 UTC
- Updated: 2026-05-27 23:27:53 UTC
- Completed: 2026-05-27 23:27:52 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Ensures favorited current events missing from the first For You page are fetched from group_broadcasts_current and merged into the initial For You feed. Keeps pagination offset based on the original Supabase page size so injected favorites do not skip later events. De-dupes later paginated results so an injected favorite cannot appear twice. Adds focused regression coverage for missing-favorite merge behavior.

PR description:

## Summary
- Ensures favorited current events missing from the first For You page are fetched from `group_broadcasts_current` and merged into the initial For You feed.
- Keeps pagination offset based on the original Supabase page size so injected favorites do not skip later events.
- De-dupes later paginated results so an injected favorite cannot appear twice.
- Adds focused regression coverage for missing-favorite merge behavior.

## Why
Vasif saw `Olimpiada Nacional CONADE San Luis Potosí...` at the top of Current but had a hard time finding it in For You. The For You feed paginates the first 20 current broadcasts before favorite sorting, so a user-favorited/current event outside that DB page can be absent from the initial For You list even though it is prominent in Current.

## Test plan
- [x] `flutter test test/for_you_games_provider_test.dart`
- [x] `flutter analyze lib/providers/for_you_games_provider.dart lib/repository/supabase/group_broadcast/group_tour_repository.dart test/for_you_games_provider_test.dart`
- [x] `git diff --check`

---

### #183 Fix scorecard K=10 for selected 2400+ rating

- URL: https://github.com/Chessever/chessever-frontend/pull/183
- State: CLOSED
- Author: dagidici
- Branch: fix/rating-k10-current-2400 -> main
- Created: 2026-05-24 14:55:03 UTC
- Updated: 2026-05-27 23:30:55 UTC
- Completed: 2026-05-27 23:30:55 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Move the score-card FIDE rating-change math into a small tested helper. Lock the simple K-factor rule Vasif requested: after selecting the rating used for the calculation, any selected rating of 2400+ uses K=10. Add focused tests covering 2400/2491/2610 => K=10 and a draw vs a higher-rated opponent using the K=10 result.

PR description:

## Summary
- Move the score-card FIDE rating-change math into a small tested helper.
- Lock the simple K-factor rule Vasif requested: after selecting the rating used for the calculation, any selected rating of 2400+ uses K=10.
- Add focused tests covering 2400/2491/2610 => K=10 and a draw vs a higher-rated opponent using the K=10 result.

## Scope
This intentionally does not implement the historical sticky-K case for players who once crossed 2400 and later dropped below 2400. It only fixes/locks the current selected-rating >= 2400 rule.

## Test plan
- `git diff --check`
- `flutter analyze lib/screens/standings/utils/fide_rating_change.dart lib/screens/standings/score_card_screen.dart test/standings/fide_rating_change_test.dart`
- `flutter test test/standings/fide_rating_change_test.dart`

---

### #182 Trust server-side standings on chess-results-flagged tours

- URL: https://github.com/Chessever/chessever-frontend/pull/182
- State: CLOSED
- Author: devberkay (Berkay Can)
- Branch: feature/use-server-standings-when-available -> dev
- Created: 2026-05-04 18:15:14 UTC
- Updated: 2026-05-04 21:16:40 UTC
- Completed: 2026-05-04 21:16:40 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: For tours the data hub has flagged as canonically sorted by chess-results.com (info.standingsSource == 'chess-results', info.standingsUpdatedAt set), the standings UI now preserves the server's array order instead of re-computing score → Buchholz Cut-1 → rating client-side. All per-player enrichment (score, Buchholz for display, rating diff, etc.) **still runs** — only the final ordering is taken from the backend....

PR description:

## Summary
- For tours the data hub has flagged as canonically sorted by chess-results.com (`info.standingsSource == 'chess-results'`, `info.standingsUpdatedAt` set), the standings UI now preserves the server's array order instead of re-computing `score → Buchholz Cut-1 → rating` client-side.
- All per-player enrichment (score, Buchholz for display, rating diff, etc.) **still runs** — only the final ordering is taken from the backend. So cells render the same; only the ranking changes.
- Adds two fields to `_TourInfo` (`standingsSource`, `standingsUpdatedAt`) and two getters on `Tour` (`usesExternalStandings`, `standingsSourceLabel`).

## Companion PR / release requirement
- Must ship together with [chessever-data-hub#20](https://github.com/Chessever/chessever-data-hub/pull/20) for the visible standings fix.
- Data-hub #20 writes and preserves the marker fields; this frontend PR consumes those markers and skips the client-side re-sort.
- This frontend PR is forward-compatible by itself: until data-hub #20 is deployed and at least one tour has been reordered, no tour has `usesExternalStandings == true`, so behavior is unchanged.
- No PostgreSQL migration is required for this feature; the marker fields live inside existing `tours.info` JSONB.

## When this kicks in
Trust server order **only** when:
- Exactly one tour is in scope (skips multi-tour pagination categories like "Boards 1-66" + "Boards 67-126" that concat independent standings), AND
- That tour has both marker fields set.

Falls back to the existing client-side sort for:
- Past tours from before the data-hub PR was deployed (no marker)
- Live tours mid-round-1 where no game has finished + 20 min yet (no marker)
- Tours with non-chess-results standings sources

## Backed by
- [chessever-data-hub#19](https://github.com/Chessever/chessever-data-hub/pull/19) — the reorder code (already merged)
- [chessever-data-hub#20](https://github.com/Chessever/chessever-data-hub/pull/20) — adds and preserves the marker fields (open)

## Realistic blast radius
~3,265 of 8,368 tours have a chess-results.com URL, but only ~38 are live + ~13 ended in last 24h at any given moment. Those ~50 tours are the rolling window where this code path actually activates.

## Followups (out of scope here)
- Add a small visible "Source: chess-results.com" affordance on the standings header. The Tour model already exposes `standingsSourceLabel` for this; left out so design can pick the placement and styling.

## Test plan
- [ ] After data-hub #20 deploys: open a live broadcast with a chess-results.com URL where at least one game finished >20 min ago. Standings should match the order on `chess-results.com/tnrXXXXX.aspx`, not the local Buchholz computation.
- [ ] Open a finished tour from last week — standings come from client-side calc (marker absent because reorder never fired for that tour).
- [ ] Open a tour with no `info.standings` (or a non-chess-results URL) — behavior unchanged.
- [ ] Open a multi-tour pagination category — falls back to client-side sort.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

### #181 Altering sign Evaluation Fix

- URL: https://github.com/Chessever/chessever-frontend/pull/181
- State: CLOSED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/Altering_Sign_Evaluation_Fix -> dev
- Created: 2026-04-04 16:23:46 UTC
- Updated: 2026-05-15 21:05:18 UTC
- Completed: 2026-05-15 21:04:45 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Inverting sign fix Stockfish FLow

PR description:

- Inverting sign fix
- Stockfish FLow

---

### #180 Remove Sentry Logs

- URL: https://github.com/Chessever/chessever-frontend/pull/180
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/removeSentryLogs -> dev
- Created: 2026-04-03 13:06:38 UTC
- Updated: 2026-05-15 21:07:14 UTC
- Completed: 2026-05-15 21:04:47 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Remove Sentry Logs.

PR description:

_No PR description provided._

---

### #179 Fix iOS cold-start deeplink forwarding for scene lifecycle

- URL: https://github.com/Chessever/chessever-frontend/pull/179
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fixSceneLifecycle -> dev
- Created: 2026-04-02 15:41:08 UTC
- Updated: 2026-04-02 15:48:36 UTC
- Completed: 2026-04-02 15:48:28 UTC
- Merge commit: f03a0f6f9470e7ce76d5fe6c6ecd6b764c4da0b1
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix iOS cold-start deeplink forwarding for scene lifecycle.

PR description:

_No PR description provided._

---

### #178 Fix delayed game deeplink opening and add share flow Sentry logs

- URL: https://github.com/Chessever/chessever-frontend/pull/178
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/deeplinkIssueFix -> dev
- Created: 2026-04-01 14:28:07 UTC
- Updated: 2026-04-01 16:30:25 UTC
- Completed: 2026-04-01 16:30:22 UTC
- Merge commit: e5d383d57e709def98ca9e39ffeb3f1fac6e28c9
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix delayed game deeplink opening and add share flow Sentry logs.

PR description:

_No PR description provided._

---

### #177 Fix aggregated live notifications for favorites and starred events

- URL: https://github.com/Chessever/chessever-frontend/pull/177
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/notifications -> dev
- Created: 2026-04-01 14:27:33 UTC
- Updated: 2026-05-15 21:07:13 UTC
- Completed: 2026-05-15 21:04:49 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix aggregated live notifications for favorites and starred events.

PR description:

_No PR description provided._

---

### #176 Sentry log for deeplink

- URL: https://github.com/Chessever/chessever-frontend/pull/176
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/sentryLog -> dev
- Created: 2026-03-31 09:03:27 UTC
- Updated: 2026-03-31 21:02:50 UTC
- Completed: 2026-03-31 21:02:47 UTC
- Merge commit: 8fbc67763ea6b68987b08f5b4ddf1f46f0a9457b
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Sentry log for deeplink.

PR description:

_No PR description provided._

---

### #175 Fix Incorrect K-factor being used for rating

- URL: https://github.com/Chessever/chessever-frontend/pull/175
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/incorrectK-factor -> dev
- Created: 2026-03-31 08:18:53 UTC
- Updated: 2026-03-31 20:55:12 UTC
- Completed: 2026-03-31 20:55:01 UTC
- Merge commit: 1cf87b73d51b66e3d66ccc94d225fe95424f6ef7
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix Incorrect K-factor being used for rating.

PR description:

_No PR description provided._

---

### #174 Fix starred events notified should be default

- URL: https://github.com/Chessever/chessever-frontend/pull/174
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/starredEvents -> dev
- Created: 2026-03-31 08:18:28 UTC
- Updated: 2026-05-15 21:07:16 UTC
- Completed: 2026-05-15 21:04:51 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix starred events notified should be default.

PR description:

_No PR description provided._

---

### #173 Change default notations to figurative from settings

- URL: https://github.com/Chessever/chessever-frontend/pull/173
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/changeDefaultNotations -> dev
- Created: 2026-03-30 14:35:01 UTC
- Updated: 2026-03-30 20:12:48 UTC
- Completed: 2026-03-30 20:12:44 UTC
- Merge commit: 7ade3a63dd7f30e6c30b483296e55d7b2ce76e47
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Change default notations to figurative from settings.

PR description:

_No PR description provided._

---

### #172 Remove live option

- URL: https://github.com/Chessever/chessever-frontend/pull/172
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/removeLiveOption -> dev
- Created: 2026-03-30 14:34:56 UTC
- Updated: 2026-03-30 20:19:55 UTC
- Completed: 2026-03-30 20:19:51 UTC
- Merge commit: 26b69b0e1521b76de7e790b3922e0d3dd5c156ff
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Remove live option.

PR description:

_No PR description provided._

---

### #171 Fix Eval Bar issue

- URL: https://github.com/Chessever/chessever-frontend/pull/171
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fixEvalBarIssue -> dev
- Created: 2026-03-30 14:34:51 UTC
- Updated: 2026-03-30 20:17:57 UTC
- Completed: 2026-03-30 20:17:53 UTC
- Merge commit: 30ddc54f74b56f05ec219b335b64a907668bc53f
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix Eval Bar issue.

PR description:

_No PR description provided._

---

### #170 Fix Kasparov Issues

- URL: https://github.com/Chessever/chessever-frontend/pull/170
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fixKasparovIssues -> dev
- Created: 2026-03-30 14:34:48 UTC
- Updated: 2026-03-30 20:27:37 UTC
- Completed: 2026-03-30 20:27:33 UTC
- Merge commit: d6d46a07535fe2c7f532ba1736c2e7b3ec98650b
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix Kasparov Issues.

PR description:

_No PR description provided._

---

### #169 Fix link not inside the picture

- URL: https://github.com/Chessever/chessever-frontend/pull/169
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fixLinkInsidePicture -> dev
- Created: 2026-03-30 14:34:46 UTC
- Updated: 2026-03-30 20:09:57 UTC
- Completed: 2026-03-30 20:09:53 UTC
- Merge commit: 3851aaed32b1a11d4d69c644a4ea6d47b49fad65
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix link not inside the picture.

PR description:

_No PR description provided._

---

### #168 Evaluation Bar with plus and minus sign

- URL: https://github.com/Chessever/chessever-frontend/pull/168
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/evaluationBar -> dev
- Created: 2026-03-30 14:31:29 UTC
- Updated: 2026-03-30 20:26:01 UTC
- Completed: 2026-03-30 20:25:59 UTC
- Merge commit: c0e37642e32bac917c7060498601b320e0fc680f
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Evaluation Bar with plus and minus sign.

PR description:

_No PR description provided._

---

### #167 Mate bug fix

- URL: https://github.com/Chessever/chessever-frontend/pull/167
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/Mate_Bug_Fix -> dev
- Created: 2026-03-30 03:20:35 UTC
- Updated: 2026-03-30 19:46:27 UTC
- Completed: 2026-03-30 19:46:24 UTC
- Merge commit: ddd0c0381a83edf9db48d22375de546c4c7d805e
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Mate bug fix.

PR description:

_No PR description provided._

---

### #166 Fix For You candidates should show the round that is on the top in ga…

- URL: https://github.com/Chessever/chessever-frontend/pull/166
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/forYouCandidates -> dev
- Created: 2026-03-27 14:07:04 UTC
- Updated: 2026-03-27 19:35:45 UTC
- Completed: 2026-03-27 19:35:42 UTC
- Merge commit: 4c383c21c57c87d6002a26bf01b82ef2d092b7d0
- Labels: none
- Purpose / what it does: …me list view

PR description:

…me list view

---

### #165 Deeplink Sentry Log

- URL: https://github.com/Chessever/chessever-frontend/pull/165
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/sentryDeeplinkLog -> dev
- Created: 2026-03-27 13:26:07 UTC
- Updated: 2026-03-27 20:24:27 UTC
- Completed: 2026-03-27 20:24:23 UTC
- Merge commit: f4d411ab37a39da438895314320d9539d5e7cfcb
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Deeplink Sentry Log.

PR description:

_No PR description provided._

---

### #164 FIDE Candidates 2026 event

- URL: https://github.com/Chessever/chessever-frontend/pull/164
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/FideCandidates -> dev
- Created: 2026-03-27 11:39:03 UTC
- Updated: 2026-03-27 12:53:59 UTC
- Completed: 2026-03-27 12:53:56 UTC
- Merge commit: 5acfac238a92a347a0ed54e0fa229955c89a7b13
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: FIDE Candidates 2026 event.

PR description:

_No PR description provided._

---

### #163  Forward iOS universal links to app_links in AppDelegate

- URL: https://github.com/Chessever/chessever-frontend/pull/163
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/iosDeepLink -> dev
- Created: 2026-03-26 12:33:19 UTC
- Updated: 2026-03-26 12:43:04 UTC
- Completed: 2026-03-26 12:43:00 UTC
- Merge commit: 1d5f4a29591229588022ed3ca6d52085d7444e74
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only:  Forward iOS universal links to app_links in AppDelegate.

PR description:

_No PR description provided._

---

### #162 Fix shared game deep links opening home instead of target game

- URL: https://github.com/Chessever/chessever-frontend/pull/162
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fixDeepLink -> dev
- Created: 2026-03-26 09:58:59 UTC
- Updated: 2026-03-26 10:36:31 UTC
- Completed: 2026-03-26 10:36:25 UTC
- Merge commit: c1b9bdfcb19307780ec6fd3c81c837b6873d5809
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix shared game deep links opening home instead of target game.

PR description:

_No PR description provided._

---

### #161 Fix random moves on the board

- URL: https://github.com/Chessever/chessever-frontend/pull/161
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fixRandoMoves -> dev
- Created: 2026-03-25 16:59:27 UTC
- Updated: 2026-03-25 18:15:51 UTC
- Completed: 2026-03-25 18:15:46 UTC
- Merge commit: d80b04aa6fc9cfd5bc8017ace4357ff71f1cc409
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix random moves on the board.

PR description:

_No PR description provided._

---

### #160 Remove the Border for Open Explorer

- URL: https://github.com/Chessever/chessever-frontend/pull/160
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-hamburger-inconsistency -> dev
- Created: 2026-03-25 15:54:56 UTC
- Updated: 2026-03-25 16:06:37 UTC
- Completed: 2026-03-25 16:06:33 UTC
- Merge commit: 4b1d843db76f07326300605094020f9b8b18196f
- Labels: none
- Purpose / what it does: Consistent UI across hamburger menu

PR description:

Consistent UI across hamburger menu

---

### #159 Fix : Add Debugger and fix the issue in For You Tab

- URL: https://github.com/Chessever/chessever-frontend/pull/159
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/forYouScreenBugFixes -> dev
- Created: 2026-03-25 15:50:09 UTC
- Updated: 2026-03-25 16:17:15 UTC
- Completed: 2026-03-25 16:17:12 UTC
- Merge commit: a06c6e6ff03cb1f0f22ef3df634876bbdef0797d
- Labels: none
- Purpose / what it does: Add Sentry Debugger, Add a retry button and proper error handler

PR description:

1. Add Sentry Debugger,
2. Add a retry button and proper error handler

---

### #158 Align For You event games with Games tab logic

- URL: https://github.com/Chessever/chessever-frontend/pull/158
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-for-you-tab -> dev
- Created: 2026-03-25 03:58:49 UTC
- Updated: 2026-03-25 07:34:21 UTC
- Completed: 2026-03-25 07:34:18 UTC
- Merge commit: 15073066663397b8fc15f7a983eec194fa2b8327
- Labels: none
- Purpose / what it does: Use the same selected-tour, ordering, and pin logic as Games tab for For You events, and render the first 4 games without round headers. Also adds parity coverage for tour selection and game ordering. Fix the unpin feature in For You, Implement 0 reload for for you tab

PR description:

1. Use the same selected-tour, ordering, and pin logic as Games tab for For You events, and render the first 4 games without round headers. Also adds parity coverage for tour selection and game ordering.
2. Fix the unpin feature in For You,
3. Implement 0 reload for for you tab

---

### #157 Add a safeguard

- URL: https://github.com/Chessever/chessever-frontend/pull/157
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-fav-paywall -> dev
- Created: 2026-03-24 21:20:54 UTC
- Updated: 2026-03-24 21:41:41 UTC
- Completed: 2026-03-24 21:41:39 UTC
- Merge commit: 6702b8dccc726f57c224a35a0e598642968ec20a
- Labels: none
- Purpose / what it does: When a free user click 4th favorite inside favorites (players), it adds a heart instead of pushing the paywall.

PR description:

When a free user click 4th favorite inside favorites (players), it adds a heart instead of pushing the paywall.

---

### #156 Fix For You tab not updating on sub-tour selection change

- URL: https://github.com/Chessever/chessever-frontend/pull/156
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-for-you-tab -> dev
- Created: 2026-03-24 20:46:32 UTC
- Updated: 2026-03-24 22:17:18 UTC
- Completed: 2026-03-24 22:17:18 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Games were cached and not immediately refreshed when the user changed the sub-tour in the Games Tab. Added a ref.listen on selectedTourForEventProvider in forYouEventGamesWithAutoRefreshProvider to explicitly invalidate eventGamesProvider on selection change, mirroring the existing live-round refresh pattern.

PR description:

Games were cached and not immediately refreshed when the user changed the sub-tour in the Games Tab. 
Added a ref.listen on selectedTourForEventProvider in forYouEventGamesWithAutoRefreshProvider to explicitly invalidate eventGamesProvider on selection change, mirroring the existing live-round refresh pattern.

---

### #155 Android Launcher Icon and Board Settings Design

- URL: https://github.com/Chessever/chessever-frontend/pull/155
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/minorFixes -> dev
- Created: 2026-03-24 14:52:31 UTC
- Updated: 2026-03-24 20:53:24 UTC
- Completed: 2026-03-24 20:53:21 UTC
- Merge commit: f5cfcb2b98e767d0f812d067173619acd924fb44
- Labels: none
- Purpose / what it does: Color consistent in Board Settings and Changed Android Launcher Icon

PR description:

Color consistent in Board Settings and Changed Android Launcher Icon

---

### #154 fix(notifications): align defaults and harden heads-up event filter

- URL: https://github.com/Chessever/chessever-frontend/pull/154
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/one-signal-edge-function-updated -> dev
- Created: 2026-03-23 20:38:51 UTC
- Updated: 2026-03-23 21:38:09 UTC
- Completed: 2026-03-23 21:38:05 UTC
- Merge commit: 8140f0315a8bdf447c479a5ff1a1c0ffc9177399
- Labels: none
- Purpose / what it does: favoriteEventAlerts default changed false → true to match the Supabase column default — new users now see the correct opted-in state in the UI Fixed eventAllowed check in filterHeadsUpRecipients from strict === true to !== false, matching the consistent fail-open pattern used across all other filter functions

PR description:

favoriteEventAlerts default changed false → true to match the Supabase column default — new users now see the correct opted-in state in the UI
Fixed eventAllowed check in filterHeadsUpRecipients from strict === true to !== false, matching the consistent fail-open pattern used across all other filter functions

---

### #153 fix: shared game links, PGN copy, and share across all game sources

- URL: https://github.com/Chessever/chessever-frontend/pull/153
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-share-link -> dev
- Created: 2026-03-23 20:06:07 UTC
- Updated: 2026-03-25 15:14:48 UTC
- Completed: 2026-03-25 15:14:44 UTC
- Merge commit: c2babd3cb4d99e53553768c42ed321f374253618
- Labels: none
- Purpose / what it does: Games.fromJson crashed on null search column → silent home redirect getGameById used bare SELECT * instead of _gameListSelectColumns Added getGameByAnyId to resolve both Supabase UUIDs and Lichess short IDs shareGameBtnClicked fetched PGN from Supabase only, breaking TWIC/gamebase/analysis board games

PR description:

- Games.fromJson crashed on null `search` column → silent home redirect
- getGameById used bare SELECT * instead of _gameListSelectColumns
- Added getGameByAnyId to resolve both Supabase UUIDs and Lichess short IDs
- shareGameBtnClicked fetched PGN from Supabase only, breaking TWIC/gamebase/analysis board games
- copyPgnBtnClicked had no error handling or user feedback
- Snackbars updated to match app theme
- Removed dead sort helpers from DeepLinkService
- 13-case unit test added for getGameByAnyId routing logic

---

### #152 Engine cold start issue

- URL: https://github.com/Chessever/chessever-frontend/pull/152
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/Engine_Cold_Start_Issue -> dev
- Created: 2026-03-23 19:16:26 UTC
- Updated: 2026-03-23 22:11:12 UTC
- Completed: 2026-03-23 22:11:09 UTC
- Merge commit: a71e341904281191fa72798ed9acbfcc5ee94564
- Labels: none
- Purpose / what it does: Engine warmup Cold start fix First time visibility engine eval time to 800ms Guard to prevent duplicate calls

PR description:

- Engine warmup
- Cold start fix
- First time visibility engine eval time to 800ms
- Guard to prevent duplicate calls

---

### #151 Default thinking time to be 5 seconds

- URL: https://github.com/Chessever/chessever-frontend/pull/151
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/change-to5second-default -> dev
- Created: 2026-03-23 13:02:53 UTC
- Updated: 2026-03-23 22:07:53 UTC
- Completed: 2026-03-23 22:07:50 UTC
- Merge commit: 6cb304949d4dccc087b1296669afccb5569b2e37
- Labels: none
- Purpose / what it does: Shift to 5 second default think timing

PR description:

Shift to 5 second default think timing

---

### #150 New Hamburger Menu

- URL: https://github.com/Chessever/chessever-frontend/pull/150
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/new-hamburger-menu -> dev
- Created: 2026-03-23 12:15:40 UTC
- Updated: 2026-03-23 21:27:19 UTC
- Completed: 2026-03-23 21:27:16 UTC
- Merge commit: 6cf8b67fea9aec8172f8ba6a4de321bfd7b28586
- Labels: none
- Purpose / what it does: > Add a new UI for Hamburger Menu

PR description:

-> Add a new UI for Hamburger Menu

---

### #149 New Explore Design

- URL: https://github.com/Chessever/chessever-frontend/pull/149
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/new-explore-design -> dev
- Created: 2026-03-19 15:19:25 UTC
- Updated: 2026-03-19 18:22:25 UTC
- Completed: 2026-03-19 18:22:19 UTC
- Merge commit: 5374ff18e5edb74c52621e9c16fc476c5a651c3c
- Labels: none
- Purpose / what it does: Implement new Explore Design from Figma

PR description:

Implement new Explore Design from Figma

---

### #148 fix: favorites not pinning in events

- URL: https://github.com/Chessever/chessever-frontend/pull/148
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-fav-issue -> dev
- Created: 2026-03-18 21:00:25 UTC
- Updated: 2026-03-19 17:25:55 UTC
- Completed: 2026-03-19 17:25:50 UTC
- Merge commit: a6e8bd4c3c386588b062591560464769372e423e
- Labels: none
- Purpose / what it does: Country code comparison used == instead of CountryCodeMatcher.matches(), causing ISO2/ISO3 mismatches (e.g. "GB" vs "ENG") to never pin Empty countryCode on a saved favorite now falls back to name-only match toggleFavorite() fideId guard was blocking favoritesVersionProvider bump for players without a fideId, leaving auto-pins stale

PR description:

- Country code comparison used `==` instead of `CountryCodeMatcher.matches()`, causing ISO2/ISO3 mismatches (e.g. "GB" vs "ENG") to never pin
- Empty `countryCode` on a saved favorite now falls back to name-only match
- `toggleFavorite()` fideId guard was blocking `favoritesVersionProvider` bump for players without a fideId, leaving auto-pins stale

---

### #147 Thiru/negative sign engine issue

- URL: https://github.com/Chessever/chessever-frontend/pull/147
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/Negative_Sign_Engine_Issue -> dev
- Created: 2026-03-18 10:08:10 UTC
- Updated: 2026-05-15 21:05:27 UTC
- Completed: 2026-03-18 11:50:16 UTC
- Merge commit: 98d49698359cd409b3d31223cb2b8308606b8061
- Labels: none
- Purpose / what it does: Fixing local stockfish negative issue

PR description:

- Fixing local stockfish negative issue

---

### #146 Fix Notation and Duplicate Games

- URL: https://github.com/Chessever/chessever-frontend/pull/146
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/notation-and-duplicate-game-fix -> dev
- Created: 2026-03-17 19:18:34 UTC
- Updated: 2026-03-18 20:33:45 UTC
- Completed: 2026-03-18 20:33:42 UTC
- Merge commit: a634f9310f264b50b1010fb5776114fcecfb7e0e
- Labels: none
- Purpose / what it does: Add _deduplicateGames helper that filters by game ID, applied in _decodeGamesInIsolate (covers ~24 methods) and the two inline-decode methods (getGamesByRoundId, getGamesByPlayerName). Move numbers (e.g., "1.", "12...") were being colored the same as the move text in variation and annotation contexts. Split the move number prefix from the SAN move so only the actual move notation receives the variation/annotation...

PR description:

1. Add _deduplicateGames helper that filters by game ID, applied in _decodeGamesInIsolate (covers ~24 methods) and the two inline-decode methods (getGamesByRoundId, getGamesByPlayerName).
2. Move numbers (e.g., "1.", "12...") were being colored the same as the move text in variation and annotation contexts. Split the move number prefix from the SAN move so only the actual move notation receives the variation/annotation color while numbers stay white.
3. Add _isFollowingLive flag to explicitly track whether the user is auto-following live moves. Previously, this was inferred from analysisState.currentMoveIndex which could be temporarily corrupted by _syncAnalysisFromNavigator during the updateWithLatestGame → goToTail sequence, causing wasViewingLastMove to return false and permanently breaking auto-follow for subsequent moves.
4. parseMoves() was creating a new AnalysisBoardState without carrying forward the game field, resetting it to null on every live update. The widget would briefly render "No moves available" until the navigator listener restored it. Now uses copyWith to preserve existing state, and shows a loading skeleton instead of an error message during initial navigator initialization.

---

### #145 Add per-user event notification mute toggle

- URL: https://github.com/Chessever/chessever-frontend/pull/145
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/mute-events -> dev
- Created: 2026-03-17 17:52:59 UTC
- Updated: 2026-03-17 19:07:17 UTC
- Completed: 2026-03-17 19:07:11 UTC
- Merge commit: 55aeec0cd1522121370d320fbcad59ec0ffc472c
- Labels: none
- Purpose / what it does: Allow users to mute/unmute notifications for individual events via the 3-dot menu. Adds user_muted_events table, Riverpod provider for mute state, and edge function filtering to suppress notifications for muted events.

PR description:

Allow users to mute/unmute notifications for individual events via the 3-dot menu. Adds user_muted_events table, Riverpod provider for mute state, and edge function filtering to suppress notifications for muted events.

---

### #144 Fix hot reload

- URL: https://github.com/Chessever/chessever-frontend/pull/144
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-hot-reload -> dev
- Created: 2026-03-17 11:01:02 UTC
- Updated: 2026-05-15 21:07:06 UTC
- Completed: 2026-05-15 21:04:54 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix hot reload.

PR description:

_No PR description provided._

---

### #143 Fix live game real-time updates for game cards and chessboard

- URL: https://github.com/Chessever/chessever-frontend/pull/143
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-live-games-moves-stream -> dev
- Created: 2026-03-17 11:00:21 UTC
- Updated: 2026-03-17 19:23:37 UTC
- Completed: 2026-03-17 19:23:34 UTC
- Merge commit: ceadff8002d90aabf3d811e671c5c27d09c4e4e4
- Labels: none
- Purpose / what it does: Decouple liveGameCardProvider family key from baseGame object so polling doesn't recreate the Supabase stream — game cards now update in real-time without manual refresh Update lastSeenMoveCount when auto-jumping via wasViewingLastMove, fixing stale new-move badges Add generation guard to parseMoves() to prevent concurrent calls from overwriting fresh state with stale data

PR description:

- Decouple `liveGameCardProvider` family key from `baseGame` object so polling doesn't recreate the Supabase stream — game cards now update in real-time without manual refresh
- Update `lastSeenMoveCount` when auto-jumping via `wasViewingLastMove`, fixing stale new-move badges
- Add generation guard to `parseMoves()` to prevent concurrent calls from overwriting fresh state with stale data

---

### #142 Open Feedback form after 3 app opens

- URL: https://github.com/Chessever/chessever-frontend/pull/142
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/feedback-after-3-sessions -> dev
- Created: 2026-03-15 14:06:17 UTC
- Updated: 2026-03-15 15:19:57 UTC
- Completed: 2026-03-15 15:19:53 UTC
- Merge commit: 0394595f4c6a6b8c832ea4c851d6dd02482a9810
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Open Feedback form after 3 app opens.

PR description:

_No PR description provided._

---

### #141 Limit 3 favorite

- URL: https://github.com/Chessever/chessever-frontend/pull/141
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/limitfav -> dev
- Created: 2026-03-14 21:54:50 UTC
- Updated: 2026-03-14 22:35:12 UTC
- Completed: 2026-03-14 22:35:05 UTC
- Merge commit: 5d519419f140d8b01fe5b031b46c362b34e3f244
- Labels: none
- Purpose / what it does: Limit free users to 3 favorites in onboarding and later. onboarding favoite choice, do not allow choosing after 3

PR description:

Limit free users to 3 favorites in onboarding and later.
onboarding favoite choice, do not allow choosing after 3

---

### #140 Fix castling annotation badge position

- URL: https://github.com/Chessever/chessever-frontend/pull/140
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-castling-move -> dev
- Created: 2026-03-14 20:50:10 UTC
- Updated: 2026-03-14 22:25:30 UTC
- Completed: 2026-03-14 22:25:26 UTC
- Merge commit: 8e0de64dd902d6b61afb2ca1fb1a8fdb9341bef9
- Labels: none
- Purpose / what it does: Description: When a castling move is marked as a blunder, mistake, or inaccuracy, the annotation badge is currently shown on the rook’s original square (h1, a1, h8, a8) instead of the king’s destination square (g1, c1, g8, c8). This happens because dartchess encodes castling in king-captures-rook format, and the current destination-square logic uses the move’s raw to/last square value without accounting for castli...

PR description:

Description:
When a castling move is marked as a blunder, mistake, or inaccuracy, the annotation badge is currently shown on the rook’s original square (h1, a1, h8, a8) instead of the king’s destination square (g1, c1, g8, c8).

This happens because dartchess encodes castling in king-captures-rook format, and the current destination-square logic uses the move’s raw to/last square value without accounting for castling.

This change updates the annotation-square resolution so castling moves map to the king’s actual destination:

White king-side castling: g1
White queen-side castling: c1
Black king-side castling: g8
Black queen-side castling: c8
Non-castling moves are unchanged.

Acceptance criteria:

Castling annotations appear on g1, c1, g8, or c8 as appropriate
Normal move annotations continue to appear on the correct destination square

---

### #139 Fix Failed King move

- URL: https://github.com/Chessever/chessever-frontend/pull/139
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-king-unclickable -> dev
- Created: 2026-03-14 12:03:22 UTC
- Updated: 2026-03-14 22:23:34 UTC
- Completed: 2026-03-14 22:23:31 UTC
- Merge commit: 042bde32af7d836c4421a000692625324c3cb56f
- Labels: none
- Purpose / what it does: Fix : https://trello.com/c/FRJER2wa/276-when-the-game-is-over-clicking-the-animated-king-and-try-to-make-move-with-king-doesnt-work

PR description:

Fix : https://trello.com/c/FRJER2wa/276-when-the-game-is-over-clicking-the-animated-king-and-try-to-make-move-with-king-doesnt-work

---

### #138 Fix the order

- URL: https://github.com/Chessever/chessever-frontend/pull/138
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/group-events--issue- -> dev
- Created: 2026-03-14 09:32:32 UTC
- Updated: 2026-03-14 22:13:24 UTC
- Completed: 2026-03-14 22:13:18 UTC
- Merge commit: 8a3d508f2fd849d036f790cdfe5d78ad3b73c0f4
- Labels: none
- Purpose / what it does: The full priority order is now: Session selection (in-memory) Saved selection (SQLite — persists user's explicit choice) Live tours (active games)

PR description:

The full priority order is now:

Session selection (in-memory)
Saved selection (SQLite — persists user's explicit choice)
Live tours (active games)
Default selection (same start → highest avgElo, different starts → latest start)
Game activity fallback
6-8. Remaining fallbacks

---

### #137 Fix live filter for you tab

- URL: https://github.com/Chessever/chessever-frontend/pull/137
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/for-you-live-filter-fix -> dev
- Created: 2026-03-13 21:32:32 UTC
- Updated: 2026-03-13 21:43:21 UTC
- Completed: 2026-03-13 21:43:18 UTC
- Merge commit: 325442721cc122005a255d6b5aa4e879bc4b119b
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix live filter for you tab.

PR description:

_No PR description provided._

---

### #136 Fix evail bar hiding on itself

- URL: https://github.com/Chessever/chessever-frontend/pull/136
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/the-evail-bar-hides-itself -> dev
- Created: 2026-03-13 21:05:20 UTC
- Updated: 2026-03-13 21:07:17 UTC
- Completed: 2026-03-13 21:06:47 UTC
- Merge commit: 11c4b2610b6e64306c688dc19b0517c48e81f878
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix evail bar hiding on itself.

PR description:

_No PR description provided._

---

### #135 Fix the constrains, annotations style and about page

- URL: https://github.com/Chessever/chessever-frontend/pull/135
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/explorer-design-update -> dev
- Created: 2026-03-13 20:35:32 UTC
- Updated: 2026-03-13 20:48:22 UTC
- Completed: 2026-03-13 20:48:17 UTC
- Merge commit: 35e2440bfe4ad9f7e70fa08d3fe61d001d452ec3
- Labels: none
- Purpose / what it does: Fix constrains exceptions in About screen, Fix annotations style, Add Powered By

PR description:

Fix constrains exceptions in About screen,
Fix annotations style,
Add Powered By

---

### #134 Flutterdev/fix question mark notation

- URL: https://github.com/Chessever/chessever-frontend/pull/134
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-question-mark-notation -> dev
- Created: 2026-03-13 18:36:02 UTC
- Updated: 2026-03-13 19:00:24 UTC
- Completed: 2026-03-13 19:00:21 UTC
- Merge commit: 2935c24539e2a12768e157b791133d5bae6d5be6
- Labels: none
- Purpose / what it does: Fix : https://trello.com/c/LBEusclm/271-fix-notation-for-signs Fix : https://trello.com/c/hmUVuXFO/274-question-marks-are-showing-for-the-next-move-that-does-not-have-question-for Fix : https://trello.com/c/EaPgPWAA/275-when-the-move-on-the-right-file-symbols-look-weird

PR description:

Fix : https://trello.com/c/LBEusclm/271-fix-notation-for-signs
Fix : https://trello.com/c/hmUVuXFO/274-question-marks-are-showing-for-the-next-move-that-does-not-have-question-for
Fix : https://trello.com/c/EaPgPWAA/275-when-the-move-on-the-right-file-symbols-look-weird

---

### #133 for completed games, go to first move

- URL: https://github.com/Chessever/chessever-frontend/pull/133
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/completed-games-first-move -> dev
- Created: 2026-03-13 16:00:09 UTC
- Updated: 2026-03-13 18:50:41 UTC
- Completed: 2026-03-13 18:50:38 UTC
- Merge commit: ada99d50009c4b9d335d7c189ce48373f32ebdd7
- Labels: none
- Purpose / what it does: for completed games, go to first move

PR description:

for completed games, go to first move

---

### #132 fix: prevent annotation badge from bleeding onto next move

- URL: https://github.com/Chessever/chessever-frontend/pull/132
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-question-mark -> dev
- Created: 2026-03-12 20:19:36 UTC
- Updated: 2026-03-12 21:00:51 UTC
- Completed: 2026-03-12 20:59:29 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Remove fallback logic that showed the previous move's annotation when the current move had none, causing question marks to appear on unannotated moves. Extract resolveBoardAnnotation into a testable function and add unit tests.

PR description:

Remove fallback logic that showed the previous move's annotation when the current move had none, causing question marks to appear on unannotated moves. Extract resolveBoardAnnotation into a testable function and add unit tests.

---

### #131 Hide Options

- URL: https://github.com/Chessever/chessever-frontend/pull/131
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/fix-hamburger -> dev
- Created: 2026-03-11 20:39:13 UTC
- Updated: 2026-03-11 20:47:31 UTC
- Completed: 2026-03-11 20:47:27 UTC
- Merge commit: c817e9195de96bea8f45ddf1d3efa8c9f8f099b9
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Hide Options.

PR description:

_No PR description provided._

---

### #130 Paywall the Opening Explorer Player filter for non-premium users

- URL: https://github.com/Chessever/chessever-frontend/pull/130
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/paywall-player-filter -> dev
- Created: 2026-03-11 19:38:05 UTC
- Updated: 2026-03-11 22:12:52 UTC
- Completed: 2026-03-11 22:12:49 UTC
- Merge commit: 129e8c8a1fec1097f7ffddb7917fccf1947edaa4
- Labels: none
- Purpose / what it does: Use ref.watch(subscriptionProvider.select((s) => s.isSubscribed)) for the premium check. Wrap const _PlayerSearchInput() with GestureDetector + AbsorbPointer for the locked state.

PR description:

Use ref.watch(subscriptionProvider.select((s) => s.isSubscribed)) for the premium check. Wrap const _PlayerSearchInput() with GestureDetector + AbsorbPointer for the locked state.

---

### #129 Fill For You events to 4 available boards

- URL: https://github.com/Chessever/chessever-frontend/pull/129
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/show-4-boards -> dev
- Created: 2026-03-11 13:56:11 UTC
- Updated: 2026-03-12 14:21:56 UTC
- Completed: 2026-03-12 14:21:16 UTC
- Merge commit: ff3b70359c5569c5bb650dd52a40b93693abaf7a
- Labels: none
- Purpose / what it does: Update For You event selection to show up to four started boards per event instead of stopping at a single latest round or tour. When the primary round has fewer than four games, backfill from other started rounds or sibling tours in the same event while preserving pin priority, match-event behavior, and existing For You view modes. Also keep the 4-board cap consistent across phone and tablet rendering.

PR description:

Update For You event selection to show up to four started boards per event instead of stopping at a single latest round or tour. When the primary round has fewer than four games, backfill from other started rounds or sibling tours in the same event while preserving pin priority, match-event behavior, and existing For You view modes. Also keep the 4-board cap consistent across phone and tablet rendering.

---

### #128 pipeline GIF export and reduce share-card memory usage

- URL: https://github.com/Chessever/chessever-frontend/pull/128
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/gif-optimization -> dev
- Created: 2026-03-11 10:37:24 UTC
- Updated: 2026-03-12 14:00:14 UTC
- Completed: 2026-03-12 14:00:10 UTC
- Merge commit: 0352962814ff1de1d1b2c29858893543f12e0c07
- Labels: none
- Purpose / what it does: Replace the batch GIF export path with a pipelined worker-based flow. move GIF planning, worker protocol, and fallback encoding into a dedicated helper overlap frame capture and GIF encoding instead of waiting for all frames first cap memory by limiting in-flight frames instead of buffering the full export

PR description:

Replace the batch GIF export path with a pipelined worker-based flow.

- move GIF planning, worker protocol, and fallback encoding into a dedicated helper
- overlap frame capture and GIF encoding instead of waiting for all frames first
- cap memory by limiting in-flight frames instead of buffering the full export
- replace per-pixel setPixelRgba loops with Image.fromBytes
- remove fixed capture sleeps and rely on endOfFrame-driven capture
- add adaptive frame planning for long games while preserving short-game fidelity
- dispose captured ui.Image objects immediately after raw byte extraction
- add timeout and failure handling for worker startup/completion
- abort cleanly when SAN parsing or required frame capture fails
- add unit tests for export planning and worker encoding behavior

---

### #127 Fix live game board opening flash by seeding initial position from FEN

- URL: https://github.com/Chessever/chessever-frontend/pull/127
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/jump-to-last-move -> dev
- Created: 2026-03-11 08:09:02 UTC
- Updated: 2026-03-12 18:42:55 UTC
- Completed: 2026-03-12 18:42:44 UTC
- Merge commit: 81cf1990f0c8ad3c36065d78ef54cc27f47d8bbc
- Labels: none
- Purpose / what it does: Seed the live chessboard’s initial render from game.fen instead of the default starting position. This removes the brief flash to Chess.initial when opening ongoing games, while keeping PGN parsing as the source of truth for move history, navigation, and live auto-follow behavior.

PR description:

Seed the live chessboard’s initial render from game.fen instead of the default starting position. This removes the brief flash to Chess.initial when opening ongoing games, while keeping PGN parsing as the source of truth for move history, navigation, and live auto-follow behavior.

---

### #126 Migrate legacy 5s engine thinking time to unlimited

- URL: https://github.com/Chessever/chessever-frontend/pull/126
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/change-default-think-time-to-unlimited -> dev
- Created: 2026-03-11 07:41:14 UTC
- Updated: 2026-03-12 19:11:35 UTC
- Completed: 2026-03-12 19:11:30 UTC
- Merge commit: f981f034d63c45675691d86d6602d5947471e26d
- Labels: none
- Purpose / what it does: Add a one-time per-user migration that rewrites legacy saved search_time_index=0 values to unlimited while preserving future user-selected 5s values, and align cached engine fallback defaults with the current unlimited default.

PR description:

Add a one-time per-user migration that rewrites legacy saved search_time_index=0 values to unlimited while preserving future user-selected 5s values, and align cached engine fallback defaults with the current unlimited default.

---

### #125 Add local-only auto-pin preferences with user-scoped SQLite storage

- URL: https://github.com/Chessever/chessever-frontend/pull/125
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/auto-pin-fix -> dev
- Created: 2026-03-10 17:02:09 UTC
- Updated: 2026-03-12 20:06:48 UTC
- Completed: 2026-03-12 20:06:38 UTC
- Merge commit: 7d3948c16989a21545706c83ef06ce5a010c957c
- Labels: none
- Purpose / what it does: Introduce two global auto-pin toggles (Favorite Players: on by default, Countrymen: off by default) stored in user-scoped SQLite cache_store. Move per-tournament auto-pin disable to user-scoped storage with legacy key compatibility fallback. Add Auto Pin section to Board Settings page.

PR description:

Introduce two global auto-pin toggles (Favorite Players: on by default, 
Countrymen: off by default) stored in user-scoped SQLite cache_store. 
Move per-tournament auto-pin disable to user-scoped storage with legacy key compatibility fallback. 
Add Auto Pin section to Board Settings page.

---

### #124 Fix `_CountryFlag` constructor missing `super.key`

- URL: https://github.com/Chessever/chessever-frontend/pull/124
- State: CLOSED
- Author: app/copilot-swe-agent
- Branch: copilot/sub-pr-122 -> flutterdev/about-us-screen
- Created: 2026-03-09 15:11:38 UTC
- Updated: 2026-05-15 21:05:47 UTC
- Completed: 2026-03-09 15:23:27 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: _CountryFlag was missing super.key in its constructor, triggering the use_key_in_widget_constructors lint from flutter_lints. Reintroduced super.key as an optional named parameter in _CountryFlag's constructor ```dart // Before

PR description:

`_CountryFlag` was missing `super.key` in its constructor, triggering the `use_key_in_widget_constructors` lint from `flutter_lints`.

## Change

- Reintroduced `super.key` as an optional named parameter in `_CountryFlag`'s constructor

```dart
// Before
const _CountryFlag({
  required this.title,
  required this.flag,
  required this.description,
});

// After
const _CountryFlag({
  super.key,
  required this.title,
  required this.flag,
  required this.description,
});
```

<!-- START COPILOT CODING AGENT TIPS -->
---

💬 We'd love your input! Share your thoughts on Copilot coding agent in our [2 minute survey](https://gh.io/copilot-coding-agent-survey).

---

### #123 Fixes for Trello tasks and Figma Updates

- URL: https://github.com/Chessever/chessever-frontend/pull/123
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/removeHeartIcon -> dev
- Created: 2026-03-09 12:26:38 UTC
- Updated: 2026-03-09 17:11:57 UTC
- Completed: 2026-03-09 17:04:34 UTC
- Merge commit: 9da53e9bd6f2e2ac08479e4de5f90323fb376413
- Labels: none
- Purpose / what it does: Fixes : Heart is eliminated from current list and stars are shown, Share image now has co-ordinates, Evail bar is now shown correctly when opened from explorer,

PR description:

Fixes : 
1. Heart is eliminated from current list and stars are shown,
2. Share image now has co-ordinates,
3. Evail bar is now shown correctly when opened from explorer,
4. Games Opened from notifications, swiping works there now,
5. twic should say 4.5 million,
6.  Eliminate heart from past and anywhere else but keep in for you,
7. Fix When we filter using Time Control, search failed,
8. Fixed from figma : 
a. Update the color of Current move, 
b. The heartbreak icon is rather new way of showing  inaccuracy, mistake and blunder,
c. Update app icon for Android,


Completed Trello Tasks :
1. https://trello.com/c/OFEp6JJ9/221-eliminate-heart-from-the-current-list-only-stars
2. https://trello.com/c/pcEIx8CA/233-image-sharing-comes-out-without-coordinates
3. https://trello.com/c/UYslQAWi/236-opening-explorer-shows-incorrectly-in-the-eval-bar
4. https://trello.com/c/xVxltAII/246-when-a-game-opened-from-notification-swiping-does-not-work
5. https://trello.com/c/UyFqIp9V/248-twic-should-say-45-million
6. https://trello.com/c/nN6neKm2/262-eliminate-heart-from-past-and-anywhere-else-but-keep-in-for-you
7. https://trello.com/c/mgBwUswb/257-rating-filter-breaks-twic 
-> Fixed based on issue shown in the video [ When we filter using Time Control, search failed ]

---

### #122 Figma : Update in About Screen

- URL: https://github.com/Chessever/chessever-frontend/pull/122
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterdev/about-us-screen -> dev
- Created: 2026-03-09 11:49:33 UTC
- Updated: 2026-03-09 20:03:42 UTC
- Completed: 2026-03-09 20:03:39 UTC
- Merge commit: 940efc5da1b907fd2391570a31d7177c844b40f7
- Labels: none
- Purpose / what it does: > Add standingsUrl and tourUrl to open the link to respective domains using URL launcher Trello : https://trello.com/c/3LHxISfP/249-about-page-lichess-update

PR description:

-> Add standingsUrl and tourUrl to open the link to respective domains using URL launcher

Trello : https://trello.com/c/3LHxISfP/249-about-page-lichess-update

---

### #121 Add Patrol signed-in mobile E2E suite

- URL: https://github.com/Chessever/chessever-frontend/pull/121
- State: CLOSED
- Author: devberkay (Berkay Can)
- Branch: feature/analysis_mode_v6 -> feature/complete_view_mode
- Created: 2026-03-07 04:50:43 UTC
- Updated: 2026-05-15 21:06:05 UTC
- Completed: 2026-05-15 21:04:56 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: add a Patrol-based signed-in mobile E2E stack with isolated E2E startup, real Supabase test-user bootstrap, and prompt suppression add stable E2E selectors across the app and a deep support layer for seeded live-data routing, board assertions, notation taps, move traversal, and game swipes document local and Codemagic operation in patrol_test/README.md, plus root-level README entrypoints and .env.e2e.example

PR description:

## Summary
- add a Patrol-based signed-in mobile E2E stack with isolated `E2E` startup, real Supabase test-user bootstrap, and prompt suppression
- add stable E2E selectors across the app and a deep support layer for seeded live-data routing, board assertions, notation taps, move traversal, and game swipes
- document local and Codemagic operation in `patrol_test/README.md`, plus root-level README entrypoints and `.env.e2e.example`

## Coverage
- smoke suite covers onboarding, signed-in shell roots, drawer surfaces, guarded shells, tournament/calendar/library/player/profile flows, and search/filter assertions across events, calendar, library, favorites, premium, and countrymen pages
- deep suite walks every named route registered in `MaterialApp.routes` and then covers widget-only page surfaces such as settings, premium screens, TWIC contents, opening explorer, board editor, book preview, and scorecard
- board-heavy coverage asserts eval bar visibility, PV visibility, engine refresh after position changes, notation taps, rapid move traversal, board flip, selector-based game switching, and swipe-based game switching

## Validation
- `flutter analyze patrol_test/signed_in_smoke_test.dart patrol_test/signed_in_deep_test.dart patrol_test/support/e2e_test_support.dart lib/widgets/board_color_dialog.dart`
- device/simulator execution was not rerun in the final pass; the last pass was code/doc coverage and focused analyzer validation

---

### #120 Fix event card parsing, live flag guard, and favorite-player fallback

- URL: https://github.com/Chessever/chessever-frontend/pull/120
- State: CLOSED
- Author: devberkay (Berkay Can)
- Branch: merge/frontend-avg-elo -> main
- Created: 2026-01-13 07:32:38 UTC
- Updated: 2026-05-15 21:07:31 UTC
- Completed: 2026-05-15 21:04:37 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Fix parsing of numeric fields for group broadcasts/tours so avg ELO and player data no longer disappear when Supabase returns non-int types. Add fallback to derive favorite players from games when tour player lists are empty. Prevent live dot from showing outside the event date window.

PR description:

## Summary
- Fix parsing of numeric fields for group broadcasts/tours so avg ELO and player data no longer disappear when Supabase returns non-int types.
- Add fallback to derive favorite players from games when tour player lists are empty.
- Prevent live dot from showing outside the event date window.

## Testing
- Not run (data-path changes only).

---

### #118 Subscription Setup

- URL: https://github.com/Chessever/chessever-frontend/pull/118
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/subscription -> main3
- Created: 2025-10-26 08:47:27 UTC
- Updated: 2026-05-15 21:07:02 UTC
- Completed: 2026-05-15 21:04:58 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: > Create Subscription in Google Play and App Store, > Setup and load entitlements in revenue cat and connect products from respective stores > Create Pop-up for subscription based on state, > Enable sandbox and testing,

PR description:

-> Create Subscription in Google Play and App Store, 
-> Setup and load entitlements in revenue cat and connect products from respective stores 
-> Create Pop-up for subscription based on state,
-> Enable sandbox and testing,

---

### #117 Flutter dev/fix duplicate team name

- URL: https://github.com/Chessever/chessever-frontend/pull/117
- State: CLOSED
- Author: devberkay (Berkay Can)
- Branch: flutterDev/fix-duplicate-team-name -> main3
- Created: 2025-10-22 18:17:12 UTC
- Updated: 2026-05-15 21:06:39 UTC
- Completed: 2026-05-15 21:05:01 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Flutter dev/fix duplicate team name.

PR description:

_No PR description provided._

---

### #116 Feature/fix group event bugs

- URL: https://github.com/Chessever/chessever-frontend/pull/116
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/fix_group_event_bugs -> main3
- Created: 2025-10-22 18:08:20 UTC
- Updated: 2026-05-15 21:06:17 UTC
- Completed: 2025-10-22 18:08:46 UTC
- Merge commit: 6ef7dcb4eb5668b3966e390b80ae27406209fe55
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feature/fix group event bugs.

PR description:

_No PR description provided._

---

### #115 Fix : Team Event Issue

- URL: https://github.com/Chessever/chessever-frontend/pull/115
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-duplicate-team-name -> main
- Created: 2025-10-22 14:11:40 UTC
- Updated: 2025-10-22 18:22:24 UTC
- Completed: 2025-10-22 18:22:24 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: > Fix Duplicate team Event Name, > Implement Search feature in group Event view and show result from the Entire game, > Display the Score of the team at the end,

PR description:

-> Fix Duplicate team Event Name,
-> Implement Search feature in group Event view and show result from the Entire game,
-> Display the Score of the team at the end,

---

### #114 Fix the null issue in navigation

- URL: https://github.com/Chessever/chessever-frontend/pull/114
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-events-view-navigation -> main3
- Created: 2025-10-22 13:27:37 UTC
- Updated: 2026-05-15 21:06:41 UTC
- Completed: 2025-10-22 18:22:37 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Send the original games list model with all the sorted games

PR description:

Send the original games list model with all the sorted games

---

### #113 Add missing login checker

- URL: https://github.com/Chessever/chessever-frontend/pull/113
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: add-missing-snippet -> main3
- Created: 2025-10-22 13:03:35 UTC
- Updated: 2025-10-22 13:37:12 UTC
- Completed: 2025-10-22 13:37:06 UTC
- Merge commit: bd63d846289159a75d5592a0e8db8d25354f7dcc
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Add missing login checker.

PR description:

_No PR description provided._

---

### #112 Group Event Update

- URL: https://github.com/Chessever/chessever-frontend/pull/112
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/main-3-group-event -> main3
- Created: 2025-10-22 07:38:28 UTC
- Updated: 2025-10-22 07:50:12 UTC
- Completed: 2025-10-22 07:50:11 UTC
- Merge commit: 70ed65a69842765dd9ade70c107fe2d830121ad6
- Labels: none
- Purpose / what it does: > Update to Normal Games Card, > Display Scores of the Game at the Top, > Display Top Rated 4 Player, else show none, > Cleanup UI and manage state and business logic in it's own provider,

PR description:

-> Update to Normal Games Card,
-> Display Scores of the Game at the Top,
-> Display Top Rated 4 Player, else show none,
-> Cleanup UI and manage state and business logic in it's own provider,
-> Remove Boiler Plate for old widgets,

---

### #111 Display the list of players

- URL: https://github.com/Chessever/chessever-frontend/pull/111
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: flutterDev/fix-about-screen -> main3
- Created: 2025-10-22 00:09:55 UTC
- Updated: 2026-05-15 21:06:38 UTC
- Completed: 2025-10-22 00:10:02 UTC
- Merge commit: 2e7a37b95812fd4b9923b90a48719f45146b4e80
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Display the list of players.

PR description:

_No PR description provided._

---

### #110 Don't display players

- URL: https://github.com/Chessever/chessever-frontend/pull/110
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-about-screen -> main3
- Created: 2025-10-21 19:49:10 UTC
- Updated: 2026-05-15 21:06:38 UTC
- Completed: 2025-10-21 23:46:59 UTC
- Merge commit: b4f4dfa06834a31450b010751362d9a6c463dec2
- Labels: none
- Purpose / what it does: Hide Players in About Screen

PR description:

Hide Players in About Screen

---

### #109 Test pr 108 merge

- URL: https://github.com/Chessever/chessever-frontend/pull/109
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: test-pr-108-merge -> main3
- Created: 2025-10-21 15:09:24 UTC
- Updated: 2026-05-15 21:07:40 UTC
- Completed: 2025-10-21 15:09:54 UTC
- Merge commit: 8019cc99991e1ba72649812082d046221c7cbb4d
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Test pr 108 merge.

PR description:

_No PR description provided._

---

### #108 Players View Fix and update app dropdown

- URL: https://github.com/Chessever/chessever-frontend/pull/108
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/save_selected_tour -> main3
- Created: 2025-10-19 04:41:22 UTC
- Updated: 2026-05-15 21:06:56 UTC
- Completed: 2025-10-21 15:09:56 UTC
- Merge commit: 5afb2f486a06a8f793af6599bdb4f0f36f260957
- Labels: none
- Purpose / what it does: > Reload Players View accurately after changing tournament, > Fix the Dropdown Layout issues,

PR description:

-> Reload Players View accurately after changing tournament,
-> Fix the Dropdown Layout issues,

---

### #107 Fix Players View

- URL: https://github.com/Chessever/chessever-frontend/pull/107
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/save_selected_tour -> main
- Created: 2025-10-19 04:40:08 UTC
- Updated: 2026-05-15 21:06:56 UTC
- Completed: 2025-10-19 04:40:25 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: > Reload Players View accurately after changing tournament, > Fix the Dropdown Layout issues,

PR description:

-> Reload Players View accurately after changing tournament,
-> Fix the Dropdown Layout issues,

---

### #106 Fix native dependencies for downloading image

- URL: https://github.com/Chessever/chessever-frontend/pull/106
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: fix/native_deps_for_downloading_image -> main3
- Created: 2025-10-18 19:25:33 UTC
- Updated: 2026-05-15 21:06:29 UTC
- Completed: 2025-10-18 20:44:09 UTC
- Merge commit: ad59845c36b9058c36d07e0c50f4207e06277b24
- Labels: none
- Purpose / what it does: 🤖 Generated with Claude Code

PR description:

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

### #105 age

- URL: https://github.com/Chessever/chessever-frontend/pull/105
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feat/bump_version_54 -> main3
- Created: 2025-10-18 17:11:35 UTC
- Updated: 2026-05-15 21:05:51 UTC
- Completed: 2025-10-18 17:11:50 UTC
- Merge commit: b08d1ce71f5bc0e431b58a64158eb3896f05179e
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: age.

PR description:

_No PR description provided._

---

### #104 Feature/complete view mode fix main3

- URL: https://github.com/Chessever/chessever-frontend/pull/104
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/complete_view_mode-fix-main3 -> main3
- Created: 2025-10-18 17:09:50 UTC
- Updated: 2026-05-15 21:06:08 UTC
- Completed: 2025-10-18 17:09:58 UTC
- Merge commit: a6c89644297ccc107f7403c42e39eb734f06965b
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feature/complete view mode fix main3.

PR description:

_No PR description provided._

---

### #103 Save User's selection and pre-select active tour

- URL: https://github.com/Chessever/chessever-frontend/pull/103
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/save_selected_tour -> main3
- Created: 2025-10-17 20:43:00 UTC
- Updated: 2025-10-18 13:20:34 UTC
- Completed: 2025-10-18 13:20:34 UTC
- Merge commit: 9a1c4d62d0978a0d287c8d71c730d91848c0d6e8
- Labels: none
- Purpose / what it does: > The tour selected by the user if exists, > the live tournament if exists, > the tournament that completed recently

PR description:

-> The tour selected by the user if exists,
-> the live tournament if exists,
-> the tournament that completed recently

---

### #102 Fix Feedbacks

- URL: https://github.com/Chessever/chessever-frontend/pull/102
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-feedback -> main3
- Created: 2025-10-17 16:19:13 UTC
- Updated: 2025-10-17 17:19:18 UTC
- Completed: 2025-10-17 17:19:10 UTC
- Merge commit: cd96f2d4cf450d6b2b050df2b0a1ac6296c3a79c
- Labels: none
- Purpose / what it does: > Fix the Past Events long load time by caching the favorites as well, > Fix the name comparison in the reverse order or normal order, > Add Missing details for the Player Information, > Sort using the score,

PR description:

-> Fix the Past Events long load time by caching the favorites as well,
-> Fix the name comparison in the reverse order or normal order,
-> Add Missing details for the Player Information,
-> Sort using the score,

---

### #101 make computer icon button active color white

- URL: https://github.com/Chessever/chessever-frontend/pull/101
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/make_computer_icon_active_color_white -> main3
- Created: 2025-10-17 03:21:45 UTC
- Updated: 2026-05-15 21:06:23 UTC
- Completed: 2025-10-17 03:21:58 UTC
- Merge commit: 08a79118454aa119c28efb7e542090642d91fce0
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: make computer icon button active color white.

PR description:

_No PR description provided._

---

### #100 Feature/stabilize before analysis mode

- URL: https://github.com/Chessever/chessever-frontend/pull/100
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/stabilize_before_analysis_mode -> main3
- Created: 2025-10-17 02:56:30 UTC
- Updated: 2025-10-17 02:59:46 UTC
- Completed: 2025-10-17 02:58:53 UTC
- Merge commit: 5c662f52cfe74ab47dbe28ee4725019620cfed74
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feature/stabilize before analysis mode.

PR description:

_No PR description provided._

---

### #99 Group Event Screen

- URL: https://github.com/Chessever/chessever-frontend/pull/99
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/main-3-group-event -> main3
- Created: 2025-10-16 16:40:27 UTC
- Updated: 2025-10-21 17:36:04 UTC
- Completed: 2025-10-21 17:36:04 UTC
- Merge commit: d275c3555922a4833715be841c55470b40c183e1
- Labels: none
- Purpose / what it does: > Create Switched View, > Allow Numeric Round Selection, > Create Hide Reveal Animation,

PR description:

-> Create Switched View,
-> Allow Numeric  Round Selection,
-> Create Hide Reveal Animation,

---

### #98 Fix Games navigation From Scorecard View

- URL: https://github.com/Chessever/chessever-frontend/pull/98
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-fav-navigation -> main3
- Created: 2025-10-16 14:55:27 UTC
- Updated: 2026-05-15 21:06:42 UTC
- Completed: 2025-10-17 03:19:16 UTC
- Merge commit: b1fe74c7849ce97f7ccfd712b0840d96164ff83b
- Labels: none
- Purpose / what it does: > Fix favorite -> Scorecard -> Chess Board New Screen Navigation,

PR description:

-> Fix favorite -> Scorecard -> Chess Board New Screen Navigation,

---

### #97 Fix state for show/hide and pin

- URL: https://github.com/Chessever/chessever-frontend/pull/97
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/enable-disable-pin-games -> main3
- Created: 2025-10-16 10:47:45 UTC
- Updated: 2026-05-15 21:06:35 UTC
- Completed: 2025-10-16 10:51:30 UTC
- Merge commit: 9008e675d7f9432972c2e0a8f767312477ac6ec6
- Labels: none
- Purpose / what it does: > Show, hide completed games, show all games > Unpin Fix, > Disable auto pin, enable auto pin, > Clear all pins,

PR description:

-> Show, hide completed games, show all games
-> Unpin Fix,
-> Disable auto pin, enable auto pin,
-> Clear all pins,

---

### #96 Show/Hide Games, Autopin enable/disable

- URL: https://github.com/Chessever/chessever-frontend/pull/96
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-unpin-all -> main
- Created: 2025-10-16 10:05:56 UTC
- Updated: 2026-05-15 21:06:47 UTC
- Completed: 2025-10-16 10:24:55 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: > Show, hide completed games, show all games > Enable/disable autopin, > Unpin Fix

PR description:

-> Show, hide completed games, show all games
-> Enable/disable autopin,
-> Unpin Fix

---

### #95 Feature/fix pv cards

- URL: https://github.com/Chessever/chessever-frontend/pull/95
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/fix_pv_cards -> main
- Created: 2025-10-14 18:12:08 UTC
- Updated: 2025-10-14 18:15:37 UTC
- Completed: 2025-10-14 18:15:36 UTC
- Merge commit: c658283ab5289d0593c867f76b711ff19fc9857d
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feature/fix pv cards.

PR description:

_No PR description provided._

---

### #94 Feature/fix clock reduntant countdown

- URL: https://github.com/Chessever/chessever-frontend/pull/94
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/fix_clock_reduntant_countdown -> main
- Created: 2025-10-14 18:10:26 UTC
- Updated: 2026-05-15 21:06:15 UTC
- Completed: 2025-10-14 18:17:34 UTC
- Merge commit: 1d2395b994f603baf3bb5620f87c36d2f5707cb7
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feature/fix clock reduntant countdown.

PR description:

_No PR description provided._

---

### #93 Favorite Update

- URL: https://github.com/Chessever/chessever-frontend/pull/93
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: main2 -> main
- Created: 2025-10-14 14:42:39 UTC
- Updated: 2026-05-15 21:07:26 UTC
- Completed: 2025-10-14 18:15:35 UTC
- Merge commit: f3fdf2ef688d196b1c4b9d65e2a7bc71b2d0b5b4
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Favorite Update.

PR description:

_No PR description provided._

---

### #92 Favorites Update

- URL: https://github.com/Chessever/chessever-frontend/pull/92
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fav-feedback -> main2
- Created: 2025-10-14 06:30:22 UTC
- Updated: 2025-10-14 14:42:15 UTC
- Completed: 2025-10-14 14:42:15 UTC
- Merge commit: b67230859ce6a6e11922a45d229defe25d372838
- Labels: none
- Purpose / what it does: > Favorite option in Players View, > Player Screen with Fav Support, > Sort based on favorite, > Cleanup Fav Logic,

PR description:

-> Favorite option in Players View,
-> Player Screen with Fav Support,
-> Sort based on favorite,
-> Cleanup Fav Logic,

---

### #91 Fix board behaviours

- URL: https://github.com/Chessever/chessever-frontend/pull/91
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/fix_board_behaviours -> main2
- Created: 2025-10-14 00:38:54 UTC
- Updated: 2025-10-14 18:14:23 UTC
- Completed: 2025-10-14 00:39:42 UTC
- Merge commit: d4c60b1e2822e7a6a5b6c6cc8e890ec5a80d6247
- Labels: none
- Purpose / what it does: This PR includes fixes for board behaviours and streaming race conditions.

PR description:

## Summary
This PR includes fixes for board behaviours and streaming race conditions.

## Changes
- Fixed streaming race condition by removing dual stream subscriptions
- Various board behaviour improvements

## Recent commits
- Everything done
- Fix streaming race condition - remove dual stream subscriptions
- EVERYTHING ALMOST AMAZING
- PERFECTION%99
- GOOD

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>

---

### #90 Feature/fix board behaviours

- URL: https://github.com/Chessever/chessever-frontend/pull/90
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/fix_board_behaviours -> main
- Created: 2025-10-14 00:35:16 UTC
- Updated: 2025-10-14 18:14:23 UTC
- Completed: 2025-10-14 18:14:19 UTC
- Merge commit: 27b3be69f5c0cac053bbefd8e0bffc5a807feb7c
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feature/fix board behaviours.

PR description:

_No PR description provided._

---

### #89 Flutter dev/favorite screen feature

- URL: https://github.com/Chessever/chessever-frontend/pull/89
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/favorite_screen_feature -> main
- Created: 2025-10-13 19:54:07 UTC
- Updated: 2025-10-13 22:16:49 UTC
- Completed: 2025-10-13 22:16:46 UTC
- Merge commit: 548d9f8ae6b5d75b877d2a313dcb6da31e697630
- Labels: none
- Purpose / what it does: > Implemented favorite screen with search feature, > Implement large heap size for android and hardware acceleration for better performance,

PR description:

-> Implemented favorite screen with search feature,
-> Implement large heap size for android and hardware acceleration for better performance,

---

### #88 Feature/commentout analysis features

- URL: https://github.com/Chessever/chessever-frontend/pull/88
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/commentout_analysis_features -> main
- Created: 2025-10-12 15:43:44 UTC
- Updated: 2025-10-12 16:36:01 UTC
- Completed: 2025-10-12 16:35:58 UTC
- Merge commit: df455c7ec1ffa8c0d45041044ba64b757687753c
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feature/commentout analysis features.

PR description:

_No PR description provided._

---

### #87 Update Clarity initialization

- URL: https://github.com/Chessever/chessever-frontend/pull/87
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/initialize-clarity-correctly -> main
- Created: 2025-10-11 23:17:21 UTC
- Updated: 2025-10-12 05:25:55 UTC
- Completed: 2025-10-12 05:25:52 UTC
- Merge commit: b9b3f13e1aef65dd3c3b236ac4a152cfbba9a0ce
- Labels: none
- Purpose / what it does: > Fix Clarity initialization > Setup API keys in .env

PR description:

-> Fix Clarity initialization
-> Setup API keys in .env

---

### #86 Flutter dev/fix calendar view

- URL: https://github.com/Chessever/chessever-frontend/pull/86
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-calendar-view -> main
- Created: 2025-10-11 22:40:23 UTC
- Updated: 2025-10-11 23:04:05 UTC
- Completed: 2025-10-11 23:04:02 UTC
- Merge commit: 57044a5e786a37ddd55d424f27891b32c8543877
- Labels: none
- Purpose / what it does: > Search in calendar view, > Search and Filter Options in calendar detail view, > Reset and Favorite sorting in calendar view,

PR description:

-> Search in calendar view,
-> Search and Filter Options in calendar detail view,
-> Reset and Favorite sorting in calendar view,

---

### #85 Analysis merge with main

- URL: https://github.com/Chessever/chessever-frontend/pull/85
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: main-2 -> main
- Created: 2025-10-10 12:25:42 UTC
- Updated: 2025-10-10 13:12:26 UTC
- Completed: 2025-10-10 13:12:23 UTC
- Merge commit: 5e4e9be5e7eba06c9246c1281266489859dc45b3
- Labels: none
- Purpose / what it does: Analysis Board and main changes merged into one

PR description:

Analysis Board and main changes merged into one

---

### #84 Feature/colorful notations

- URL: https://github.com/Chessever/chessever-frontend/pull/84
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/colorful_notations -> main-2
- Created: 2025-10-09 17:43:41 UTC
- Updated: 2025-10-10 04:12:23 UTC
- Completed: 2025-10-10 04:12:11 UTC
- Merge commit: 9cd3ebd0f1194188ed0b0fcbe2286372c173962a
- Labels: none
- Purpose / what it does: Analysis Feature + Move Impact Analysis ("!!","!?","!","?","??")

PR description:

Analysis Feature + Move Impact Analysis ("!!","!?","!","?","??")

---

### #83 Fix moves not to be clicked

- URL: https://github.com/Chessever/chessever-frontend/pull/83
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/hide-chat-icon -> main
- Created: 2025-10-09 12:14:30 UTC
- Updated: 2026-05-15 21:06:50 UTC
- Completed: 2025-10-10 18:32:36 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: > Fix moves not being clicked when clicked on arrows, > Remove Chat icon

PR description:

-> Fix moves not being clicked when clicked on arrows, 
-> Remove Chat icon

---

### #82 Flutter dev/auto pin games

- URL: https://github.com/Chessever/chessever-frontend/pull/82
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/auto-pin-games -> main
- Created: 2025-10-08 11:13:53 UTC
- Updated: 2025-10-08 12:14:56 UTC
- Completed: 2025-10-08 12:13:05 UTC
- Merge commit: 55c3b5a72d2b208b93222c2395400270a75da5fa
- Labels: none
- Purpose / what it does: > Favorites players are pinned at the top, > Country men are pinned after favorites, > If all the players are from the same country, then the pins no longer appear, > Country pins and fav pins can be unpinned,

PR description:

-> Favorites players are pinned at the top,
-> Country men are pinned after favorites,
-> If all the players are from the same country, then the pins no longer appear,
-> Country pins and fav pins can be unpinned,
-> Fix Future Event Sort,

---

### #81 Fix Round exception

- URL: https://github.com/Chessever/chessever-frontend/pull/81
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: fix/rounds-exception -> main
- Created: 2025-10-07 19:54:17 UTC
- Updated: 2025-10-08 12:00:59 UTC
- Completed: 2025-10-08 12:00:51 UTC
- Merge commit: 047dc3ad44bb1b074736d3a05d0bb63bafab244b
- Labels: none
- Purpose / what it does: > Sort the rounds based on date, > Cleanup old boilerplate,

PR description:

-> Sort the rounds based on date,
-> Cleanup old boilerplate,

---

### #80 Automatically manage encryption in Testflight

- URL: https://github.com/Chessever/chessever-frontend/pull/80
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/automatically-manage-encryption -> main
- Created: 2025-10-06 20:45:21 UTC
- Updated: 2025-10-07 19:55:22 UTC
- Completed: 2025-10-07 19:55:20 UTC
- Merge commit: 145433c2ac3ffb35dace4823005e64fdf645e9f9
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Automatically manage encryption in Testflight.

PR description:

_No PR description provided._

---

### #79 Fix Freeze issue

- URL: https://github.com/Chessever/chessever-frontend/pull/79
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-splash-freeze-issue -> main
- Created: 2025-10-06 12:36:22 UTC
- Updated: 2026-05-15 21:06:46 UTC
- Completed: 2025-10-06 15:30:05 UTC
- Merge commit: d363a99ca83c6f2ba438528e0d83e273974806dd
- Labels: none
- Purpose / what it does: > Load the Audios in unawaited method in a microtask and avoid parallel cache, > Update main to have proper hierarchy for less errors and deadlocks,

PR description:

-> Load the Audios in unawaited method in a microtask and avoid parallel cache,
-> Update main to have proper hierarchy for less errors and deadlocks,

---

### #78 Fix Duplicate Star Events 

- URL: https://github.com/Chessever/chessever-frontend/pull/78
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/group-event -> main
- Created: 2025-10-06 05:35:45 UTC
- Updated: 2025-10-06 09:58:49 UTC
- Completed: 2025-10-06 09:58:45 UTC
- Merge commit: 84b2508f81a08ff46f0da532d9b6cd15fcf98019
- Labels: none
- Purpose / what it does: > Duplicate events fix for Past Events, > Enhance favorite and reload

PR description:

-> Duplicate events fix for Past Events,
-> Enhance favorite and reload

---

### #77 Group Event Optimization

- URL: https://github.com/Chessever/chessever-frontend/pull/77
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/group-event -> main
- Created: 2025-10-06 04:03:41 UTC
- Updated: 2025-10-06 04:27:16 UTC
- Completed: 2025-10-06 04:27:16 UTC
- Merge commit: 1deda2bce90b08d23b33ea29448f5329e6ea39f4
- Labels: none
- Purpose / what it does: > 15 mins cache for group events, > Cleanup code and view,

PR description:

-> 15 mins cache for group events,
-> Cleanup code and view,

---

### #76 PGN Copy & Sort

- URL: https://github.com/Chessever/chessever-frontend/pull/76
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/PGN_Copy_And_Sort -> main
- Created: 2025-10-05 16:26:42 UTC
- Updated: 2025-10-05 19:10:38 UTC
- Completed: 2025-10-05 19:10:35 UTC
- Merge commit: 2c80c8ec1a696c927e8f6b15269deed8fa94517d
- Labels: none
- Purpose / what it does: Sort in past games PGN Copy Make sure Evaluiation is proper

PR description:

- Sort in past games
- PGN Copy
- Make sure Evaluiation is proper

---

### #75 Feature : Games List Grid View and lazy building enhancement

- URL: https://github.com/Chessever/chessever-frontend/pull/75
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/grid-board -> main
- Created: 2025-10-03 19:42:47 UTC
- Updated: 2025-10-03 20:08:11 UTC
- Completed: 2025-10-03 20:08:08 UTC
- Merge commit: 83fa74f2ce1c61a08eb0ec6f92f302714ec45798
- Labels: none
- Purpose / what it does: > Add Grid View mode for games list, > Connect scroll filter, top list visible and scroll to index feature on view toggle and navigation, > Remove pre-load widgets in memory and add lazy loading approach for optimization,

PR description:

-> Add Grid View mode for games list,
-> Connect scroll filter, top list visible and scroll to index feature on view toggle and navigation,
-> Remove pre-load widgets in memory and add lazy loading approach for optimization,

---

### #74 Add chess analysis features with board navigation and evaluation display

- URL: https://github.com/Chessever/chessever-frontend/pull/74
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: staging -> main
- Created: 2025-10-01 10:48:10 UTC
- Updated: 2026-05-15 21:07:39 UTC
- Completed: 2025-10-10 13:12:24 UTC
- Merge commit: ac5e93299c289e930d3d5eedcd5e669c3f202a3e
- Labels: none
- Purpose / what it does: Refactored local storage repository class naming for clarity Implemented analysis mode with interactive board navigation Added principal variation display for engine lines Created chess game navigator and line display components

PR description:

- Refactored local storage repository class naming for clarity
- Implemented analysis mode with interactive board navigation
- Added principal variation display for engine lines
- Created chess game navigator and line display components
- Added evaluation utilities and analysis state management
- Enhanced move navigation with jump to start/end functionality
- Improved UI with dedicated analysis controls and move display

This is an umbrella PR merging **Varun's analysis-board->main PR#62** and **Thiru's UI Adaptations PR#68**

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

### #73 Update Package Name

- URL: https://github.com/Chessever/chessever-frontend/pull/73
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterde/update-package-name -> main
- Created: 2025-09-29 18:26:57 UTC
- Updated: 2025-09-30 13:01:37 UTC
- Completed: 2025-09-30 13:01:27 UTC
- Merge commit: e9acc827d0e4d597e0d5a198a48aa63c5d557f24
- Labels: none
- Purpose / what it does: > com.chessever.app

PR description:

-> com.chessever.app

---

### #72 Fix Auth Route and cleanup auth state

- URL: https://github.com/Chessever/chessever-frontend/pull/72
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-google-auth -> main
- Created: 2025-09-29 17:43:06 UTC
- Updated: 2025-09-29 17:52:14 UTC
- Completed: 2025-09-29 17:52:10 UTC
- Merge commit: 79d55a0b4eb2b1790d0bb5043013ae7dd3d882fe
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix Auth Route and cleanup auth state.

PR description:

_No PR description provided._

---

### #71 Re "UI Adaptions for analysis board"

- URL: https://github.com/Chessever/chessever-frontend/pull/71
- State: CLOSED
- Author: varunpvp (Varun Pujari)
- Branch: revert-70-revert-69-Thiru/UI_Adaption_For_Analysis_Board -> analysis-board
- Created: 2025-09-29 12:23:14 UTC
- Updated: 2026-05-15 21:07:37 UTC
- Completed: 2026-05-15 21:05:03 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Reverts Chessever/chessever-frontend#70

PR description:

Reverts Chessever/chessever-frontend#70

---

### #70 Revert "UI Adaptions for analysis board"

- URL: https://github.com/Chessever/chessever-frontend/pull/70
- State: MERGED
- Author: varunpvp (Varun Pujari)
- Branch: revert-69-Thiru/UI_Adaption_For_Analysis_Board -> analysis-board
- Created: 2025-09-29 11:35:24 UTC
- Updated: 2026-05-15 21:07:36 UTC
- Completed: 2025-09-29 11:35:35 UTC
- Merge commit: bd601a36001bc8e25c08d3746e94f5867097dbe8
- Labels: none
- Purpose / what it does: Reverts Chessever/chessever-frontend#69

PR description:

Reverts Chessever/chessever-frontend#69

---

### #69 UI Adaptions for analysis board

- URL: https://github.com/Chessever/chessever-frontend/pull/69
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/UI_Adaption_For_Analysis_Board -> analysis-board
- Created: 2025-09-29 10:55:44 UTC
- Updated: 2026-05-15 21:05:31 UTC
- Completed: 2025-09-29 10:55:54 UTC
- Merge commit: 02dc21df3704afa7251ab2ae0f6d28be5a63fce4
- Labels: none
- Purpose / what it does: Initial changes for UI Adaptations Board Theme Bottom navigation bar Settings of Analysis mode matched to the old one (Drag, zoom behaviour)

PR description:

Initial changes for UI Adaptations
- Board Theme
- Bottom navigation bar
- Settings of Analysis mode matched to the old one (Drag, zoom behaviour)
- Long press on move forward button goes to the beginning of game, same for move back button (Somewhat not working now - will check)
- Player Name Info displaying properly
- Clock

---

### #68 Inital changes for UI adaptations

- URL: https://github.com/Chessever/chessever-frontend/pull/68
- State: CLOSED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/UI_Adaptations_For_Analysis_Board -> analysis-board
- Created: 2025-09-29 01:32:05 UTC
- Updated: 2026-05-15 21:05:30 UTC
- Completed: 2026-05-15 21:05:06 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: Initial changes for UI Adaptations

PR description:

Initial changes for UI Adaptations

---

### #67 Fix live game clocks and evaluations

- URL: https://github.com/Chessever/chessever-frontend/pull/67
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/fix_live_game_clocks_and_evals -> main
- Created: 2025-09-29 00:24:24 UTC
- Updated: 2025-09-29 17:44:56 UTC
- Completed: 2025-09-29 17:44:53 UTC
- Merge commit: a9cf707ada3d38fa8494ef33f1da9c40f1564432
- Labels: none
- Purpose / what it does: Fix live game clocks and evaluations

PR description:

Fix live game clocks and evaluations

---

### #66 Thiru/UI adaptations for analysis board

- URL: https://github.com/Chessever/chessever-frontend/pull/66
- State: CLOSED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/UI_Adaptations_For_Analysis_Board -> main
- Created: 2025-09-28 08:32:22 UTC
- Updated: 2026-05-15 21:05:30 UTC
- Completed: 2025-09-28 08:32:57 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Thiru/UI adaptations for analysis board.

PR description:

_No PR description provided._

---

### #65 Fix Apple and Google Sign in

- URL: https://github.com/Chessever/chessever-frontend/pull/65
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-applesignin -> main
- Created: 2025-09-27 18:57:06 UTC
- Updated: 2025-09-27 20:00:02 UTC
- Completed: 2025-09-27 19:59:59 UTC
- Merge commit: 8b72fb390b01c47b5b337e5dd717b0bb3b79b1e0
- Labels: none
- Purpose / what it does: > Fix Apple Sign in, > Fix Google in,

PR description:

-> Fix Apple Sign in,
-> Fix Google in,

---

### #64 Preventing unnecessary supabase call

- URL: https://github.com/Chessever/chessever-frontend/pull/64
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/Preventing_Unnessarcy_Supabase_call -> main
- Created: 2025-09-27 14:10:21 UTC
- Updated: 2025-09-27 19:12:57 UTC
- Completed: 2025-09-27 19:12:54 UTC
- Merge commit: f37755bc272665360a15967c6522d0fb3d01ef78
- Labels: none
- Purpose / what it does: Preventing unnecessary supabase call When in Current screen tournament, Not rendering the other tabs (Past & Upcoming) Thus preventing.. and applicable for all the tabs Removed unnecessary function which will query entire data from a table

PR description:

- Preventing unnecessary supabase call
- When in Current screen tournament, Not rendering the other tabs (Past & Upcoming) Thus preventing.. and applicable for all the tabs
- Removed unnecessary function which will query entire data from a table

---

### #63 Preserve Board State

- URL: https://github.com/Chessever/chessever-frontend/pull/63
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterde/preserve-board-state -> main
- Created: 2025-09-27 08:59:57 UTC
- Updated: 2025-09-27 20:01:14 UTC
- Completed: 2025-09-27 20:01:11 UTC
- Merge commit: e385f8e554c996463466fe19e29c9ad9b6be298c
- Labels: none
- Purpose / what it does: > Remove autodispose from the state

PR description:

-> Remove autodispose from the state

---

### #62 Core Analysis Board Structure and Navigation Logic

- URL: https://github.com/Chessever/chessever-frontend/pull/62
- State: CLOSED
- Author: varunpvp (Varun Pujari)
- Branch: analysis-board -> main
- Created: 2025-09-27 07:04:17 UTC
- Updated: 2026-05-15 21:05:37 UTC
- Completed: 2026-05-15 21:04:37 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: This PR introduces the foundational data structure and state management required to transform the static game preview board into a **full-featured analysis board**. The key change is the implementation of a hierarchical game structure that fully supports multiple moves and variations. ** **New Data Model (ChessGame, ChessMove, ChessLine)**:

PR description:

### Description

This PR introduces the foundational data structure and state management required to transform the static game preview board into a **full-featured analysis board**.

The key change is the implementation of a hierarchical game structure that fully supports multiple moves and variations.

***

### Key Changes and Implementation Details

1.  **New Data Model (`ChessGame`, `ChessMove`, `ChessLine`)**:
    * The core models are **`ChessGame`**, **`ChessMove`**, and **`ChessLine`** (`typedef` for `List<ChessMove>`).
    * The game is represented using a custom JSON structure that stores the mainline as a list, with variations nested at the point of divergence.
    * Each move stores critical data like the `san`, `uci`, and the resulting board state (`fen`).

2.  **Dedicated Navigation Logic (`ChessGameNavigator`)**:
    * The new **`ChessGameNavigator`** class (`StateNotifier`) manages all game state logic, encapsulating complex traversal and manipulation logic from the UI.
    * **Hierarchical Navigation (`movePointer`)**: Navigation is handled by a `List<int>` called **`movePointer`** (e.g., `[4, 0, 1]`). This array precisely locates any move within the nested mainline/variation structure, supporting deep branching.
    * **Core Navigation Methods**: Implements essential control functions for all lines: `goToNextMove()`, `goToPreviousMove()`, `goToHead()`, and `goToTail()`.

3.  **The Core Interaction Method (`makeOrGoToMove`)**:
    * Implements the single, central method **`makeOrGoToMove(String uci)`**. This method intelligently determines the action:
        * **Continuation**: If the UCI move is the next move in the current line, it navigates forward.
        * **Existing Variation**: If the move matches an existing branch, it **switches the `movePointer`** to that variation.
        * **New Variation/Move**: If the move is valid but new, it **inserts the move** into the immutable game structure as a new variation and updates the `movePointer` to land on the new move.

***

### Next Steps

This foundation paves the way for integrating core analysis features:

* **Evaluation Bar**: Add the **Evaluation Bar** UI component to visualize the engine's assessment based on the current board position.
* **Engine Lines**: Display the engine's recommended moves and variations to the user.
* **Game Management**: Implement functionality for move deletion and variation promotion/demotion.

---

### #61 Feature/fix evalbar and clocks

- URL: https://github.com/Chessever/chessever-frontend/pull/61
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/fix_evalbar_and_clocks -> main
- Created: 2025-09-26 19:49:52 UTC
- Updated: 2025-09-26 19:58:10 UTC
- Completed: 2025-09-26 19:58:03 UTC
- Merge commit: 50944d20265234fc2c8f559c607079548c46bdce
- Labels: none
- Purpose / what it does: Fix everything regarding evalbar clocks and wrong game redirection from score card screen

PR description:

Fix everything regarding evalbar clocks and wrong game redirection from score card screen

---

### #60 Fallback to Stockfish

- URL: https://github.com/Chessever/chessever-frontend/pull/60
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fallback-stockfish -> main
- Created: 2025-09-26 13:07:18 UTC
- Updated: 2025-09-26 20:00:43 UTC
- Completed: 2025-09-26 19:58:49 UTC
- Merge commit: 3cc3bc0da99d41830bcaeac3b3aecfc51519c7b2
- Labels: none
- Purpose / what it does: > Fix the lichess api error case using local stockfish

PR description:

-> Fix the lichess api error case using local stockfish

---

### #59 Show or Hide games

- URL: https://github.com/Chessever/chessever-frontend/pull/59
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/Show_Or_Hide_Finished_Games -> main
- Created: 2025-09-26 02:51:57 UTC
- Updated: 2025-09-26 08:46:53 UTC
- Completed: 2025-09-26 08:46:49 UTC
- Merge commit: 6c515e2c4d4bb58c74e81f1e53bab786abf726de
- Labels: none
- Purpose / what it does: Show or Hide finished games

PR description:

- Show or Hide finished games

---

### #58 Fix Pinning Issue

- URL: https://github.com/Chessever/chessever-frontend/pull/58
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-pinning-issue -> main
- Created: 2025-09-25 13:14:39 UTC
- Updated: 2025-09-25 13:18:28 UTC
- Completed: 2025-09-25 13:18:24 UTC
- Merge commit: 758e2cfca5e872b473f53ec46f66c820c2298a6e
- Labels: none
- Purpose / what it does: > Fix the Incorrect use of Parent Widget causing grey screen in Release

PR description:

-> Fix the Incorrect use of Parent Widget causing grey screen in Release

---

### #57 Fix Pagination Issue

- URL: https://github.com/Chessever/chessever-frontend/pull/57
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-pagination -> main
- Created: 2025-09-25 12:01:32 UTC
- Updated: 2025-09-25 13:04:49 UTC
- Completed: 2025-09-25 13:04:34 UTC
- Merge commit: 99155c2aa8658408fd4d3ea3bc17087f3e6dc99b
- Labels: none
- Purpose / what it does: Remove the duplicate events created during pagination

PR description:

Remove the duplicate events created during pagination

---

### #56 Fix the stream of fen and last move

- URL: https://github.com/Chessever/chessever-frontend/pull/56
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix_fenstreaming -> main
- Created: 2025-09-25 11:40:32 UTC
- Updated: 2025-09-25 13:05:42 UTC
- Completed: 2025-09-25 13:05:38 UTC
- Merge commit: 8ffcc99d3372323210c23727ae3e631b08269a1f
- Labels: none
- Purpose / what it does: > use route observer to setup or destroy stream, > fix navigation and remove listeners from widgets, > update model to support stream update

PR description:

-> use route observer to setup or destroy stream,
-> fix navigation and remove listeners from widgets, 
-> update model to support stream update

---

### #55 Fix evaluation bar showing 0.0 and improve time streaming

- URL: https://github.com/Chessever/chessever-frontend/pull/55
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/fix_eval_bar_and_further_improve_time_remaining -> main
- Created: 2025-09-24 17:54:40 UTC
- Updated: 2025-09-24 18:15:51 UTC
- Completed: 2025-09-24 18:15:51 UTC
- Merge commit: 0433cf0bb8fe8daa5636e43b521caefe7f073a4b
- Labels: none
- Purpose / what it does: Fixed evaluation validation logic to accept legitimate 0.0 evaluations (balanced positions) Resolved database constraint errors preventing eval persistence Improved error handling for Lichess API failures with proper fallback Enhanced comprehensive game streaming for real-time clock updates

PR description:

- Fixed evaluation validation logic to accept legitimate 0.0 evaluations (balanced positions)
- Resolved database constraint errors preventing eval persistence
- Improved error handling for Lichess API failures with proper fallback
- Enhanced comprehensive game streaming for real-time clock updates
- Fixed type casting issues for clock data (num? to int?)
- Added evaluation caching and perspective-aware evaluation handling
- Improved Stockfish integration with proper mate score calculation
- Smoother evaluation bar animations with better debouncing

🤖 Generated with [Claude Code](https://claude.ai/code)

---

### #54 Remove three dots

- URL: https://github.com/Chessever/chessever-frontend/pull/54
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/remove-3dots -> main
- Created: 2025-09-24 08:49:45 UTC
- Updated: 2025-09-24 08:50:11 UTC
- Completed: 2025-09-24 08:50:05 UTC
- Merge commit: 5ec39c51a172d728fe6b0032705c561803d7d46c
- Labels: none
- Purpose / what it does: > Remove 3 dots from events card and add haptic feedback, > Remove three dots from games card and fix the scacing

PR description:

-> Remove 3 dots from events card and add haptic feedback, 
-> Remove three dots from games card and fix the scacing

---

### #53 Remove 3 dots

- URL: https://github.com/Chessever/chessever-frontend/pull/53
- State: CLOSED
- Author: flutterdev77 (Puru)
- Branch: flutter-dev/remove-three-dots -> main
- Created: 2025-09-24 08:46:40 UTC
- Updated: 2025-09-24 08:47:18 UTC
- Completed: 2025-09-24 08:47:18 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: > remove 3 dots from events card and add haptic feedback on long press, -> remove 3 dots from games card and update the spacing

PR description:

-> remove 3 dots from events card and add haptic feedback on long press, -> remove 3 dots from games card and update the spacing

---

### #52 feat: Implement comprehensive favorites system and fix player standings

- URL: https://github.com/Chessever/chessever-frontend/pull/52
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feat/close-tickets-9-10-114-118-89 -> main
- Created: 2025-09-24 00:18:33 UTC
- Updated: 2025-09-24 04:19:09 UTC
- Completed: 2025-09-24 04:19:06 UTC
- Merge commit: 177b3fa0f2b5f2c6aae79b17e04ab7f93bec5072
- Labels: none
- Purpose / what it does: Created unified favorites system for both players and events Added dedicated favorite cards for players and events in favorites screen Implemented player games screen to display complete game history for favorited players Fixed player standings calculation to use actual Supabase games instead of local storage

PR description:

- Created unified favorites system for both players and events
- Added dedicated favorite cards for players and events in favorites screen
- Implemented player games screen to display complete game history for favorited players
- Fixed player standings calculation to use actual Supabase games instead of local storage
- Enhanced dropdown width and responsiveness in score card appbar
- Removed 3-dot menu from completed event cards
- Added priority sorting for favorited items in lists
- Fixed navigation from player favorites to show comprehensive game history
- Implemented proper w:1, d:0.5, l:0 scoring system from actual game data

Closes tickets: #9, #10, #114, #118, #89

🤖 Generated with [Claude Code](https://claude.ai/code)

---

### #51 Update PGN to fen based approach for list view

- URL: https://github.com/Chessever/chessever-frontend/pull/51
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutter-dev/fix-fen-streamer -> main
- Created: 2025-09-23 21:43:48 UTC
- Updated: 2025-09-24 04:20:02 UTC
- Completed: 2025-09-24 04:19:59 UTC
- Merge commit: dad8e0c694326c4663a8deb515e7c6520e871048
- Labels: none
- Purpose / what it does: > Remove pgn fetcher for games list view (board mode), > Create last_move and fen data streamer and connect to GameCard and ChessBoardFromFENNew,

PR description:

-> Remove pgn fetcher for games list view (board mode),
-> Create last_move and fen data streamer and connect to GameCard and ChessBoardFromFENNew,

---

### #50 Fix FIDE Elo calculation and improve score display

- URL: https://github.com/Chessever/chessever-frontend/pull/50
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/vasif_scorecard_screen_feedbacks_further_improvements -> main
- Created: 2025-09-23 13:22:57 UTC
- Updated: 2025-09-23 18:53:56 UTC
- Completed: 2025-09-23 18:53:53 UTC
- Merge commit: 0ee37fd2b2c16479ce8f5a3c5bf9463072a8bd9e
- Labels: none
- Purpose / what it does: Corrected K-factor calculation to use standard FIDE values (K=20 for <2400, K=10 for 2400+) Removed unnecessary (W), (L), (D) letters from game results, showing only numeric scores Changed performance rating display to one decimal place for better readability 🤖 Generated with Claude Code

PR description:

- Corrected K-factor calculation to use standard FIDE values (K=20 for <2400, K=10 for 2400+)
- Removed unnecessary (W), (L), (D) letters from game results, showing only numeric scores
- Changed performance rating display to one decimal place for better readability

🤖 Generated with [Claude Code](https://claude.ai/code)

---

### #49 Feature/fix time remaining issues

- URL: https://github.com/Chessever/chessever-frontend/pull/49
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/fix_time_remaining_issues -> main
- Created: 2025-09-22 15:54:27 UTC
- Updated: 2025-09-24 03:55:17 UTC
- Completed: 2025-09-24 03:55:14 UTC
- Merge commit: e178493debe947d193e13c6a6a195d7cb881b41a
- Labels: none
- Purpose / what it does: fix all time remaining issues and add live countdown for live games.

PR description:

fix all time remaining issues and add live countdown for live games.

---

### #48 Fix Load Background Issue

- URL: https://github.com/Chessever/chessever-frontend/pull/48
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/preserve_state -> main
- Created: 2025-09-22 14:30:54 UTC
- Updated: 2025-09-22 15:16:27 UTC
- Completed: 2025-09-22 15:16:24 UTC
- Merge commit: 91e59ab0e77ee822f9d5649384887197929cdbd4
- Labels: none
- Purpose / what it does: > use a listener based approach for live ids for tournaments to prevent from rebuilding,

PR description:

-> use a listener based approach for live ids for tournaments to prevent from rebuilding,

---

### #47 Search Enhancement for Events

- URL: https://github.com/Chessever/chessever-frontend/pull/47
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/search-enhancement -> main
- Created: 2025-09-22 13:36:46 UTC
- Updated: 2025-09-22 15:13:45 UTC
- Completed: 2025-09-22 15:13:42 UTC
- Merge commit: 5baf4c86187eacf3bbab658c1ce301fbe55a34a3
- Labels: none
- Purpose / what it does: > Fix the search to have max matches >70%, > Use sql rpc for accurate result based on query

PR description:

-> Fix the search to have max matches >70%,
-> Use sql rpc for accurate result based on query

---

### #46 Implement Pin Feature in FEN Board

- URL: https://github.com/Chessever/chessever-frontend/pull/46
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/longTap-options -> main
- Created: 2025-09-22 10:39:07 UTC
- Updated: 2025-09-22 13:33:54 UTC
- Completed: 2025-09-22 13:33:50 UTC
- Merge commit: 2dc96040d55ef0c5d8a61768256fda2fb1728d48
- Labels: none
- Purpose / what it does: > Add Haptic Feedback on long press in Chess Board with FEN, > Show Options when long press in games Board with FEN widget,

PR description:

-> Add Haptic Feedback on long press in Chess Board with FEN,
-> Show Options when long press in games Board with FEN widget,

---

### #45 Eval bar abrupt fix

- URL: https://github.com/Chessever/chessever-frontend/pull/45
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/Evaluation_Bar_Abrupt_Fix -> main
- Created: 2025-09-21 17:23:11 UTC
- Updated: 2026-05-15 21:05:25 UTC
- Completed: 2025-09-21 17:23:33 UTC
- Merge commit: b2c694d99a76ec864be3af6f6dc3c9f1fb939bb6
- Labels: none
- Purpose / what it does: EValuation bar abrupt fix

PR description:

- EValuation bar abrupt fix

---

### #44 Pin Feature in Search view and normal view

- URL: https://github.com/Chessever/chessever-frontend/pull/44
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/feedback-fixes -> main
- Created: 2025-09-19 04:09:32 UTC
- Updated: 2025-09-19 05:57:48 UTC
- Completed: 2025-09-19 05:57:44 UTC
- Merge commit: 3fb9f6b83721334927e9bc65a16aaa58c3984f51
- Labels: none
- Purpose / what it does: > Users can pin the game during search mode, > After search view is removed , the pinned items will come to top, > The Refresh cleans up the search view and gets back to normal view, > Fix the Search Overflow,

PR description:

-> Users can pin the game during search mode,
-> After search view is removed , the pinned items will come to top,
-> The Refresh cleans up the search view and gets back to normal view,
-> Fix the Search Overflow,

---

### #43 feat: preserve scroll position when returning from chessboard

- URL: https://github.com/Chessever/chessever-frontend/pull/43
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/preserve-scroll-position-on-return -> main
- Created: 2025-09-18 21:30:56 UTC
- Updated: 2025-09-19 04:21:21 UTC
- Completed: 2025-09-19 04:21:19 UTC
- Merge commit: 76c99a6b480e1c4d0054f5f7ae3ea29c7205884d
- Labels: none
- Purpose / what it does: Add callback mechanism to capture returned game index from chessboard Update GameCardWrapperWidget to handle navigation result Implement scrolling to returned game position in GamesListView Pass callback through component hierarchy from ContentBody to GameCard

PR description:

- Add callback mechanism to capture returned game index from chessboard
- Update GameCardWrapperWidget to handle navigation result
- Implement scrolling to returned game position in GamesListView
- Pass callback through component hierarchy from ContentBody to GameCard

When user navigates to chessboard and swipes to different games, returning to the list view now scrolls to the last viewed game position.

🤖 Generated with [Claude Code](https://claude.ai/code)

---

### #42 feat: add Shorebird integration for over-the-air updates

- URL: https://github.com/Chessever/chessever-frontend/pull/42
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/shorebird_integration -> main
- Created: 2025-09-18 19:45:35 UTC
- Updated: 2025-09-19 04:17:42 UTC
- Completed: 2025-09-19 04:17:39 UTC
- Merge commit: 838c0b85f425e306d55f0a57cf04e70e9193f934
- Labels: none
- Purpose / what it does: Integrated Shorebird for seamless app updates without app store releases Updated .gitignore to track pubspec.lock and Podfile.lock files Added shorebird.yaml configuration file Updated iOS project settings to support Shorebird

PR description:

- Integrated Shorebird for seamless app updates without app store releases
- Updated .gitignore to track pubspec.lock and Podfile.lock files
- Added shorebird.yaml configuration file
- Updated iOS project settings to support Shorebird
- Added network entitlements for macOS Release configuration

🤖 Generated with [Claude Code](https://claude.ai/code)

---

### #41 Update chess piece sound effects

- URL: https://github.com/Chessever/chessever-frontend/pull/41
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/improved_sfx -> main
- Created: 2025-09-18 11:38:05 UTC
- Updated: 2025-09-18 19:47:09 UTC
- Completed: 2025-09-18 19:47:06 UTC
- Merge commit: 0f3267ba0a3919affda23d1c488bdf4e47210a5d
- Labels: none
- Purpose / what it does: Updated piece_castling.wav Updated piece_check.wav Updated piece_checkmate.wav Updated piece_takeover.wav

PR description:

- Updated piece_castling.wav
- Updated piece_check.wav
- Updated piece_checkmate.wav
- Updated piece_takeover.wav

🤖 Generated with Claude Code

---

### #40 Feature/improved score card screen and bug fix page scroll forward in chessboard

- URL: https://github.com/Chessever/chessever-frontend/pull/40
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/improved_score_card_screen_and_bug_fix_page_scroll_forward_in_chessboard -> main
- Created: 2025-09-18 01:37:41 UTC
- Updated: 2025-09-18 10:14:08 UTC
- Completed: 2025-09-18 10:13:50 UTC
- Merge commit: 79b5c1e7cb7d1e8b45df3c18aae13ff874170bc2
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feature/improved score card screen and bug fix page scroll forward in chessboard.

PR description:

_No PR description provided._

---

### #39 Flutter dev/fix auth

- URL: https://github.com/Chessever/chessever-frontend/pull/39
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutter-dev/fix-auth -> main
- Created: 2025-09-17 22:25:10 UTC
- Updated: 2025-09-18 10:16:33 UTC
- Completed: 2025-09-18 10:16:30 UTC
- Merge commit: 353e60acda80f8d352148c8499df4ef45af32338
- Labels: none
- Purpose / what it does: > Add Apple Sing in configuration in .env, > Remove riverpod generator, > Update Sign in with apple,

PR description:

-> Add Apple Sing in configuration in .env,
-> Remove riverpod generator,
-> Update Sign in with apple,

---

### #38 Re-Write Games Tour Screen and Fix existing bugs

- URL: https://github.com/Chessever/chessever-frontend/pull/38
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/update-game-tour -> main
- Created: 2025-09-17 19:37:22 UTC
- Updated: 2025-09-17 20:49:54 UTC
- Completed: 2025-09-17 20:49:51 UTC
- Merge commit: 526a1c74f5732584af0f2e5a8c5e0cb5a287a014
- Labels: none
- Purpose / what it does: > Fix the round based filter using scrollable_positioned_list, > Changing from Fen to Games will keep the scroll position intact for the top item, > Cleanup listeners from UI and implement it on scroll controller provider, > Fix null issue for groupBroadcastProvider,

PR description:

-> Fix the round based filter using scrollable_positioned_list,
-> Changing from Fen to Games will keep the scroll position intact for the top item,
-> Cleanup listeners from UI and implement it on scroll controller provider,
-> Fix null issue for groupBroadcastProvider,
-> Cleanup Code and remove boilerplate,

---

### #37 Upsert in Supabase

- URL: https://github.com/Chessever/chessever-frontend/pull/37
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/Upsert_In_Supabase -> main
- Created: 2025-09-17 16:44:52 UTC
- Updated: 2026-05-15 21:05:33 UTC
- Completed: 2025-09-17 16:45:42 UTC
- Merge commit: 3184d77e2d1a0e3e1a66269c25d577575fb2a326
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Upsert in Supabase.

PR description:

_No PR description provided._

---

### #36 Implement real-time chess clock countdown with atomic rebuilds

- URL: https://github.com/Chessever/chessever-frontend/pull/36
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/player_clock_countdown -> main
- Created: 2025-09-16 22:51:21 UTC
- Updated: 2025-09-17 13:51:44 UTC
- Completed: 2025-09-17 13:51:40 UTC
- Merge commit: 0ce5218870a3a9904f5cdb56ce706ba0db7ec871
- Labels: none
- Purpose / what it does: Add lastMoveTime field to Games and GamesTourModel with DateTime support Create date_time_provider.dart with StreamProvider for real-time updates Update GameCard and PlayerFirstRowDetailWidget with atomic HookConsumer rebuilds Implement countdown logic that only updates time text, not parent widgets

PR description:

- Add lastMoveTime field to Games and GamesTourModel with DateTime support
- Create date_time_provider.dart with StreamProvider for real-time updates
- Update GameCard and PlayerFirstRowDetailWidget with atomic HookConsumer rebuilds
- Implement countdown logic that only updates time text, not parent widgets
- Add safety checks to prevent negative time display
- Support turn-based countdown for ongoing games only

🤖 Commit Comments Generated with [Claude Code](https://claude.ai/code)

---

### #35 Display Games Result based on Rounds and Fix Past Event Sorting

- URL: https://github.com/Chessever/chessever-frontend/pull/35
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutter-dev/sort_past_events -> main
- Created: 2025-09-16 19:16:11 UTC
- Updated: 2025-09-17 07:11:28 UTC
- Completed: 2025-09-17 07:11:25 UTC
- Merge commit: 6c6eff466e79ef838bf58390256d9a10ec325273
- Labels: none
- Purpose / what it does: > Past events should be sorted based on their date of completion, > Games Search Result ordered by Rounds in Games Tab,

PR description:

-> Past events should be sorted based on their date of completion,
-> Games Search Result ordered by Rounds in Games Tab,

---

### #34 Fix event card search navigation - clicking on search result goes to …

- URL: https://github.com/Chessever/chessever-frontend/pull/34
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/click_on_one_event_but_go_to_another_fix -> main
- Created: 2025-09-16 18:27:51 UTC
- Updated: 2025-09-16 18:29:59 UTC
- Completed: 2025-09-16 18:29:42 UTC
- Merge commit: d6a47e82e4928789d8e7a43bb98cdc02fc2ca2e3
- Labels: none
- Purpose / what it does: …correct event Previously, when searching for events and clicking on a search result, users were always redirected to the 0th indexed event instead of the correct one. Root cause: The main events list (_groupBroadcastList) is populated from category-specific local storage, while search results come from global Supabase search. When a search result tournament wasn't found in the limited category list, the orElse fa...

PR description:

…correct event

Previously, when searching for events and clicking on a search result, users were always redirected to the 0th indexed event instead of the correct one.

Root cause: The main events list (_groupBroadcastList) is populated from category-specific local storage, while search results come from global Supabase search. When a search result tournament wasn't found in the limited category list, the orElse fallback always returned the first event.

Solution:
- Replace dangerous orElse fallback with proper null handling
- First attempt to find tournament in current category list
- If not found, fetch directly from repository using getGroupBroadcastById
- Add proper error handling with AsyncValue.error for UI toast notifications
- Use context.mounted check for safe async navigation

Also add .mcp.json to gitignore to exclude personal development configuration.

🤖 Commit Comments Generated with [Claude Code](https://claude.ai/code)

---

### #33 IOS Release update

- URL: https://github.com/Chessever/chessever-frontend/pull/33
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutter-dev/ios-release-config -> main
- Created: 2025-09-16 17:10:33 UTC
- Updated: 2025-09-16 17:45:16 UTC
- Completed: 2025-09-16 17:45:13 UTC
- Merge commit: 275fdba79fdb431b1332e7afae3b5d4af90981e7
- Labels: none
- Purpose / what it does: > Add missing info.plist config, > Update build for release mode

PR description:

-> Add missing info.plist config,
-> Update build for release mode

---

### #32 Feature/fide flag and more sfx

- URL: https://github.com/Chessever/chessever-frontend/pull/32
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/fide_flag_and_more_sfx -> main
- Created: 2025-09-16 16:59:22 UTC
- Updated: 2025-09-16 17:12:04 UTC
- Completed: 2025-09-16 17:12:01 UTC
- Merge commit: c7daadbde7b1dff23a758450a00b46769b0f6e41
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Feature/fide flag and more sfx.

PR description:

_No PR description provided._

---

### #31 Mate in Eval bar

- URL: https://github.com/Chessever/chessever-frontend/pull/31
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/Bug_Mate_In_EvalBar -> main
- Created: 2025-09-16 16:00:35 UTC
- Updated: 2026-05-15 21:05:22 UTC
- Completed: 2025-09-16 16:00:44 UTC
- Merge commit: 7112826508274a07a5062398307e4c89663792f0
- Labels: none
- Purpose / what it does: Mate in Eval bar Including new prop called mate in Principal variation

PR description:

- Mate in Eval bar
- Including new prop called mate in Principal variation

---

### #30 Remove Negative evaluation

- URL: https://github.com/Chessever/chessever-frontend/pull/30
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/remove-negative-value -> main
- Created: 2025-09-16 07:15:05 UTC
- Updated: 2025-09-16 16:20:06 UTC
- Completed: 2025-09-16 16:20:03 UTC
- Merge commit: 726b106afa141aca3de22e572d45d1be962281f5
- Labels: none
- Purpose / what it does: > The values of evaluation bar should not be in negative, > reduce the width of evaluation bar in games tour screen board view,

PR description:

-> The values of evaluation bar should not be in negative,
-> reduce the width of evaluation bar in games tour screen board view,

---

### #29 Convert UTC to local Time

- URL: https://github.com/Chessever/chessever-frontend/pull/29
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/utc-to-localtime -> main
- Created: 2025-09-15 13:17:35 UTC
- Updated: 2025-09-15 16:31:12 UTC
- Completed: 2025-09-15 16:31:09 UTC
- Merge commit: 2ca1c2adcbf8b5c5741d7be957629ec3e1a031e7
- Labels: none
- Purpose / what it does: Convert UTC to Local Time, Update AppBar to show local time,

PR description:

1. Convert UTC to Local Time,
2. Update AppBar to show local time,

---

### #28 Update Search Result and Enhance the Switcher Widget

- URL: https://github.com/Chessever/chessever-frontend/pull/28
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutter-dev/enhance-group-search -> main
- Created: 2025-09-15 09:31:49 UTC
- Updated: 2025-09-15 12:36:43 UTC
- Completed: 2025-09-15 12:17:02 UTC
- Merge commit: 34d850be5e25120d334f641915f316ed4e208943
- Labels: none
- Purpose / what it does: > Enhance Group Search to be sorted based on Datetime, > Fix the top segmented switcher to switch the state properly based on selection,

PR description:

-> Enhance Group Search to be sorted based on  Datetime,
-> Fix the top segmented switcher to switch the state properly based on selection,

---

### #27 Best moves by arrows

- URL: https://github.com/Chessever/chessever-frontend/pull/27
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/Best_Move_Arrows_In_Board -> main
- Created: 2025-09-14 15:21:36 UTC
- Updated: 2026-05-15 21:05:21 UTC
- Completed: 2025-09-14 15:22:13 UTC
- Merge commit: 806f20900e1964deab5a61f0dd13bddf5e9deb3b
- Labels: none
- Purpose / what it does: Best moves indicated by arrows in Analysis mode as well Normal mode

PR description:

- Best moves indicated by arrows in Analysis mode as well Normal mode

---

### #26 Don't Throw Exception on null check

- URL: https://github.com/Chessever/chessever-frontend/pull/26
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutter-dev/fix-null-checker -> main
- Created: 2025-09-14 08:16:05 UTC
- Updated: 2025-09-14 12:00:05 UTC
- Completed: 2025-09-14 12:00:03 UTC
- Merge commit: 1f9c9cbe20cef337c2b8ccaec2127d988e53d764
- Labels: none
- Purpose / what it does: > Update the state to be in loading if the Id is null, > Remove exception and pass the null id in the notifier,

PR description:

-> Update the state to be in loading if the Id is null,
-> Remove exception and pass the null id in the notifier,

---

### #25 Fix missing country flags for chess federation codes

- URL: https://github.com/Chessever/chessever-frontend/pull/25
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/missing_flags -> main
- Created: 2025-09-12 22:02:37 UTC
- Updated: 2025-09-13 07:03:21 UTC
- Completed: 2025-09-12 22:16:34 UTC
- Merge commit: 61edd24916702ea7a27c95769ea27aa54c2abde8
- Labels: none
- Purpose / what it does: Add comprehensive federation code to ISO country code mapping (180+ codes) (Taken from FIDE website) Update LocationService.getValidCountryCode() with multiple fallback strategies Fix GameCard widget to use mapped country code instead of raw federation code Ensure flags display correctly for players like Bluebaum, Matthias (GER -> DE)

PR description:

- Add comprehensive federation code to ISO country code mapping (180+ codes) (Taken from FIDE website)
- Update LocationService.getValidCountryCode() with multiple fallback strategies
- Fix GameCard widget to use mapped country code instead of raw federation code
- Ensure flags display correctly for players like Bluebaum, Matthias (GER -> DE)

🤖 Commit Comments Generated with [Claude Code](https://claude.ai/code)

---

### #24 Improve game dropdown readability in chess board screen

- URL: https://github.com/Chessever/chessever-frontend/pull/24
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/dropdown_menu_not_readable_in_game -> main
- Created: 2025-09-12 19:47:40 UTC
- Updated: 2025-09-13 07:03:27 UTC
- Completed: 2025-09-12 22:17:11 UTC
- Merge commit: 0f5a3ef796e0156deeb176163aec8294a860276c
- Labels: none
- Purpose / what it does: Increase dropdown width from 200w to 300w for better readability Implement smart name formatting that prioritizes full names over abbreviation Progressive abbreviation logic that preserves family names while shortening first/middle names only when necessary Different width constraints for dropdown header vs items for optimal space usage

PR description:

- Increase dropdown width from 200w to 300w for better readability
- Implement smart name formatting that prioritizes full names over abbreviation
- Progressive abbreviation logic that preserves family names while shortening first/middle names only when necessary
- Different width constraints for dropdown header vs items for optimal space usage

🤖 Commit Comments Generated with [Claude Code](https://claude.ai/code)

---

### #23 Pin Feature update and Fix wrong game PGN data

- URL: https://github.com/Chessever/chessever-frontend/pull/23
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutter-dev/fix-pin-scroll-issue -> main
- Created: 2025-09-12 19:31:20 UTC
- Updated: 2025-09-12 22:15:23 UTC
- Completed: 2025-09-12 22:15:20 UTC
- Merge commit: b81669367d8fd96a80c07d60278e3c613968fc72
- Labels: none
- Purpose / what it does: > Save pin to local storage based on tournament id, > Fix unexpected scroll on pinning game, > Fix wrong game PGN data, > Enhance the search mechanism,

PR description:

-> Save pin to local storage based on tournament id, 
-> Fix unexpected scroll on pinning game,
-> Fix wrong game PGN data,
-> Enhance the search mechanism,

---

### #22 Add results display for finished games on board and list view

- URL: https://github.com/Chessever/chessever-frontend/pull/22
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/results_on_board_and_list_view -> main
- Created: 2025-09-12 18:29:16 UTC
- Updated: 2025-09-12 19:18:42 UTC
- Completed: 2025-09-12 19:18:39 UTC
- Merge commit: 89b2b39500db77ee009af899796beae287ff601d
- Labels: none
- Purpose / what it does: Modified PlayerFirstRowDetailWidget to show game results (1, 0, ½) for finished games when at the latest move Refactored widget to accept GamesTourModel and calculate player data internally 🤖 Commit Comments Generated with Claude Code

PR description:

- Modified PlayerFirstRowDetailWidget to show game results (1, 0, ½) for finished games when at the latest move
- Refactored widget to accept GamesTourModel and calculate player data internally

🤖 Commit Comments Generated with [Claude Code](https://claude.ai/code)

---

### #21 Fix Search and pin feature and update the Group Event Screen

- URL: https://github.com/Chessever/chessever-frontend/pull/21
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/fix-games-tour-screen -> main
- Created: 2025-09-12 12:42:24 UTC
- Updated: 2025-09-12 14:23:56 UTC
- Completed: 2025-09-12 14:23:53 UTC
- Merge commit: 1c983375a45f4cf5ae7e506acf828e004ada78d6
- Labels: none
- Purpose / what it does: > Fix search dismiss feature, > Enhance Round filtering, > Fix Pin feature > Update Group Event to be Paginated for Past Tab,

PR description:

-> Fix search dismiss feature,
-> Enhance Round filtering,
-> Fix Pin feature
-> Update Group Event to be Paginated for Past Tab,
-> Enhance the Search feature for group event and player search,

---

### #20 Add chessboard sound effects functionality

- URL: https://github.com/Chessever/chessever-frontend/pull/20
- State: MERGED
- Author: devberkay (Berkay Can)
- Branch: feature/chessboard_sfx -> main
- Created: 2025-09-12 09:22:18 UTC
- Updated: 2025-09-12 09:34:26 UTC
- Completed: 2025-09-12 09:34:23 UTC
- Merge commit: 0cab40ad97a18b9e0211edf9793b15fdaa1275d4
- Labels: none
- Purpose / what it does: Add AudioPlayerService singleton for managing sound effects Integrate flutter_soloud package for audio playback Add piece_move.wav sound effect asset Implement sound on chess moves in chess_board_screen_new.dart

PR description:

- Add AudioPlayerService singleton for managing sound effects
- Integrate flutter_soloud package for audio playback
- Add piece_move.wav sound effect asset
- Implement sound on chess moves in chess_board_screen_new.dart
- Initialize audio service on app startup

🤖 Commit Comments Generated with [Claude Code](https://claude.ai/code)

---

### #19 Update search to game screen

- URL: https://github.com/Chessever/chessever-frontend/pull/19
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutter-dev/fix-games-screen -> main
- Created: 2025-09-11 15:41:26 UTC
- Updated: 2025-09-11 15:41:45 UTC
- Completed: 2025-09-11 15:41:37 UTC
- Merge commit: 77373cdc4004c325562496ebc53ea39156b1e05b
- Labels: none
- Purpose / what it does: > Cleanup and update the screen

PR description:

-> Cleanup and update the screen

---

### #18 Update games tour screen

- URL: https://github.com/Chessever/chessever-frontend/pull/18
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/games-tour-update -> main
- Created: 2025-09-11 09:11:50 UTC
- Updated: 2025-09-11 09:12:03 UTC
- Completed: 2025-09-11 09:12:00 UTC
- Merge commit: ab8bd7f161fa5e6425cfd7f247cfe81961837b4b
- Labels: none
- Purpose / what it does: > Fix the riverpod flow, > Directly pass the model instead of a new riverpod for id,

PR description:

-> Fix the riverpod flow,
-> Directly pass the model instead of a new riverpod for id,

---

### #17 Flutter dev/updates and fixes

- URL: https://github.com/Chessever/chessever-frontend/pull/17
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/updates-and-fixes -> main
- Created: 2025-09-10 14:51:48 UTC
- Updated: 2025-09-10 14:52:00 UTC
- Completed: 2025-09-10 14:51:57 UTC
- Merge commit: dd1e74b24b08ec37677940a614c574b24685b3d7
- Labels: none
- Purpose / what it does: > Combined Search feature using Supabase, > Update Upcoming View, > Create Past Tab, > Cleanup Riverpod and structure more properly

PR description:

-> Combined Search feature using Supabase,
-> Update Upcoming View,
-> Create Past Tab,
-> Cleanup Riverpod and structure more properly

---

### #16 Stockfish cascade fix

- URL: https://github.com/Chessever/chessever-frontend/pull/16
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/StockFish_Queue_Removed_Cascade_Fix -> main
- Created: 2025-09-07 14:52:58 UTC
- Updated: 2026-05-15 21:05:28 UTC
- Completed: 2025-09-07 14:54:03 UTC
- Merge commit: d215ff3874ea4f77fd71e6a06e9aba8328ebae72
- Labels: none
- Purpose / what it does: Removed stockfish singleton - Cancel old evaluation & only priortize new evaluation Provider cache fix upsert in postion tables for safety

PR description:

- Removed stockfish singleton - Cancel old evaluation & only priortize new evaluation
- Provider cache fix
- upsert in postion tables for safety

---

### #15 Cascasde eval

- URL: https://github.com/Chessever/chessever-frontend/pull/15
- State: CLOSED
- Author: ThiruDev50 (Thiru)
- Branch: Thiru/ref_Cascade_Eval_Beta -> main
- Created: 2025-09-07 14:44:32 UTC
- Updated: 2026-05-15 21:05:34 UTC
- Completed: 2025-09-07 14:52:41 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Cascasde eval.

PR description:

_No PR description provided._

---

### #14 Fix chessboard order of games to be correct

- URL: https://github.com/Chessever/chessever-frontend/pull/14
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/updates-and-fixes -> main
- Created: 2025-09-06 08:12:48 UTC
- Updated: 2025-09-07 16:53:51 UTC
- Completed: 2025-09-07 16:53:49 UTC
- Merge commit: 3c872ba1bd77a6f26256d7412e5ef55cad24e076
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Fix chessboard order of games to be correct.

PR description:

_No PR description provided._

---

### #13 Board Updates and Country Selector Updates 

- URL: https://github.com/Chessever/chessever-frontend/pull/13
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutter-dev/screen-updates -> main
- Created: 2025-09-02 20:56:14 UTC
- Updated: 2025-09-03 10:48:31 UTC
- Completed: 2025-09-03 10:48:28 UTC
- Merge commit: 08fd148a4999cd7f0befc47d46decc258befac5f
- Labels: none
- Purpose / what it does: > Setup initial Fen data, > Add Error catchers for country selection button, > Enhance Games Tour Screen to load once for the same session and for same game,

PR description:

-> Setup initial Fen data,
-> Add Error catchers for country selection button,
-> Enhance Games Tour Screen to load once for the same session and for same game,

---

### #12 Skipping evaluation for analysis mode

- URL: https://github.com/Chessever/chessever-frontend/pull/12
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: feature/Thiru_Skipping_Evaluation_For_AnalysisMode -> main
- Created: 2025-09-02 14:01:03 UTC
- Updated: 2026-05-15 21:06:04 UTC
- Completed: 2025-09-02 14:01:11 UTC
- Merge commit: 473b10d3cc7a453eeaad927c99c25ba01ce8fced
- Labels: none
- Purpose / what it does: Skipping evaluation for analysis mode

PR description:

- Skipping evaluation for analysis mode

---

### #11 Initial changes for analysis mode

- URL: https://github.com/Chessever/chessever-frontend/pull/11
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: feature/Thiru_Analysis_Mode -> main
- Created: 2025-09-02 13:48:50 UTC
- Updated: 2026-05-15 21:05:56 UTC
- Completed: 2025-09-02 13:48:59 UTC
- Merge commit: 26720c71be775e9fd4d46a7142d9a3d788369d5f
- Labels: none
- Purpose / what it does: Initial changes for analysis mode

PR description:

- Initial changes for analysis mode

---

### #10 Analysis mode beta

- URL: https://github.com/Chessever/chessever-frontend/pull/10
- State: CLOSED
- Author: ThiruDev50 (Thiru)
- Branch: feature/Thiru_Analysis_Mode_Beta -> main
- Created: 2025-09-02 13:07:48 UTC
- Updated: 2026-05-15 21:05:58 UTC
- Completed: 2025-09-02 13:49:24 UTC
- Merge commit: n/a
- Labels: none
- Purpose / what it does: No PR description provided; inferred from title/branch only: Analysis mode beta.

PR description:

_No PR description provided._

---

### #9 Evail bar fixes and tournament screen updates

- URL: https://github.com/Chessever/chessever-frontend/pull/9
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/cleanup-optimize -> main
- Created: 2025-09-01 20:11:32 UTC
- Updated: 2025-09-02 19:32:57 UTC
- Completed: 2025-09-02 19:32:54 UTC
- Merge commit: 6e4efda32d926af3a58aa64afd84a2db8ec2df1f
- Labels: none
- Purpose / what it does: > Fix the evaluation bar not to bounce off, > Create a no tournament found screen,

PR description:

-> Fix the evaluation bar not to bounce off,
-> Create a no tournament found screen,

---

### #8 Flutter dev/cleanup optimize

- URL: https://github.com/Chessever/chessever-frontend/pull/8
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/cleanup-optimize -> main
- Created: 2025-08-31 20:12:10 UTC
- Updated: 2025-09-01 10:38:05 UTC
- Completed: 2025-09-01 10:38:05 UTC
- Merge commit: 6fe4b60e1f5ae4869eaf2f11557e76ec95d92c08
- Labels: none
- Purpose / what it does: > Cleanup and enhance Favorite, > Fix the move to next move in board, > Fix latest round to appear at the top in Games Screen, > Cleanup games app bar logic

PR description:

-> Cleanup and enhance Favorite,
-> Fix the move to next move in board,
-> Fix latest round to appear at the top in Games Screen,
-> Cleanup games app bar logic

---

### #7 Flutter dev/cleanup optimize

- URL: https://github.com/Chessever/chessever-frontend/pull/7
- State: MERGED
- Author: flutterdev77 (Puru)
- Branch: flutterDev/cleanup-optimize -> main
- Created: 2025-08-30 19:33:07 UTC
- Updated: 2025-08-31 01:42:17 UTC
- Completed: 2025-08-31 01:42:17 UTC
- Merge commit: c474c0ff629a8bdf4a6392c703ddb1fc40080c73
- Labels: none
- Purpose / what it does: > Remove old dart files, > Relocate Files and Folder in their respective sub-directory, > Rename and Refactor

PR description:

-> Remove old dart files,
-> Relocate Files and Folder in their respective sub-directory,
-> Rename and Refactor

---

### #6 Board theme and Tournament name fix

- URL: https://github.com/Chessever/chessever-frontend/pull/6
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: feature/Thiru_Board_Theme_And_Width_Fix -> main
- Created: 2025-08-27 16:04:51 UTC
- Updated: 2026-05-15 21:05:59 UTC
- Completed: 2025-08-27 16:04:59 UTC
- Merge commit: c931d20f5a9d1ea8c877aee61c0558615d2f858a
- Labels: none
- Purpose / what it does: Board theme Width for tournament name

PR description:

- Board theme
- Width for tournament name

<img width="460" height="971" alt="image" src="https://github.com/user-attachments/assets/0b0ea814-23b9-49c6-8d5a-f04257025057" />
<img width="451" height="1006" alt="image" src="https://github.com/user-attachments/assets/d0fd6948-20fb-4266-a2b6-75d2e5b02515" />

---

### #5 ChessBoard from FEN using chessground package

- URL: https://github.com/Chessever/chessever-frontend/pull/5
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: feature/Thiru_ChessBoardFromFen_With_ChessGround_Package -> main
- Created: 2025-08-24 14:12:45 UTC
- Updated: 2026-05-15 21:06:01 UTC
- Completed: 2025-08-24 14:19:13 UTC
- Merge commit: d0956aeb728985806ecfa0e6059d1010e568306b
- Labels: none
- Purpose / what it does: ChessBoardFromFen widget using chessground package

PR description:

- ChessBoardFromFen widget using chessground package

---

### #4 Replacing Board with chessground package

- URL: https://github.com/Chessever/chessever-frontend/pull/4
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: feature/Thiru_Replace_Board_By_Chess_Ground -> main
- Created: 2025-08-24 13:51:52 UTC
- Updated: 2026-05-15 21:06:02 UTC
- Completed: 2025-08-24 13:52:00 UTC
- Merge commit: cd1a7f0b22dfedeb0ca6434ab5f342dd2bcce429
- Labels: none
- Purpose / what it does: using chessground package Inlcuding dartchess package for supporting functionalities

PR description:

- using chessground package
- Inlcuding dartchess package for supporting functionalities

---

### #3 Improvements in sliding board

- URL: https://github.com/Chessever/chessever-frontend/pull/3
- State: MERGED
- Author: ThiruDev50 (Thiru)
- Branch: feature/Improvements_In_Sliding_Board -> main
- Created: 2025-08-17 14:16:19 UTC
- Updated: 2025-08-17 17:41:40 UTC
- Completed: 2025-08-17 17:07:32 UTC
- Merge commit: 24840c112e24ac4e580b706270bf98acd5d14e49
- Labels: none
- Purpose / what it does: Improvements in Sliding board Better view for Tournament selection Changes for these Tasks: https://www.notion.so/Sliding-on-the-board-should-be-improved-23ba1076c72a80b9b672cb978ea0f718

PR description:

- Improvements in Sliding board
- Better view for Tournament selection

Changes for these Tasks:
- https://www.notion.so/Sliding-on-the-board-should-be-improved-23ba1076c72a80b9b672cb978ea0f718
- https://www.notion.so/Better-View-in-Tournament-selection-250a1076c72a80368895eba7cbbab8f7

---

### #2 Switch to Chessground board and dartchess logic

- URL: https://github.com/Chessever/chessever-frontend/pull/2
- State: CLOSED
- Author: hwuebben
- Branch: codex/replace-chessboard-with-chessground-and-update-logic -> main
- Created: 2025-08-16 14:20:57 UTC
- Updated: 2026-05-15 21:05:44 UTC
- Completed: 2025-09-27 07:04:25 UTC
- Merge commit: n/a
- Labels: codex
- Purpose / what it does: replace AdvancedChessBoard with Chessground widget migrate chess logic to dartchess Game objects remove legacy advanced_chess_board package and update dependencies

PR description:

## Summary
- replace AdvancedChessBoard with Chessground widget
- migrate chess logic to dartchess Game objects
- remove legacy advanced_chess_board package and update dependencies

## Testing
- `flutter pub get` *(fails: command not found)*

------
https://chatgpt.com/codex/tasks/task_e_689f964f2d30832382e1b4be35291eaa

---

### #1 only relevant tournaments

- URL: https://github.com/Chessever/chessever-frontend/pull/1
- State: MERGED
- Author: hwuebben
- Branch: feature/only_relevant_tournaments -> main
- Created: 2025-07-13 22:12:10 UTC
- Updated: 2025-07-14 09:13:38 UTC
- Completed: 2025-07-14 09:13:34 UTC
- Merge commit: 04795e273f4cd0e300091150ed526d0017626b29
- Labels: none
- Purpose / what it does: created a view in supabase that entails only the relevant tournaments. pull from this view.

PR description:

created a view in supabase that entails only the relevant tournaments.
pull from this view.

---
