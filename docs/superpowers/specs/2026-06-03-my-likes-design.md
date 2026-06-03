# My Likes — design spec

Date: 2026-06-03
Status: approved-pending (proceeding on recommended defaults)

## Goal

Rename the "Liked Games" feature to **My Likes** and give it a dedicated, tab-less
screen that mirrors the **For You → Favorites → Games** tab exactly: same search +
filter button, same date-section cards, same game card. All filters available in the
Favorites Games tab must be available here. Free users may like an unlimited number of
games, but on the My Likes page they may only **open** games liked within the last 7
days (today + the 6 prior calendar days). Older likes render with a lock icon + PREMIUM
badge and route to the paywall on tap. Premium users may open everything.

## Current architecture (as found)

- A "like" is a normal `SavedAnalysis` row in Supabase `user_saved_analyses`, placed in
  the user's special `user_folders` row where `is_liked_games = true` (name `'Liked Games'`,
  created lazily by `ensureLikedGamesFolder()` in `library_repository.dart`). There is no
  separate liked-games table and no local (Hive/SharedPreferences/sqlite) store.
- The full game is stored in `chess_game` jsonb = `{ id, sf, md, m }`. `md` holds PGN
  headers: `White/Black`, `WhiteElo/BlackElo`, `WhiteFed/BlackFed`, `WhiteTitle/BlackTitle`,
  `WhiteFideId/BlackFideId`, `ECO`, `Opening`, `Result`, `Date` (played date, `YYYY.MM.DD`),
  `TimeControl` (raw PGN increment string), `Event/Round/BroadcastName`, `Variant`.
- `SavedAnalysis.createdAt` = liked-at timestamp. `getSavedAnalyses` orders `created_at DESC`.
- `likedGamesProvider` (`AsyncNotifierProvider<LikedGamesNotifier, List<SavedAnalysis>>`)
  is the in-memory source of truth; `isGameLikedProvider` derives board-heart state.
- No dedicated screen: the liked folder is pinned first on Library home
  (`library_screen.dart`) and opens the generic `FolderContentsScreen`
  (it is a `database` node) which lists `BookSavedGameCard`.
- Favorites Games tab = `FavoritesGamesTab` (`lib/screens/favorites/tabs/favorites_games_tab.dart`),
  a self-contained body with no Scaffold: `RefreshIndicator > CustomScrollView` of
  [search bar, filter chips, content sliver]. Private `_groupGamesByDate` (buckets by
  `GamesTourModel.bucketDate`), `_formatDateHeader` (Today/Yesterday/`EEEE, MMM d`),
  `_DateHeader` widget. Fed by `favoritesCombinedGamesProvider` (favorite players' games).
- Filters: `GameFilter` model + `GameFilterHelper.applyFilter(List<GamesTourModel>, filter,
  {playerNameQuery, targetFideId})` (generic, source-agnostic) + `showGameFilterDialog`.
  Favorites passes `showFormatFilter:false`. Effective dims there: result, color, time
  control, live, min-rating tier, year range. ECO and Format are not user-settable there.
- Premium: `subscriptionProvider` (RevenueCat) → `ref.watch(subscriptionProvider).isSubscribed`.
  Paywall: `requirePremiumGuard(context, ref)` / `showPremiumPaywallSheet(context:)`.
  No lock-badge list overlay and no time-window gating exist yet. `requirePremiumGuard`
  returns `true` in `kDebugMode`.

## Filter-data gap analysis

`GameFilterHelper` runs on `GamesTourModel`; `convertSavedAnalysisToGame()` rebuilds one
from `md`. Coverage of the favorites Games-tab filter dimensions:

- Result — OK (`md['Result']`).
- Min-rating tier — OK (`max(WhiteElo, BlackElo)` → `cardElo`).
- Year range — OK (`md['Date'].year` → `lastMoveTime`).
- Color — needs a target player identity; My Likes has none, so it no-ops (same as
  favorites with no single player chip). Acceptable.
- Live/completed — a like is always a completed game. Acceptable.
- **Time control (rapid/blitz/classical) — GAP.** Only the raw PGN `TimeControl` string is
  saved; the broadcast category (`GamesTourModel.timeControl`) is dropped at like-time, so
  `_inferTimeControl` cannot match and the filter silently no-ops.
- Format (online/OTB) — hidden in the favorites tab (`showFormatFilter:false`), so not
  required for parity. (Memory: Format is TWIC-only.)

Therefore the only required save-side change for filter parity is to persist the
**time-control category**. We also persist the online flag cheaply for future-proofing, and
fix the converter to stop discarding FIDE ids.

## Design

### 1. Save-side: capture filter metadata at like-time
`liked_games_provider.dart::_resolveChessGame()` (and, for parity, the manual save path in
`add_to_folder_sheet.dart::_resolveChessGame()`): additionally write
- `md['TcCategory']` = the source `GamesTourModel.timeControl` (broadcast category), and
- `md['IsOnline']` = `game.isOnline`.

No schema/migration — these are new keys inside the existing `chess_game` jsonb. Existing
rows lack them; the TC filter simply no-ops for old likes (graceful degradation).

### 2. Converter: stop dropping data
`load_saved_analysis.dart::convertSavedAnalysisToGame()`:
- Read `md['WhiteFideId']/['BlackFideId']` into `PlayerCard.fideId` (currently hard-coded null).
- Prefer `md['TcCategory']` for `timeControl` (fallback to existing behavior).
- Set `isOnline` from `md['IsOnline']`.
These changes are backward-safe (null/absent → current defaults).

### 3. Shared date-section widget
Extract the favorites date-section header into a small public widget
`DateSectionHeader` (label + count + collapse chevron) in a shared location so My Likes
renders the identical card. (Favorites/countrymen copies left untouched for now to limit
scope; a later cleanup can migrate them.) My Likes supplies its own grouping function that
buckets by **liked-at** (see Decision below).

### 4. My Likes provider
`lib/screens/my_likes/provider/my_likes_provider.dart`:
- Holds `GameFilter` + `searchQuery` (mirrors the favorites notifier's surface:
  `applyFilter`, `clearFilter`, `searchGames`, `clearSearch`).
- Watches `likedGamesProvider`, maps each `SavedAnalysis` → `(analysis, GamesTourModel)`
  pairs (keeping `analysis` for `createdAt` + navigation), applies
  `GameFilterHelper.applyFilter` + the title/White/Black/Event search predicate (the
  folder_contents precedent), and groups the survivors by `analysis.createdAt` into
  date buckets (newest first).

### 5. My Likes screen
`lib/screens/my_likes/my_likes_screen.dart`: a `Scaffold` (own header "My Likes",
status-bar spacer) wrapping a `CustomScrollView` = [search bar, filter button using
`showGameFilterDialog(showFormatFilter:false)`, date-grouped slivers]. Each row = the game
card (card mode only) wrapped with the lock overlay; swipe-to-unlike (delete the
`SavedAnalysis`, mirroring FolderContentsScreen). Unlocked tap → `loadSavedAnalysisWithSwiping`.

### 6. Premium gate (read-only)
- `final isPremium = ref.watch(subscriptionProvider).isSubscribed;`
- `final todayStart = DateTime(now.year, now.month, now.day);`
  `final cutoff = todayStart.subtract(const Duration(days: 6));`
  `final locked = !isPremium && analysis.createdAt.isBefore(cutoff);`
- Locked card: `ColorFiltered` dim + a lock icon + PREMIUM badge overlay; tap →
  `await requirePremiumGuard(context, ref)` (auth → paywall). Premium → all tappable.
- Liking is never capped; the gate is purely on opening older likes from this page.
- Locked items remain **visible** (greyed) so users see what premium unlocks.
- `requirePremiumGuard` is `kDebugMode`-bypassed; the lock *visual* keys off `isSubscribed`
  directly, so it still renders in debug. Verify the paywall sheet itself in profile/release.

### 7. Rename to "My Likes"
- Add `LibraryFolder.displayName => isLikedGames ? 'My Likes' : name`; use at the Library
  home `FolderCard`, the My Likes header, and any other folder-name surface.
- Flip the creation literal in `ensureLikedGamesFolder()` to `'My Likes'` for new users.
- No prod data migration; existing `'Liked Games'` rows display "My Likes" via the override.

### 8. Routing
`library_screen.dart`: when the tapped folder `isLikedGames`, push `MyLikesScreen` instead
of `FolderContentsScreen`.

## Decisions

- **Date-card bucketing = liked-at (`created_at`), not played-date.** Rationale: the 7-day
  lock and the date sections then share one axis (whole sections lock/unlock cleanly); the
  goal text ("favorited before the 1 week period") ties recency to favorited time;
  `created_at` is always present whereas played-date is often null for gamebase/TWIC games;
  "My Likes" reads as a timeline of when you liked. Reversible — only the grouping function
  changes if we later prefer played-date.
- **Navigation = `loadSavedAnalysisWithSwiping`** (saved-analysis path), not the favorites
  raw-game push, so variations/comments/board-flip are restored and no extra premium guard
  fires on the open itself (the My Likes lock owns gating).
- **Card mode only** for v1 (no board/grid view-mode toggle) to keep scope tight.

## Out of scope / non-goals

- No backfill of `TcCategory`/`IsOnline` onto existing likes (old likes' TC filter no-ops).
- No refactor of the favorites/countrymen date-grouping copies (only extract what My Likes needs).
- No server-side filtering of likes (the in-memory list is small; all filtering is client-side).
- No view-mode (board/grid) toggle in v1.

## Validation

- `flutter analyze` on touched files (canonical correctness check per CLAUDE.md).
- Unit test for the My Likes provider: filter application + liked-at grouping + 7-day lock
  boundary (today vs 6 days ago vs 8 days ago).
- Device/manual check (by the user) for: lock visual + paywall on tap, unlimited liking,
  rename label, filter parity, date sections.
