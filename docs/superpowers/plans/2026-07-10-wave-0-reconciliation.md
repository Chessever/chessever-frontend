# ChessEver V2 — Wave 0 reconciliation record

Date: 2026-07-10
Status: Wave 0 reconciled; implementation underway

Authority:

- [`docs/CHESSEVER_V2_MASTER_HANDOFF.md`](../../CHESSEVER_V2_MASTER_HANDOFF.md)
- [`docs/superpowers/specs/2026-07-10-my-space-design.md`](../specs/2026-07-10-my-space-design.md)
- [`docs/superpowers/plans/2026-07-10-chessever-v2-implementation-plan.md`](2026-07-10-chessever-v2-implementation-plan.md)

This record captures the immutable starting point and will receive the reconciled ownership
and contract decisions from the parallel Wave 0 audits before production workers begin.

## Repository baselines

| Repository | Starting commit | Starting worktree |
| --- | --- | --- |
| `chessever-frontend` | `363bf9f932f51a62f253465604253a5ab9616b67` | 18 pre-existing modified screen files, all reserved in the execution plan |
| `chessever_frontend_desktop` | `0cabd1e438b525b161de9617ed424169b13a1a23` | clean |
| `chessever_data_hub_monorepo` | `866d8cc197f3cb5f568496452d61488457a784ef` | clean |
| `chessever_gamebase` | `77138641140f34a131edbafbb1c19351eff57be6` | clean |

The 18 mobile files are fingerprinted by their starting Git blob IDs and line deltas in
the coordinator session. No worker may edit them until the coordinator assigns an exact
file after reviewing its existing diff.

## Static-analysis baseline

The untouched mobile repository reports 389 findings under whole-repository
`flutter analyze --no-pub`. The failures include pre-existing patrol/library test API drift
and vendored `third_party/chessground` example/test dependency failures. Whole-repository
analysis is therefore not a useful pass/fail signal for V2 slices.

The 18 reserved modified screens report no analyzer errors and eight warnings:

- one unused import in `countryman_games_screen.dart`;
- two unused private declarations and one unused optional parameter across the Gamebase
  explorer and smart-event screen;
- one unused local in `book_preview_screen.dart`;
- one unused theme import in `pgn_import_preview_screen.dart`;
- one unused private declaration and one unused local in `score_card_screen.dart`.

Workers must use scoped `flutter analyze --no-pub <touched paths>` plus relevant tests and
must not absorb unrelated baseline cleanup into their feature slices.

## Active audit assignments

The first fleet consists of six independent read-only audits:

1. mobile V2 shell and My Space composition;
2. Studies service and Flutter contract;
3. Miniatures desktop-to-mobile parity;
4. Supabase user state and premium authorization;
5. Liquid Glass and independent light/dark coverage;
6. desktop Players preparation workspace.

No audit agent had permission to edit, stage, commit, push, deploy, migrate, restart, run a
Flutter app, or run a Flutter build. Production worker scopes are issued only from the
reconciled decisions in this record.

## Mobile shell and My Space findings

The current mobile shell has three destinations only:

- `BottomNavBarItem` in `lib/screens/home/widget/bottom_nav_bar.dart` contains tournaments,
  calendar, and Library;
- `BottomNavBarView._buildScreen` in `lib/screens/home/home_screen.dart` builds only the
  selected child, so tab switches dispose local screen state;
- the existing For You experience is an Events subcategory, not a V2 destination;
- no Discovery, Study, or My Space route/provider/repository currently exists.

Existing canonical sources for the initial My Space shelves are:

| Shelf | Existing source | Important limitation |
| --- | --- | --- |
| Continue | `libraryAnalysesProvider` plus `SavedAnalysis.lastOpenedAt`, `lastViewedPosition`, and move pointer | Library analyses only; no Study/event progress |
| My Likes | `likedGamesProvider`, `likedGamesFolderProvider`, and `LibraryRepository` | Shelf must not inherit temporary filters from the My Likes screen provider |
| Saved Events | `favoriteEventsProvider` and `user_favorite_events` | Event source/category identity is not sufficient for every saved event to resolve reliably |
| Databases/folders | `combinedLibraryFoldersProvider` and `LibraryRepository` | No pinned flag; needs a feature adapter rather than a second store |
| Saved Studies | None | Requires the Study user-state contract |
| Favorite Players | `favoritePlayersProviderNew` and `user_favorite_players` | Optional FIDE ID and name fallback are insufficient for every canonical pinned-player reference |

The Library `SavedAnalysis` model is an owned chess-tree snapshot. The local
`ChessGameNavigatorStateManager` stores unscoped game JSON. Neither is a valid substitute
for live Study bookmark/progress state with user, Study, chapter, content-version, and
node/ply identity.

### Reconciled mobile decisions

1. The coordinator owns the five-destination shell changes in `lib/screens/home/`,
   including a lazy retained destination stack and responsive phone/tablet navigation.
2. A worker may create the typed My Space domain, curated default layout, independent
   shelf states, and tests under new `lib/screens/my_space/` files without claiming remote
   persistence.
3. A read-only Study rail/detail/chapter slice may start after the Study API audit. Real
   bookmark/progress starts only after its user-state contract is frozen.
4. My Space adapters reuse the existing likes, event, player, and Library sources; they do
   not create parallel tables or repositories for those entities.
5. Account-switch invalidation must cover likes, Library, Study state, and My Space caches,
   extending the current favorite event/player invalidation behavior.
6. Saved Events and pinned Players remain capability-limited until stable canonical source
   identity is available.
7. The tracer avoids all 18 reserved dirty screens. Board/Opening Explorer callbacks and
   dirty event/Library destination edits remain coordinator-owned follow-up work.

## Liquid Glass and theme findings

The package bootstrap, root renderer wrapper, separate theme objects, and floating home
bottom navigation already exist. The shared system is nevertheless not V2-complete:

- `ScreenWrapper`/`GlassPage` has no reusable full-screen opaque-content plus floating-
  overlay contract, which caused repeated private top-bar composition;
- custom glass/navigation motion does not honor Reduce Motion;
- back, avatar, and collapsed-search controls default to 40-point hit regions, below the
  required 44-point minimum, and scroll chrome can shrink them further;
- the 11-point inactive navigation labels do not meet text contrast in light mode and are
  also too faint in dark mode;
- several reserved dirty screens still contain pinned opaque search delegates, fixed
  `Column`/`SafeArea` header bands, full-width gradients, or a Scaffold app-bar slot.

### Reconciled design-system decisions

1. The coordinator first implements a shared full-screen page primitive and proves it on
   the currently clean Global Search surface.
2. Opaque content fills the viewport through `Positioned.fill`; glass controls occupy
   safe-area-aware overlay slots and never reserve a permanent top band.
3. Shared controls maintain at least 44-by-44 interaction/semantics bounds even when their
   visual treatment contracts during scroll.
4. Custom animations switch to immediate state or a simple crossfade when
   `MediaQuery.disableAnimations` is true.
5. Light/dark inactive text and control tokens receive contrast-safe values rather than a
   shared dark-first constant.
6. Root theme, `ScreenWrapper`, `lib/widgets/liquid_glass/`, search primitives, and the home
   shell remain coordinator-owned until the proof API and tests are stable.
7. Clean follow-up batches are Home tabs, Player Profile, Tournament/Countrymen, and
   Chessboard. The 18 reserved conversions are not considered complete and will be
   reconciled against the settled primitive separately.

## Desktop Players findings

The desktop Players workspace already imports ChessEver, Lichess, and Chess.com data,
deduplicates source and combined PGN, records provenance, builds cached opening trees,
indexes supporting games, and routes cache writes through the shared serialized writer.
Download/import cancellation and phase progress exist.

Two correctness gaps are now proven:

1. canonical account ownership is enforced only within the selected workspace, allowing
   the same FIDE/ChessEver identity or online account to be attached to multiple players;
2. local tree position keys retain only board placement and side-to-move, so positions
   with different castling or en-passant rights are falsely merged along with their
   supporting-game rows.

Combined PGN isolate preparation and local tree rebuilding also lack true cancellation.

### Reconciled desktop decisions

1. Implement canonical player/account ownership first inside the Players state/pane and
   focused tests; duplicate additions select the existing workspace and cross-player
   online-account attachment is rejected clearly.
2. Implement legal transposition identity in a separate reserved slice using the first
   four FEN fields, backward-compatible lookup for old compact snapshots, and tree-only
   cache invalidation through the existing write queue.
3. Prove that true move-order transpositions still merge while castling/en-passant variants
   and their supporting games remain separate.
4. Keep shell shortcuts, sidebar/routes, updater code, and global search outside Players
   workers. The existing global-search chord differs from the documented requirement and
   needs a coordinator-owned decision.
5. Preserve forui chrome and never open a new same-file database writer.

## User state and premium findings

Supabase is the canonical authenticated user-data owner. Existing folders, saved analyses,
favorite events, and favorite players use `user_id` references to `auth.users` with
owner-scoped RLS. No My Space layout or Study progress table/RPC currently exists;
`user_folders.order_index` is folder ordering and must not be repurposed.

A server-side premium authority does exist:

- webhook-owned `public.subscriptions` and `public.user_premium_view` are created by the
  unified subscription migrations;
- a later migration adds bounded past-due grace;
- the Flutter client can call a backend entitlement function.

The authority has two release caveats:

1. the entitlement Edge Function source exists in a desktop sibling repository but is
   absent from this mobile repository's Supabase function tree, so deployment ownership is
   split;
2. both the client shortcut and server synchronization accept any active RevenueCat
   entitlement rather than an explicitly approved ChessEver premium entitlement ID.

### Reconciled persistence decisions

1. Create a dedicated `user_my_space_layouts` table only; do not add generic Study progress
   JSON until the Studies audit freezes its identity and reconciliation fields.
2. Layout rows use the approved `schema_version`, `revision`, ordered `shelves` descriptors,
   and timestamps. Source titles, thumbnails, PGN, and private notes never enter the row.
3. Authenticated clients may select their own row. Direct insert/update/delete is not the
   premium boundary and remains unavailable; versioned save/reset RPCs derive ownership
   from `auth.uid()`, validate the document, check `user_premium_view`, and compare revision
   atomically.
4. Tests must prove cross-user denial, forged-owner/anonymous/direct-write denial, exactly
   one winner for competing revisions, and safe premium expiry/renewal behavior.
5. Local migration/client work may proceed without applying it. Production migration and
   entitlement deployment require an explicit external-state checkpoint and reconciliation
   of the canonical function source and entitlement ID policy.

## Studies findings

Gamebase is the canonical Study owner. It schedules and executes Lichess Study sync,
persists `LichessStudy`/`LichessStudyChapter`, and serves:

- Study list with typed filters and pagination;
- facets;
- Study detail;
- raw chapter PGN;
- a privileged refresh enqueue operation.

Data Hub contains only Lichess API snapshots and has no Study implementation. Mobile has no
Study models, repository methods, providers, routes, screens, bookmarks, progress, or
sharing today.

Gamebase already records views, chapter/ply counts, annotations, credibility/gate status,
ECO/opening/variant/mode/player metadata, and cached PGN with comments/variations. It does
not yet provide:

- explicit source URL and rights/license provenance;
- a stable chapter content hash/version;
- a normalized parsed chapter tree;
- stable fallback chapter identity independent of chapter order;
- Study-specific bookmarks/progress/sharing.

### Reconciled Studies decisions

1. Gamebase remains the sole ingestion/serving owner; no Study service or repository is
   created in Data Hub.
2. The first mobile slice may list quality-gated Studies and show attributed detail using
   the existing metadata contract.
3. Until redistribution rights are explicitly recorded and approved, chapter actions open
   the canonical `lichess.org/study/{studyId}/{chapterId}` source rather than serving the
   mirrored PGN inside ChessEver.
4. Gamebase follow-up adds source URL, rights basis/version, stable content hash, and tests
   before in-app chapter PGN/tree rendering is enabled.
5. Study progress/bookmark storage waits for stable Study/chapter/content-version identity;
   internal UUIDs recreated during sync and order-derived fallback IDs are not accepted as
   durable user-state references.
6. Refresh remains operations-only. Mobile pull-to-refresh re-fetches list/detail and never
   calls the sync route.

## Miniatures findings

Gamebase is also the canonical Miniatures owner. The working desktop flow calls
`GET /api/miniatures` through the Gamebase proxy, then maps results into date-grouped cards
and table rows with offset pagination, search, result/opening/time-control/online/rating/
move/date/player filters, and deterministic sorting.

Mobile has generic cards and pagination infrastructure but no Miniatures DTO, repository
method, provider, entry point, specialized filters, or verified full-game open path.

One contract defect is proven in repository source: the desktop DTO expects flat
`items/total`, while Gamebase returns `{status, data: {items, total, ...}}` and the proxy
passes the envelope through. The existing desktop path can therefore parse an empty page
unless deployed code differs. The mapped card also carries header-only PGN and the traced
hydration path does not hydrate Gamebase sources before Board open.

### Reconciled Miniatures decisions

1. Add the mobile Gamebase Miniatures DTO/filter/page method first, decoding the canonical
   nested envelope and accepting the historical flat shape without silently treating a
   malformed response as an empty success.
2. Preserve stable Gamebase game identity and enough source metadata for a later verified
   full-PGN hydration path.
3. Build provider/filter/UI parity after the repository contract lands. The current dirty
   `premium_games_screen.dart` remains reserved during the data slice.
4. Add a desktop regression test for the nested envelope and repair full-game hydration in
   a separate desktop-owned slice.
5. Do not create a second Miniatures store or backend route.
