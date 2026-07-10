# ChessEver V2 — multi-repository implementation plan

Date: 2026-07-10
Status: Approved for execution

Primary requirements:

- [`docs/CHESSEVER_V2_MASTER_HANDOFF.md`](../../CHESSEVER_V2_MASTER_HANDOFF.md)
- [`docs/superpowers/specs/2026-07-10-my-space-design.md`](../specs/2026-07-10-my-space-design.md)

## 1. Outcome

Deliver one coherent ChessEver V2 experience across mobile, supporting services, and the
existing desktop preparation workspace:

- a full-screen mobile shell with For You, Events, Library, Discovery, and My Space;
- restrained floating Liquid Glass management controls with no sticky top regions;
- independently complete light and dark themes;
- a useful default My Space plus server-authorized premium personalization;
- accurate, quality-gated, interoperable Studies;
- mobile Miniatures parity with the working desktop implementation;
- a polished desktop Players preparation workspace that preserves the existing local
  multi-source tree-building behavior;
- tests, privacy boundaries, accessibility, failure states, and migration safety.

This plan implements the parent requirements; it does not replace them. When a detail is
not repeated here, the master handoff and approved My Space specification remain binding.

## 2. Repository map

| Repository | Responsibility in this program |
| --- | --- |
| `/Users/berkay/projects/chessever-frontend` | Flutter mobile shell, Liquid Glass system, light/dark themes, For You, Events, Library integration, Discovery, Studies client, Miniatures client, My Space, likes/progress, tests |
| `/Users/berkay/projects/chessever_frontend_desktop` | Existing working Miniatures reference and Players preparation/tree workspace |
| `/Users/berkay/projects/chessever_data_hub_monorepo` | Candidate ingestion/curation owner for Miniatures, Studies, and event data; read-only until ownership is proven |
| `/Users/berkay/projects/chessever_gamebase` | Candidate serving/canonical-data owner for Studies and Miniatures; API contracts and source identity |

No new repository is created unless the ownership audits prove that no existing repository
has the correct domain responsibility. Cancelled hosted-engine and opening-tree cloud work
is outside this plan.

## 3. Non-negotiable execution rules

1. Agents are not alone in any repository. They must preserve user changes, inspect the
   current status before editing, and never revert work they do not own.
2. Parallel workers receive disjoint write scopes. Cross-scope interface changes are
   proposed to the coordinator before editing shared files.
3. Mobile and desktop agents never run `flutter build` or `flutter run`. They validate with
   scoped `flutter analyze --no-pub` and relevant unit/widget tests. Runtime checks belong
   to the user.
4. Existing shared Liquid Glass primitives are reused and hardened, never copied into
   feature-local lookalikes.
5. No client-only RevenueCat value is trusted as the server authorization boundary for
   premium layout writes.
6. No source content is duplicated into My Space layout rows. Stable typed references are
   resolved through the owning feature repositories.
7. Studies do not ship on visual polish alone: legality, PGN/tree fidelity, attribution,
   quality, sharing, progress, and source-version behavior must pass the master gates.
8. Miniatures mobile behavior is compared against the working desktop baseline, not
   reimagined from screenshots.
9. No credentials, private account details, raw tokens, PGN content, private notes, or
   serialized layouts enter commits or logs.
10. No GitHub push, production migration, service restart, or production deployment is
    performed by a fleet worker. Those actions require an explicit coordinator checkpoint
    and user authority, including where a repository's normal workflow expects deployment.

## 4. Current mobile working-tree protection

The following mobile files contained pre-existing uncommitted changes when execution was
approved. They are reserved from fleet edits until the coordinator attributes and
reconciles them:

```text
lib/screens/board_editor/board_editor_screen.dart
lib/screens/calendar/calendar_event_detail_screen.dart
lib/screens/countryman_games_screen.dart
lib/screens/countrymen/countrymen_combined_games_screen.dart
lib/screens/favorites/player_games/favorites_combined_games_screen.dart
lib/screens/favorites/player_games/player_games_screen.dart
lib/screens/gamebase/gamebase_explorer_screen.dart
lib/screens/group_event/smart_event/smart_event_screen.dart
lib/screens/library/book_preview_screen.dart
lib/screens/library/folder_contents_screen.dart
lib/screens/library/gamebase_database_search_screen.dart
lib/screens/library/gamebase_player_games_screen.dart
lib/screens/library/pgn_import_preview_screen.dart
lib/screens/library/twic_contents_screen.dart
lib/screens/my_likes/my_likes_screen.dart
lib/screens/premium_games/premium_games_screen.dart
lib/screens/standings/score_card_screen.dart
lib/screens/tour_detail/team_tour/team_score_card_screen.dart
```

Explorers may read these files. Workers may edit one only after the coordinator verifies
the current diff and assigns that exact file exclusively.

## 5. Fleet topology

### Coordinator-owned critical path

The coordinator owns:

- requirements and contract reconciliation;
- shared navigation and cross-feature interface decisions;
- assignment of exact write scopes;
- review and integration of worker changes;
- conflict resolution around dirty files;
- final scoped analysis/tests and user device checklist;
- every checkpoint involving external state.

The coordinator does not duplicate delegated audits or implementations while they are in
flight.

### Wave 0 audit agents

Six read-only explorers run concurrently. Each reports exact files, types, routes, tables,
IDs, tests, gaps, and a proposed disjoint implementation slice.

#### A. Mobile V2 shell and My Space composition

Inspect the current mobile navigation, home state retention, auth/subscription providers,
Library/My Likes/favorite event/favorite player providers, routing, and existing design
system. Return the smallest tracer path and the exact shared files that only the
coordinator should own.

#### B. Studies service and Flutter contract

Inspect Gamebase, Data Hub, and mobile for all Study models, endpoints, ingestion jobs,
routes, source IDs, PGN handling, quality filters, bookmarks/progress, caching, sharing,
and tests. Determine the current canonical owner and identify the exact contract required
for the first legal Study rail/detail/chapter tracer.

#### C. Miniatures desktop-to-mobile parity

Trace the working desktop Miniatures experience end to end: source repository/provider,
filters, sorting, pagination, cards, errors, and game opening. Find the matching backend
and mobile code. Produce a parity matrix and a minimal set of disjoint mobile changes.

#### D. User state, Supabase, and premium authorization

Inspect migrations, Supabase clients, RLS conventions, user-data tables, subscription
state, server-side entitlement mirrors/functions, optimistic concurrency patterns, and
tests. Decide whether `user_my_space_layouts` is needed and provide the safe migration/RPC
and test plan without applying it.

#### E. Liquid Glass and light/dark modernization inventory

Inspect shared glass adapters, theme tokens, root wrappers, floating navigation/search,
page shells, and all remaining screens. Classify surfaces as complete, dirty/in progress,
or unmodernized. Identify one clean representative tracer surface and independent batches
that avoid the reserved dirty files.

#### F. Desktop Players preparation workspace

Inspect the current Players sidebar/workspace, ChessEver/Chess.com/Lichess imports,
identity mapping, dedupe/provenance, tree algorithms, transpositions, local-cache write
serialization, filters, layout, cancellation, and tests. Return contained improvements
that preserve domain and updater constraints.

### Wave 0 reconciliation gate

Before any production worker starts, the coordinator publishes a short reconciliation
record containing:

- canonical owner for every source and user-state entity;
- stable identifier and route contracts;
- authoritative premium verification path or explicit release blocker;
- exact file ownership map;
- tracer acceptance tests;
- dirty-file conflicts and resolutions;
- whether any backend edit would imply push/deployment obligations.

## 6. Wave 1 — foundations in parallel

Only slices proven independent by Wave 0 may start together.

### 1A. Shared mobile shell and semantic design system

Coordinator/shared worker scope:

- V2 navigation enum/routes and state retention;
- semantic color, surface, glass, elevation, radius, spacing, and motion tokens;
- separate light/dark definitions;
- edge-to-edge page inset contract around floating controls;
- shared loading/empty/error/locked/tombstone primitives;
- responsive bottom-navigation strategy for five destinations;
- accessibility and Reduce Motion support.

No feature-specific data loading belongs in this slice.

### 1B. My Space domain and local default layout

Mobile worker scope, preferably new files under `lib/screens/my_space/`:

- typed shelf descriptor and layout domain objects;
- schema-version parsing and validation;
- curated default layout;
- repository interface and fake/in-memory implementation for tests;
- independent shelf-state composition;
- account-scoped cache contract;
- unit tests.

This slice must compile without a production persistence mutation and cannot claim that
customization is saved until server authorization exists.

### 1C. Studies source/API hardening

Owning-backend worker scope determined by the audit:

- explicit DTOs and stable IDs;
- quality/status/attribution fields;
- legal chapter PGN or normalized tree contract;
- ETag/content-version behavior;
- bounded list/detail caching and typed errors;
- fixture and contract tests.

The first backend change remains local until the deployment checkpoint.

### 1D. Premium layout persistence

Owning user-data backend worker scope determined by the audit:

- layout table only if no canonical equivalent exists;
- RLS and least-privilege grants;
- server-authorized, revision-aware save/reset mutation;
- descriptor validation and size/count limits;
- forged-entitlement, cross-user, conflict, expiry, and deletion tests;
- generated/client contract if the repository uses one.

If authoritative premium verification is absent, this slice produces the verifier/bridge
design and keeps production writes disabled behind a typed capability.

### 1E. Miniatures parity adapter

Mobile worker scope:

- canonical mobile models/repository mapping to the proven source;
- desktop-equivalent filters, sorting, pagination, failures, and open-game behavior;
- fixture tests;
- no new source store.

### 1F. Desktop Players contained hardening

Desktop worker scope under `lib/desktop/` and existing tests:

- one or more audit-proven, phase-coherent improvements;
- preserve shared local-cache writer serialization;
- preserve global search shortcuts and forui chrome rules;
- no updater changes;
- scoped analysis/tests.

## 7. Wave 2 — tracer vertical

The first integrated vertical is:

```text
Discovery Study rail
  → quality/attribution-aware Study card
  → Study detail
  → legal chapter document/tree
  → Board/opening integration
  → bookmark and exact progress
  → Saved Studies shelf in My Space
  → canonical share
```

### Tracer requirements

- signed-out public reading path where allowed;
- signed-in bookmark/progress path;
- no-row My Space default path;
- free and premium behavior without client-trusted writes;
- content-version change reconciliation;
- removed/private Study tombstone;
- cold, warm, partial, offline, and retry states;
- light, dark, Dynamic Type, semantics, and Reduce Motion widget coverage;
- safe analytics without titles, PGN, notes, queries, tokens, or layout JSON;
- scoped analysis and tests clean.

No additional shelf or discovery family expands until this tracer works end to end in
code and the user receives exact runtime verification steps.

## 8. Wave 3 — breadth workstreams

After the tracer reconciles, run independent workers for:

### 3A. For You

- default V2 destination;
- Continue and smart event rails;
- quality Studies, Miniatures, notable games, and event rails;
- deduplication and recommendation explanations;
- useful signed-out/non-personalized fallback;
- private personalization reset/removal behavior.

### 3B. Events

- normalized live/upcoming/past identity and timezones;
- bookmarks and My Space integration;
- smart event rails based on explicit follows/bookmarks;
- source freshness and failure treatment;
- mobile edge-to-edge Liquid Glass modernization.

### 3C. Discovery and Miniatures

- Miniatures desktop parity;
- quality-gated Studies rails and search;
- My Likes/public-most-liked boundaries;
- useful free browse plus consistent premium filtering;
- canonical Board, Player, Event, Library, My Space, and Share actions.

### 3D. My Space breadth

- Continue, My Likes, Saved Events, databases/folders, Saved Studies/chapters, and Favorite
  Players default shelves;
- Add shelf catalog and pinned entities;
- premium add/remove/reorder/resize/reset;
- expiry freeze/renewal restore;
- optimistic conflict/offline behavior;
- per-shelf loading/empty/error/tombstone states;
- full light/dark/accessibility tests.

### 3E. Studies completeness

- editorial quality and accurate metadata;
- chapter/variation/comment fidelity;
- search/facets/pagination;
- source attribution and canonical sharing;
- immutable Library snapshot versus live bookmark semantics;
- Board, Opening Explorer/tree, Player, Event, Library, My Space, and progress integration;
- admin-only/coalesced source refresh and observability.

### 3F. Liquid Glass modernization batches

Modernize disjoint screen groups after shared primitives stabilize:

- root/navigation/global search;
- auth/profile/settings;
- Events and event detail;
- Library and import flows;
- Board/game/analysis flows;
- players/favorites/countrymen;
- Discovery/Studies/Miniatures;
- My Space;
- remaining sheets/dialogs/feedback.

Every page remains full-screen. Outer management controls float; content does not become a
stack of translucent cards. Each batch receives separate light and dark review criteria.

### 3G. Desktop Players completeness

- stable player identity and provenance;
- ChessEver/Chess.com/Lichess import/dedupe filters;
- correct transpositions and supporting-game lists;
- cancellation/progress for large local builds;
- usable tree/notation/game-list layout;
- keyboard navigation and global search preservation;
- benchmarks and regression tests without moving heavy compute to a cancelled cloud path.

## 9. Work assignment and integration protocol

Every worker prompt must include:

- exact repository and allowed files/directories;
- explicit statement that other agents and user edits coexist;
- prohibited files and shared interfaces;
- required tests and analysis command;
- instruction to list every changed file and unresolved dependency;
- instruction not to commit, push, deploy, run the app, or run a Flutter build unless the
  coordinator explicitly assigns that action under repository rules.

When a worker completes:

1. inspect its reported files and current diff;
2. reject scope leakage or copied abstractions;
3. run/check focused tests and static analysis;
4. reconcile interfaces before starting dependent workers;
5. close the agent to release fleet capacity;
6. commit one coherent integration chunk from the coordinator scope.

## 10. Validation matrix

| Layer | Required validation |
| --- | --- |
| Flutter domain/repository/provider | Unit tests for parsing, state transitions, failures, conflicts, cache/account isolation |
| Flutter UI | Widget/golden-style coverage where established for light/dark, empty/loading/error/locked/offline/tombstone, semantics, large text, Reduce Motion |
| Flutter static correctness | `flutter analyze --no-pub <touched paths>`; never build/run |
| Supabase/Postgres | Migration lint/dry run where supported, RLS cross-user tests, mutation authorization/conflict tests, rollback notes |
| Gamebase TypeScript | Repository-standard typecheck/lint/tests and OpenAPI/fixture consistency |
| Data Hub Python | Repository tests plus `python3 -m py_compile` for touched files; no production restart without checkpoint |
| Desktop Flutter | Scoped analyze/tests, keyboard reasoning, cache-writer regression coverage where touched; never build/run |
| Integration | Contract fixtures shared across backend/mobile, canonical ID/open/share paths, privacy-safe errors/analytics |

## 11. External-state checkpoints

The coordinator must stop and request explicit authority before:

- creating a new GitHub repository;
- pushing backend or desktop branches;
- applying a production migration;
- changing a production environment variable or secret reference;
- deploying/restarting Gamebase, Data Hub, Supabase, or Coolify services;
- publishing a mobile/desktop build;
- operating the user's browser/account for a consequential change.

Read-only inspection and local implementation/testing may continue while a checkpoint is
pending when it does not depend on the external action.

## 12. Completion definition

The program is complete only when:

- the master handoff acceptance gates pass;
- the My Space specification acceptance criteria pass;
- every supported entity opens the promised experience;
- Studies are accurate, legal, quality-gated, useful, shareable, and interoperable;
- Miniatures match the working desktop behavior on mobile;
- desktop Players preparation remains correct and is measurably more usable;
- full-screen Liquid Glass and independent light/dark treatment cover the agreed mobile
  surfaces without sticky top regions;
- static analysis and relevant automated tests pass;
- no private data or credentials entered source control;
- no unrelated user work was reverted;
- the user has a precise runtime test checklist and all remaining production actions are
  explicit rather than implied.
