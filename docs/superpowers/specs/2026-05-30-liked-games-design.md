# Liked Games v1 — Design Spec

**Status:** Approved for planning
**Date:** 2026-05-30
**Scope:** (1) a permanent, for-everybody `liked_games` Supabase store, and (2) the double-tap heart animation + toolbar heart. Nothing else — no leaderboards, like counts, notifications, sharing, or For-You content.

---

## 1. Goal & locked decisions

A user double-taps a game (board) to "like" it. The like is persisted per-user to Supabase and surfaced in a permanent **Library → Liked Games** collection that every user has automatically and cannot delete.

Decisions locked during brainstorming:

| # | Decision | Rationale |
|---|---|---|
| D1 | **All sources likeable** — flexible key `(source, game_id)`, `game_id` is `text`, **no FK** to `games`. | Games are multi-source; gamebase/TWIC ids live outside this DB so an FK is impossible. User chose maximum reach. |
| D2 | **Denormalized `jsonb` snapshot** of card-display fields stored on each like. | Library list renders with zero per-source refetch, offline-safe (Postgres read-heavy denormalization best practice). |
| D3 | **Burst = bespoke Flutter spring** (`SpringSimulation`+`SpringDescription`); **toolbar heart = `motor`** (`CupertinoMotion`). **`cue` dropped.** | User wanted full custom physics control; `motor` already in app, no new pre-release dep. |
| D4 | **"Liked Games" is a permanent, undeletable, for-everybody collection.** | The `liked_games` table + RLS gives every user their own likes with no per-user setup. UI entry is fixed/pinned, not user-removable. |
| D5 | **Likeable sources = `supabase`, `gamebase`, `twic` only.** Synthetic `GameSource`s (`openingExplorer`, `boardEditor`, `savedAnalysis`, `localAnalysis`) are **not** likeable — heart hidden. | Those are ephemeral/synthetic boards, not real persistable games. |
| D6 | **Likes are separate from the saved-analysis quota.** Liking does not count against `kFreeSavedGamesLimit`; likes are unlimited in v1. | A like is lightweight, distinct from "save analysis to folder". |
| D7 | **All new code logs through `AppLog`** (the colored logger from the separate logging project), tagged `LIKE`/`DB`. | Reference usage for the upcoming app-wide logging work. |

---

## 2. Architecture

Four isolated units, each independently testable:

1. **DB** — `public.liked_games` (migration) — source of truth.
2. **Data layer** — `LikedGameSnapshot` (model) + `LikedGamesRepository` (Supabase CRUD) + `likedGamesNotifierProvider` (Riverpod optimistic state).
3. **Like surfaces** — board double-tap overlay + chessboard toolbar heart, both calling `toggle()`.
4. **Library surface** — permanent synthetic "Liked Games" folder → `LikedGamesScreen`.

```
double-tap / toolbar heart
        │ toggle(GamesTourModel)
        ▼
likedGamesNotifierProvider ──optimistic──▶ UI (heart fill + burst)
        │ debounced write
        ▼
LikedGamesRepository ──▶ Supabase public.liked_games (RLS)
        ▲
LikedGamesScreen ◀── fetchAll() ◀── Library "Liked Games" (pinned, undeletable)
```

---

## 3. Database

**File:** `supabase/migrations/20260529220712_create_liked_games.sql` — ✅ **APPLIED to `chessever_main`** (version `20260529220712`). Verified: RLS on, PK/CHECK/FK/UNIQUE present, 3 `authenticated` policies with `(select auth.uid())`, index `(user_id, liked_at desc)`. Advisor `auth_allow_anonymous_sign_ins` matches all 28 existing per-user tables (house norm).

**Live-schema verification results:** `auth.users.id` = `uuid` ✓; `public.games.id` = `text` (so even broadcast ids are text → `game_id text` is correct universally); no prior `liked_games` table.

```sql
-- Per-user game likes across all real sources (broadcast/gamebase/twic).
-- Source-agnostic key (no FK to games: gamebase/twic ids live outside this DB).
-- A denormalized jsonb snapshot lets the Library "Liked Games" list render
-- without any per-source refetch.

create table if not exists public.liked_games (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references auth.users (id) on delete cascade,
  source    text not null check (source in ('supabase','gamebase','twic')),
  game_id   text not null,
  game_meta jsonb not null default '{}'::jsonb,   -- card snapshot (no PGN)
  liked_at  timestamptz not null default now(),
  unique (user_id, source, game_id)               -- idempotent like / unlike
);

-- Newest-first list for a user (covers the Library "Liked Games" query).
create index if not exists liked_games_user_recent_idx
  on public.liked_games (user_id, liked_at desc);

alter table public.liked_games enable row level security;

-- (select auth.uid()) → evaluated once per statement (initplan), not per row.
-- TO authenticated → policy never runs for the anon role.
create policy "liked_games_select_own" on public.liked_games
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "liked_games_insert_own" on public.liked_games
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "liked_games_delete_own" on public.liked_games
  for delete to authenticated using ((select auth.uid()) = user_id);
```

**"For everybody, undeletable":** the table + RLS *is* the per-user store — no per-user provisioning. Every signed-in user can insert/read/delete only their own rows the moment they sign up. There is deliberately **no** policy or UI path that lets a user drop the collection itself; "unlike" only deletes individual rows they own.

**Verified against live schema:** `auth.users(id)` is correct (real Google/Apple/email auth; anon is legacy and force-routed to sign-in). Migrations dir + timestamp naming confirmed.

---

## 4. Data layer

### 4.1 `LikedGameSnapshot` (`lib/repository/liked_games/models/liked_game_snapshot.dart`)
`GamesTourModel` has **no** `toJson` and nests `PlayerCard`, so a purpose-built snapshot is required.

- Fields (the subset `LibraryGameCard` renders): `gameId`, `source`, white/black `{name, title, rating, fed}`, `result`/status, `eco`, `openingName`, `tourId`, `roundId`, `tourName?`, `bucketDate` (ISO), `fen`. **No PGN** (reopening the board uses the existing per-source fetch-by-id).
- `LikedGameSnapshot.fromGamesTourModel(GamesTourModel)` + `toJson()`/`fromJson()`.
- `toGamesTourModel()` rebuilds a display-only `GamesTourModel` for the list card.

### 4.2 `LikedGamesRepository` (`lib/repository/liked_games/liked_games_repository.dart`)
Mirrors the `favorite_players` repo pattern (wraps `Supabase.instance.client`):
- `Future<void> like(LikedGameSnapshot s)` → upsert into `liked_games` with `onConflict: 'user_id,source,game_id'`, `ignoreDuplicates: true`. Idempotent.
- `Future<void> unlike(GameSource source, String gameId)` → delete matching `(user_id, source, game_id)`.
- `Future<List<LikedGameSnapshot>> fetchAll()` → select ordered `liked_at desc`.
- Throws if `currentUser == null` (matches existing favorites behavior).
- Logs via `AppLog.tag('DB')`.

`likedGamesRepositoryProvider = Provider(...)`.

### 4.3 `likedGamesNotifierProvider` (`lib/repository/liked_games/liked_games_provider.dart`)
`AsyncNotifier` holding the user's liked set (keyed `"$source:$gameId"`):
- `bool isLiked(GameSource, String gameId)`.
- `Future<void> toggle(GamesTourModel game)` — **optimistic**: flip in-memory set instantly (drives heart + burst), then write in background; **roll back** the in-memory flip if the write throws.
- **Debounce** per key (~400ms): rapid re-taps coalesce; only the final state is committed to Supabase.
- Clears on sign-out; hydrates on sign-in / first read.
- Logs via `AppLog.tag('LIKE')` (toggle intent, debounce-commit, rollback).

---

## 5. Like surfaces + collision

### 5.1 Toolbar heart (chessboard bottom nav)
- New heart button styled like `ChessSvgBottomNavbar`, added to the chessboard bottom nav row.
- Fill/unfill via **`motor`** `SingleMotionBuilder(motion: CupertinoMotion.smooth())` driving a 0→1 fill value (matches house style at `app_button.dart:138`).
- Reflects like state for the currently-open game at all times; tap = `toggle()`; light haptic on like only.
- Hidden when `source` is not in {`supabase`,`gamebase`,`twic`} (D5).

### 5.2 Board double-tap
- A translucent `GestureDetector(onDoubleTapDown:)` layered **over** chessground inside the inner board `Stack` (`chess_board_screen_new.dart:~7389`).
- `onDoubleTapDown` captures the local tap offset → the heart **spawns at the tap point** and fires on the **second tap-down** (zero perceived delay).
- `HitTestBehavior.translucent` so single taps still reach chessground (tap-to-move / scrub).

### 5.3 Collision strategy (the only real risk)
- The app has **zero** `onDoubleTap` today; the board's only gesture consumes *vertical drags* (flip). So no double-tap competitor exists.
- To avoid stealing the 2nd tap of a select→move sequence, double-tap-to-like is **armed only in view/scrub state** (no piece mid-selection / not in active move-input mode).
- **Flagged for on-device testing** — `flutter analyze` cannot validate gesture feel.

---

## 6. Heart-burst animation

A self-contained `HeartBurst` overlay widget (`lib/screens/chessboard/widgets/heart_burst.dart`). No `cue`.

- **Burst scale:** `AnimationController.animateWith(SpringSimulation(SpringDescription(mass, stiffness, damping), 0, 1, velocity))`. An **underdamped** (bouncy) spring animating 0→1 naturally overshoots ~1.2 then settles to 1.0 — the overshoot is physics, not a keyed value. Start tuning point: `mass: 1, stiffness: 500, damping: 18` (settles ~350ms); tuned on device.
- **Hold + drift-fade:** second controller — hold full opacity ~400ms, then fade + translate up ~12px over ~300ms (gentler spring/curve).
- **Unlike:** quieter, stiffer reverse (scale 1→0, fade ~250ms), **no** haptic.
- **Toolbar heart:** `motor` `CupertinoMotion.smooth()` (§5.1) — clean state spring, no burst.
- **Color:** `context.colors.danger` (the like-active token; dark `kRedColor`) — single source of truth, never a literal.
- **Haptic:** `HapticFeedbackService` light impact on **like only**.
- **Reduce motion:** `MediaQuery.disableAnimationsOf(context)` → skip burst/drift, 150ms opacity fill; the like still registers.
- The heart sits *over* the board and fades; it never obscures or replaces the position.

---

## 7. Library — permanent "Liked Games" collection

- A synthetic `kLikedGamesFolder` constant (mirrors `kLikedGamesBookId = '__liked__'`, like `kTwicFolder`), **pinned at the top** of the Library folder list, always present for every signed-in user.
- **Undeletable / immutable (D4):** rendered without any swipe-to-delete / rename / long-press-delete affordance; excluded from the free `kFreeBookCreationLimit` count.
- Tap → `LikedGamesScreen` (`lib/screens/library/liked_games_screen.dart`): reads `likedGamesNotifierProvider`, renders each snapshot through the existing `LibraryGameCard`, **newest-first**. Empty state when no likes.
- Tap a liked card → reopen the board via the existing per-source fetch (supabase `getGameByAnyId`, gamebase provider, twic) keyed by the stored `(source, game_id)`.
- Likes are **not** bound by `kFreeSavedGamesLimit` (D6).

---

## 8. Out of scope (per ticket)

No leaderboards, like counts, notifications, sharing, Entertainment/For-You content. No local SQLite mirror in v1 (Supabase + optimistic in-memory only). The app-wide colored-logging migration is a **separate project/spec**; this spec only *consumes* `AppLog`.

---

## 9. File manifest

**New**
- `supabase/migrations/20260530120000_create_liked_games.sql`
- `lib/repository/liked_games/models/liked_game_snapshot.dart`
- `lib/repository/liked_games/liked_games_repository.dart`
- `lib/repository/liked_games/liked_games_provider.dart`
- `lib/screens/chessboard/widgets/heart_burst.dart`
- `lib/screens/library/liked_games_screen.dart`

**Touched**
- `lib/screens/chessboard/chess_board_screen_new.dart` — double-tap overlay + burst host in the board `Stack`.
- chessboard bottom-nav row — add heart button.
- `lib/screens/library/library_screen.dart` + `lib/screens/library/providers/library_folders_provider.dart` — prepend pinned `kLikedGamesFolder`, route to `LikedGamesScreen`.
- (logger utility `AppLog` arrives via the separate logging project; until then, fall back to existing logging.)

---

## 10. Acceptance criteria (from ticket)

**Database**
- [x] `public.liked_games` with the columns (adapted: `source` + `text game_id` + `game_meta`).
- [x] Unique `(user_id, source, game_id)` → idempotent like/unlike.
- [x] Index `(user_id, liked_at desc)`.
- [x] RLS enabled; user selects/inserts/deletes only their own rows.
- [x] `game_id` type + (no-)FK confirmed against real multi-source schema.
- [x] User reference confirmed = `auth.users`.

**Animation** — implemented (✅ = code complete; device-verify motion feel)
- [x] Spring-physics-based (bespoke `SpringSimulation` + `motor`), not duration/curve easing.
- [x] Double-tap fires burst at tap point, no perceived latency.
- [x] Like inserts a row; unlike deletes it.
- [x] Unlike uses the quieter reverse animation.
- [x] Single light haptic on like, none on unlike.
- [x] Reduce-motion → simple fade; like still registers.
- [x] Rapid re-tap commits only the final state (debounce).
- [x] Optimistic UI, rolls back on write failure.
- [x] Liked games appear in Library → Liked Games, newest first.

**Device-verify (cannot be checked by `flutter analyze`):** double-tap vs tap-to-move
feel on the interactive board; spring `mass/stiffness/damping` tuning; burst placement
at the tap point across phone/tablet.

---

## 11. Risks / device-test items
- **Board double-tap vs. tap-to-move collision** (§5.3) — primary risk; must be verified on device.
- **Spring tuning** — `mass/stiffness/damping` values are starting points; finalize by feel on device.
- **Cross-source card rehydration** — snapshot must carry every field `LibraryGameCard` needs; verify against the card's required params during implementation.
