# My Space — premium shelf workspace design specification

Date: 2026-07-10
Status: Product direction approved; written specification awaiting final review
Parent brief: [`docs/CHESSEVER_V2_MASTER_HANDOFF.md`](../../CHESSEVER_V2_MASTER_HANDOFF.md)

## 1. Decision summary

My Space is ChessEver's personal home for content the user already cares about. It uses
a premium, Netflix-style shelf layout, but every card remains a direct chess action rather
than passive decoration.

The experience has two layers:

1. Every signed-in user receives a useful curated layout containing their real content.
2. Premium users can add, remove, reorder, and resize shelves and can pin individual
   entities such as an event, database, Study, chapter, or player.

Free users can open every item their current entitlement permits. They do not receive a
dead or fake preview page. The customization entry point remains visible so the value of
premium is understandable, but customization itself is protected by an authoritative
server-side entitlement check.

The page is full-screen and edge-to-edge. It has no sticky or permanently occupied top
area. Title, profile/avatar, search, filter, edit, add-shelf controls, and bottom navigation
float over the page as restrained Liquid Glass islands. Content cards and imagery remain
opaque and crisp. Light and dark modes are designed and verified independently.

## 2. Goals

- Make every supported personal entity visible, ready, and one tap away from use.
- Give new and free users a complete default workspace without requiring setup.
- Give premium users meaningful control without turning the page into a dashboard editor.
- Connect My Space to Studies, Miniatures, Events, Players, My Likes, Library, databases,
  folders, games, progress, and saved content through stable references.
- Resume Studies and other progress-bearing content at the best valid location.
- Persist customization across devices and restore it after premium renewal.
- Keep one failed data source from blanking or blocking the rest of the page.
- Preserve privacy boundaries: user state is private unless the user explicitly shares a
  public entity through its canonical sharing flow.
- Meet the V2 Liquid Glass, motion, accessibility, light-mode, and dark-mode standards.

## 3. Non-goals

- My Space does not replace global Discovery, Library management, or event browsing.
- It does not duplicate full Study PGN, database payloads, or game collections into its
  layout record.
- It does not publish a user's private layout, progress, bookmarks, tags, or interests.
- It does not make all premium source content free merely because its card appears here.
- It does not use glass styling for every card, row, or background surface.

## 4. Audience and entitlement behavior

### 4.1 Signed-out visitor

The My Space navigation destination may be visible, but opening it presents a polished
sign-in state explaining that saved items and progress synchronize across devices. It
must not show another user's cached data. A signed-out visitor can leave for Discovery,
Events, or other public destinations without encountering a paywall.

### 4.2 Signed-in free user

The free user receives the default layout and can:

- open supported free content immediately;
- use My Likes according to its existing free recency rules;
- resume content when that content and action are free;
- bookmark/unbookmark entities whose bookmark action is free;
- see honest locked treatment only where the underlying content is premium;
- inspect the shelf catalog preview and premium customization benefits.

The free user cannot persist a custom layout. Tapping Add shelf, reorder, resize, remove,
or edit enters the established premium flow. The page itself remains useful after the
flow is dismissed.

### 4.3 Signed-in premium user

The premium user can:

- add broad dynamic shelves;
- pin supported individual entities as dedicated shelves or featured cards;
- remove and reorder shelves;
- select a supported shelf size;
- restore the curated default layout;
- persist changes across devices with optimistic conflict handling.

### 4.4 Premium expiry and renewal

When premium expires, the last custom layout is retained but frozen:

- content in the saved layout remains readable/openable according to current content
  entitlements;
- edit, add, remove, resize, and reorder controls are disabled behind the premium flow;
- the stored custom layout is not deleted or replaced with defaults;
- renewal restores editability without reconstructing the layout.

This rule avoids holding a user's organization hostage while still preserving premium
customization as a clear benefit.

## 5. Information architecture

### 5.1 Default layout

The curated default is ordered as follows. Empty shelves remain compact and useful rather
than occupying a full empty rail.

| Order | Shelf | Primary content | Empty action |
| --- | --- | --- | --- |
| 1 | Continue | Current Study/chapter, game review, event, or Library activity with valid progress | Browse Studies |
| 2 | My Likes | Recently liked games, honoring existing access rules | Discover games |
| 3 | Saved Events | Bookmarked live, upcoming, and past events | Browse events |
| 4 | Databases | Recent and pinned user databases/folders | Import or open Library |
| 5 | Saved Studies | Bookmarked Studies and chapters | Browse quality Studies |
| 6 | Favorite Players | Followed players and direct preparation actions | Find players |

The product may add a server-supported Miniatures or recommended Studies shelf to the
default after its content quality and source contracts pass the master handoff gates. It
must not silently insert promotional rails between a user's personal shelves.

### 5.2 Shelf catalog

The Add shelf control opens a floating Liquid Glass sheet with search and grouped shelf
types. The catalog must distinguish dynamic collections from pinned entities.

Supported dynamic shelf types:

- Continue
- My Likes
- Saved Events
- Databases and folders
- Saved Studies and chapters
- Favorite Players
- Saved games or Library recents when a canonical source is available
- Miniatures after mobile parity is complete
- quality-gated Study discovery rails when editorial contracts are complete

Supported pinned entity types:

- Event
- Database or folder
- Study
- Study chapter
- Player
- Public or user-owned game when a stable canonical reference exists

The catalog excludes an already-present singleton shelf or explains why it cannot be
added again. Pinned entities may repeat only when their stable target identifiers differ.

### 5.3 Immediate actions

Every populated card has a clear primary action:

- Study: open the Study detail or resume the exact valid chapter/node.
- Study chapter: open that chapter and restore valid progress.
- Miniature/game: open the canonical game/Board experience.
- Event: open the event or its live games.
- Player: open the player workspace; expose preparation as a secondary action where
  supported.
- Database/folder: open its contents.
- My Like: open the saved analysis when permitted or show its existing premium rule.

Cards must not open an intermediary detail screen that adds no information or action.

## 6. Visual and interaction design

### 6.1 Page composition

The page uses a vertical feed of horizontal shelves:

- an edge-to-edge hero/continue area only when meaningful content exists;
- compact section title, optional context, count, and See all action;
- horizontally scrolling cards with intentional peek at the next card;
- stable card dimensions per shelf size to prevent scroll jumps;
- contextual empty rows that take less height than populated shelves;
- a final Add shelf tile for premium personalization.

The first useful content begins behind/under the floating chrome with safe-area padding,
not below a fixed app bar. Scroll position and shelf horizontal positions survive tab
switches within the current session.

### 6.2 Liquid Glass rules

Glass is reserved for outer management controls:

- floating title/back island when navigation context requires it;
- avatar/profile control;
- search, filter, and catalog controls;
- edit/done/reorder controls;
- floating bottom navigation;
- temporary sheets, confirmations, and contextual control clusters.

Glass is not used for:

- every content card;
- text-heavy Study metadata;
- chessboard imagery;
- nested containers inside other glass containers;
- permanent full-width top bars.

The fallback renderer must preserve hierarchy and readability on devices where the full
glass effect is unavailable or reduced.

### 6.3 Light and dark modes

Light and dark modes use separate semantic tokens and are reviewed separately. Neither is
derived by a simple color inversion.

- Light mode uses calm warm/cool neutral page surfaces, readable dark text, crisp opaque
  content cards, restrained shadows, and glass edges visible against light imagery.
- Dark mode avoids pure black-on-neon styling, muddy translucent stacks, and low-contrast
  secondary text. Content cards remain distinguishable from the page.
- Cyan remains an action/state accent, not a general decoration color.
- All thumbnails require a deterministic placeholder, contrast-safe scrim where text
  overlays imagery, and no layout change when the image arrives.

### 6.4 Motion and feedback

- Shelf insertion/removal/reorder uses short, spatially understandable motion, generally
  150–250 ms.
- Press feedback begins immediately and does not delay navigation.
- Optimistic layout changes visibly settle or roll back with an explanation.
- Loading uses shelf-shaped skeletons rather than global spinners.
- Reduce Motion removes decorative movement and uses fades/state changes.
- Haptics are limited to meaningful edit, drop, and save events where platform conventions
  support them.

### 6.5 Accessibility

- Interactive targets meet platform touch-size guidance.
- Every card exposes entity type, title, relevant status, and primary action to assistive
  technology.
- Locked state, live state, progress, and selected/editing state are not color-only.
- Reordering has accessible move-before/move-after alternatives; drag is never the only
  mechanism.
- Dynamic type does not clip titles or hide primary actions.
- Horizontal rails remain navigable with switch/keyboard traversal where supported.

## 7. Data model

### 7.1 Ownership

My Space stores authenticated user state in ChessEver's existing user-data Supabase
domain. It references, but does not own, source entities:

- Studies and Study chapter source content: Gamebase, with ingestion/curation possibly in
  `chessever_data_hub_monorepo` and serving contracts in `chessever_gamebase`;
- Miniatures: existing working desktop source, with underlying services expected in
  `chessever_data_hub_monorepo` or `chessever_gamebase`;
- Events: existing event/data-hub contracts;
- My Likes and Library entities: existing user folders/saved analyses/library contracts;
- Favorite players: existing user favorite-player records.

The implementation begins with a read-only ownership audit. It must reuse canonical IDs
and current tables/providers rather than create parallel bookmark or favorite systems.

### 7.2 Layout table

Create one row per user in `user_my_space_layouts` only after the backend ownership audit
confirms no equivalent canonical store exists.

Required logical fields:

| Field | Type | Rule |
| --- | --- | --- |
| `user_id` | UUID primary key | References `auth.users(id)` with cascade delete |
| `schema_version` | integer | Positive, starts at 1 |
| `revision` | bigint | Monotonic optimistic-concurrency token |
| `shelves` | JSONB | Ordered validated shelf descriptors only |
| `created_at` | timestamptz | Server generated |
| `updated_at` | timestamptz | Server generated on every accepted write |

The record contains layout references and presentation choices only. It does not cache
titles, thumbnails, PGN, event payloads, private notes, game arrays, or Study documents.

### 7.3 Shelf descriptor contract

Version 1 descriptors use a closed typed contract equivalent to:

```json
{
  "id": "01J...client-generated-stable-id",
  "type": "saved_studies",
  "targetId": null,
  "size": "standard",
  "visible": true
}
```

Allowed `type` values for version 1:

```text
continue
my_likes
saved_events
databases
saved_studies
favorite_players
library_recents
miniatures
study_discovery
pinned_event
pinned_database
pinned_folder
pinned_study
pinned_study_chapter
pinned_player
pinned_game
```

Allowed `size` values are `compact`, `standard`, and `featured`. Not every type must
support every size; unsupported combinations are rejected rather than silently changed.
`targetId` is required for every `pinned_*` type and forbidden for dynamic types. Stable
IDs must be canonical IDs from the source domain, never display names or mutable URLs.

Server validation enforces:

- supported schema version;
- maximum shelf count and serialized payload size;
- unique descriptor IDs;
- valid type/target/size combinations;
- singleton rules for dynamic shelf types;
- no unknown keys that could become a hidden data store;
- no cross-user private target reference where source authorization can be checked.

### 7.4 Defaults and migration

Users without a layout row receive the curated default in application/domain code. A row
is created only on the first authorized customization, keeping default evolution simple.

When `schema_version` changes, a deterministic migrator:

- preserves known shelf IDs, order, and supported sizes;
- converts renamed types explicitly;
- tombstones or omits removed unsupported types with a user-visible explanation;
- never discards the last saved document before the replacement validates;
- retains a safe reset-to-default path.

## 8. Authorization and premium enforcement

### 8.1 Row-level security

RLS is enabled for every user layout table. The authenticated user may select only the
row where `user_id = auth.uid()`. Anonymous users have no access. Administrative access
uses existing controlled operational paths, never a client-shipped service key.

Direct client insert/update/delete grants are not the premium boundary. Layout writes go
through one versioned mutation/RPC that:

1. derives the user from `auth.uid()`;
2. checks an authoritative server-side premium entitlement;
3. validates the complete descriptor document;
4. compares the supplied expected revision;
5. atomically writes and increments revision;
6. returns the accepted normalized document and new revision.

The function uses a fixed search path and least privilege. Conflicts return a typed result
that lets the client reload and offer retry, not a generic success or silent overwrite.

### 8.2 Entitlement prerequisite

The repository audit must locate the production-authoritative premium entitlement mirror
or verifier before customization writes ship. RevenueCat state read only from the Flutter
client is insufficient because it can be forged.

If no server-verifiable entitlement source currently exists, the customization mutation
remains disabled in production until an entitlement synchronization path and reconciliation
tests exist. This is a release gate, not permission to trust a client boolean temporarily.

## 9. Client architecture

### 9.1 Domain types

Create typed domain objects rather than passing JSON through widgets:

- `MySpaceLayout`
- `MySpaceShelfDescriptor`
- `MySpaceShelfType`
- `MySpaceShelfSize`
- `MySpaceShelfState<T>`
- `MySpaceEntitlement`
- `MySpaceLayoutConflict`
- typed target references for pinned entities

Unknown future shelf types deserialize into an explicit unsupported/tombstone state. They
must not crash the whole layout or be silently saved back as another type.

### 9.2 Repository boundary

One repository owns layout transport and persistence:

- load the current layout/revision;
- return the default when no row exists;
- validate local edits before mutation;
- save with expected revision;
- reset to default through the authorized mutation;
- expose typed authorization/conflict/network errors;
- cache only the current authenticated user's layout with account-scoped keys;
- erase account-scoped cached layout on sign-out.

Entity repositories remain responsible for resolving shelf contents. My Space does not
become a second API client for Studies, Events, Library, players, or games.

### 9.3 Riverpod composition

Follow the repository's current Riverpod conventions. A layout notifier coordinates edit
operations and optimistic saves. Independent shelf providers resolve content by typed
descriptor and use `autoDispose`/family behavior only where consistent with existing code.

Required behavior:

- one shelf error does not fail the page;
- layout load and shelf data load are independent;
- providers watch only the state slices they render;
- optimistic reorder/resize/add/remove rolls back on rejected writes;
- a newer remote revision invalidates stale local edits;
- rapid reorder operations are coalesced or serialized;
- disposed searches/loads do not update current state;
- free users never invoke an unauthorized save mutation.

### 9.4 Suggested feature boundary

Use a cohesive feature module, adapted to established project naming:

```text
lib/screens/my_space/
  domain/
  providers/
  repository/
  widgets/
  my_space_screen.dart
```

Shared Liquid Glass primitives stay in the existing shared design-system location. Do not
fork local glass implementations inside My Space.

## 10. Entity-source behavior

### 10.1 Continue

Continue chooses resumable user activity through explicit timestamps and capability
rules, not a random recommendation. For a Study it stores/retrieves Study ID, chapter ID,
content version, node/ply, completion state, and last activity. If a version changes, the
Studies reconciliation contract attempts a safe mapping and otherwise opens the chapter
at its valid start with an explanation.

### 10.2 Studies

Only quality-gated, usable Studies may appear in discovery-derived shelves. Saved Studies
can show content the user explicitly saved, but removed/private/unavailable source content
must use a graceful tombstone. Study cards expose source attribution and open into legal,
tested chapter navigation. Bookmark, progress, Board, Opening Explorer, Player, Event,
Library snapshot, and canonical share interoperability follow the parent handoff.

### 10.3 Miniatures

The desktop implementation in `projects/chessever_frontend_desktop` is the behavioral
baseline and is already working. Mobile uses the same canonical source/filter/open
semantics after auditing the owning service in `projects/chessever_data_hub_monorepo` or
`projects/chessever_gamebase`. My Space does not ship a separate Miniatures data model.

### 10.4 Events

Saved Events use canonical normalized event identity. Live/upcoming/past status is derived
from event data with explicit timezone rules. A stale source update remains visible as a
stale/error state rather than silently turning a live event into an unrelated card.

### 10.5 Players

Favorite-player cards use stable player IDs and preserve source provenance. A card never
merges players by display name alone. Mobile opens the supported player experience; the
desktop preparation workspace remains the full multi-source tree-building baseline.

### 10.6 Library, databases, My Likes, and games

Reuse `user_folders`, `user_saved_analyses`, Library repositories, and current My Likes
providers. A pinned private entity is visible only to its owner. Game references must use
the canonical game/saved-analysis identity appropriate to their source. Deleted records
become a removable tombstone instead of breaking the shelf.

## 11. Empty, loading, error, and offline states

Every shelf defines all states explicitly:

- **Loading:** correctly sized skeleton cards; no page-wide spinner.
- **Empty:** short explanation plus one real contextual action.
- **Partial:** usable items render while a non-blocking status explains missing data.
- **Error:** retry is scoped to that shelf; other shelves keep working.
- **Unauthorized:** sign-in or entitlement action appropriate to the entity.
- **Removed:** tombstone with source-safe wording and Remove from My Space.
- **Offline with cache:** last known content is marked as cached when freshness matters.
- **Offline without cache:** shelf-level offline state and retry.

The default layout remains available offline. Cached content and layout are isolated by
user ID and cleared on sign-out. Mutating layout offline is either explicitly queued with
revision-aware reconciliation or disabled with clear feedback; it is never presented as
saved when no durable queue exists.

## 12. Sharing and privacy

Sharing belongs to the referenced entity, not to the private My Space layout:

- public Study/Event/game/player cards can invoke their canonical share route;
- private databases, folders, notes, progress, shelf ordering, and recommendations are not
  embedded in share links;
- a saved immutable Study snapshot follows Library sharing/privacy rules, distinct from a
  live Study bookmark;
- removed/private targets do not expose source URLs, IDs, or authorization details in
  error text;
- analytics record shelf type and interaction, not private titles, PGN, notes, queries, or
  raw layout JSON.

## 13. Analytics and observability

Use the project's established analytics abstraction and safe operational logging.

Minimum product events:

- My Space viewed with signed-in/free/premium state;
- shelf impression by type and position;
- entity opened by shelf type and action;
- empty action selected;
- catalog opened and shelf type selected;
- edit mode entered/exited;
- add/remove/reorder/resize/reset attempted and accepted/rejected;
- premium flow shown from a customization action;
- layout conflict, shelf load failure, and tombstone shown.

Do not log target titles, private IDs where avoidable, Study progress payloads, search text,
or serialized shelf documents. Operational logs use request/correlation IDs and typed
error categories.

## 14. Validation strategy

### 14.1 Automated tests

Required before release:

- descriptor parsing/validation and schema migration tests;
- default-layout construction tests;
- duplicate/singleton/target/size rule tests;
- repository no-row/default, successful save, revision conflict, unauthorized, and
  malformed-response tests;
- layout notifier optimistic success/rollback/coalescing tests;
- independent shelf loading and partial failure tests;
- sign-out cache isolation tests;
- premium-expiry freeze and renewal restoration tests;
- RLS tests proving cross-user select/write denial;
- mutation tests proving free/forged-client writes fail server-side;
- source authorization tests for pinned private targets;
- widget tests for default, empty, loading, error, offline, tombstone, free, premium,
  light, dark, Dynamic Type, and Reduce Motion states;
- semantics tests for card actions and accessible reorder controls.

Per repository rules, Flutter validation uses scoped `flutter analyze --no-pub` and relevant
unit/widget tests. Agents must never run `flutter build` or `flutter run`.

### 14.2 User device checks

The user verifies runtime/on-screen behavior on representative small and large phones:

- no fixed/sticky top region;
- first and last content remain reachable around floating controls;
- bottom navigation does not cover shelf actions;
- horizontal and vertical gestures do not fight each other;
- populated cards open the promised destination in one tap;
- edit/reorder is smooth and persists after relaunch and on another device;
- free customization attempts show the correct premium flow without breaking browsing;
- light and dark modes look intentionally designed on image-heavy and empty states;
- Reduce Motion and larger text remain usable;
- network loss and recovery do not lose or falsely confirm layout changes.

## 15. Acceptance criteria

My Space is complete only when all of the following are true:

1. It is a real V2 bottom-navigation destination and never uses a fixed top app bar.
2. Every signed-in user receives the useful curated default layout.
3. Every populated card has a direct, working primary action.
4. Empty shelves have a contextual creation/discovery action.
5. Premium users can add, remove, reorder, resize, reset, and persist shelves.
6. Free users retain a useful page and cannot forge layout writes.
7. Premium expiry freezes rather than deletes customization; renewal restores it.
8. Shelf failures are isolated and retryable.
9. Study progress/bookmarks, Events, Players, Library, databases, My Likes, and supported
   Miniatures use canonical identities and existing owning services.
10. Study content shown through My Space meets the quality/interoperability gates in the
    master handoff.
11. Private user state never enters public discovery, sharing payloads, or unsafe logs.
12. Layout and content caches cannot leak across accounts.
13. Light mode, dark mode, Dynamic Type, semantics, Reduce Motion, and accessible reorder
    controls pass their tests and user checks.
14. Scoped static analysis and relevant automated tests pass without running the app or a
    Flutter build.

## 16. Delivery sequence and fleet boundaries

The implementation uses a tracer-first fleet. Agents work in parallel only on disjoint
files/contracts and must not revert other agents' or the user's existing work.

### Wave 0 — read-only audits

- locate the authoritative user-data backend and any existing My Space/layout store;
- locate the authoritative premium entitlement source and server verification path;
- map existing providers/routes for My Likes, Events, Library, databases, Studies,
  Miniatures, and favorite players;
- record exact canonical IDs and missing contracts;
- audit shared Liquid Glass primitives and V2 navigation constraints.

### Wave 1 — vertical tracer

Ship one complete path:

```text
Saved Study shelf
  → Study card
  → Study/chapter open
  → progress/bookmark update
  → My Space refresh
  → canonical share
```

This proves source identity, user state, navigation, layout, auth, error handling, and the
visual system before breadth work begins.

### Wave 2 — independent shelves and personalization

After tracer contracts are reconciled:

- one agent owns layout persistence/mutation/RLS tests;
- one owns My Space domain/repository/provider composition;
- one owns the full-screen shell, rails, edit/catalog UI, and responsive glass behavior;
- source-domain agents own adapters inside their existing feature boundaries;
- test agents add cross-source integration and accessibility coverage without rewriting
  production ownership.

### Wave 3 — breadth and polish

- add the remaining default and catalog shelf types;
- complete Miniatures mobile parity and Studies quality integration;
- complete free/premium states, expiry behavior, offline states, and conflicts;
- audit every My Space state separately in light and dark mode;
- run scoped static analysis/tests and hand exact runtime checks to the user.

No fleet agent may invent a second content store, trust a client-only premium flag, run
`flutter build`/`flutter run`, or overwrite unrelated dirty files.
