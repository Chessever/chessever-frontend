# Collections navigation and author photos

This implementation targets the production flavor. It does not change flavor
selection, endpoints, credentials, Stockfish behavior or publication permissions.
Gamebase was deployed to production on 2026-09-30 with the user's explicit
authorization. Production verification used read-only queries. No schema or
book data changes were required. Mobile and web changes remain local.

## Behavior

- Player cards push a separate book/player Games route. Existing player keys and
  legacy aliases scope every page. The route uses existing date/round headers and
  game layouts; Back preserves the source Players tab.
- Book Games has the existing search input with its integrated filter action.
  Text/PGN tags, ECO, result, years, annotations and sort intersect. Clearing text
  retains filters; Reset removes filters. Search stays visible on errors and
  empty results. Dates with missing values do not invent a publication date.
- Collections uses the existing three-tab shell: Openings, Books, Authors.
  Openings expands categories and families. Books keeps the existing cards and
  loaded favorites ordering. Author taps preserve the combined query and use an
  opaque account identity; legacy name-only responses retain a name-filter path.
- Sidebar avatar taps show a modal with background blur, a circular preview,
  Upload, Save and Cancel. No profile page was added. Existing profile navigation
  through the name remains. The native picker center-crops without stretching.
- Avatar Upload uses the existing system gallery picker on iOS and Android.
  Its dedicated `pickProfileImage` entry shares one selected image, with no
  library-wide, camera, storage or save-to-library permission request. iOS
  presents PHPicker directly; Android retains the existing scoped-URI picker
  and fallback. Existing feedback selection keeps its previous entry and flow.
  Desktop/browser retains its existing file picker. OAuth photos remain current
  until a replacement is saved; cancelling selection changes no account data.
- Native and web photos use the same account metadata and storage bucket. Only
  owners of published books supply public author photos. Namesakes stay separate;
  credits are never interpreted as account or FIDE identity. Changing the photo
  grants no publishing rights. Superadmin approval remains required.

## Compatibility and release

Shared changes are optional avatar support on the player card, a photo-only auth
observer, and an additive photo-update method. Account equality, linked chess
accounts, existing authentication events and default player-card behavior remain
unchanged. Gamebase query parameters are optional; envelopes, premium gates,
player aliases, default ordering and existing fields remain available.

Backend changes are in `/Users/berkay/projects/chessever-gamebase-collection-detail`.
Web changes are in `/Users/berkay/projects/chessever-web-collection-detail`. Both
reuse existing feature worktrees. Gamebase commit `62198d7e86dfe7c8969fdbadb5540dfa19376819`
was pushed to its verified production source branch, `main`. The web source
branch was not changed. The mobile checkout retains its unrelated local changes.

Gamebase capabilities are deployed. Its server-only primary Supabase service
key is configured. The existing production `profile-avatars` bucket was verified
as public, limited to 1 MiB JPEG files, matching the web repository's existing
`supabase/migrations/20260928192532_profile_avatar_storage.sql`. No migration
was needed. Mobile and web release and the device checks below remain pending.

## Production Gamebase deployment

Coolify application `t0cg4gk4w04gow4o4gck84cs` serves
`https://service.chessever.com` from `Chessever/gamebase`, branch `main`.
Deployment `uorwbwnvvqx2h0jbilpjqid1` finished successfully at commit `62198d7`.
The API reports healthy and all six companion workers are running. The previous
image was retained as `gamebase:rollback-34a093c-20260930`.

Thirty HTTP checks passed. Root health, search metadata, FIDE player lookup,
book summaries and opening summaries match their pre-deployment response
fingerprints. Author responses add the intended identity/count/photo fields.
Premium book games and players, profile uploads and the staff console still
reject unauthenticated requests. The public game catalog excludes premium games.

The only published probe book is premium. Its deployed query implementation
was checked inside the server with one database connection explicitly set to
`transaction_read_only=on`, Redis caching disabled in that verification process,
and a five-second statement timeout. Three player scopes, 25 combined filter
checks and pagination passed against its two games. No account photo, book,
role, entitlement or publication state was changed for verification. Published
author photos are currently null for the existing editorial credit; owner photo
refresh and upload behavior are covered by the isolated tests.

## Validation

Scoped Flutter analysis is clean. The final Collections/PGN/premium/photo suite
passes 123 tests. Separate profile, guest authentication, top-bar and player-flag
regressions also pass. Tests exercise all new picker controls, empty searches,
back navigation, disclosures, stale replies, retries, crop geometry and 2x text.
The later gallery-selection change has clean scoped Flutter analysis, a passing
Swift syntax check and 17 avatar/feedback tests. These cover both mobile channel
paths, cancellation preserving the OAuth photo, invalid/oversized input and the
existing feedback flow. Platform permission declarations were not expanded.

The isolated PostgreSQL/Redis integration suite and avatar unit suite pass 34
checks, including 192 query/sort combinations, four player scopes, pagination,
section intersections, namesake identity, upload ownership and rollback. Another
61 backend auth/roles/search/identity checks pass. Backend and web TypeScript
checks pass; 89 web profile/publication checks and the account-photo browser test
pass in dark and light themes. External network calls in those tests are mocked.

## Design-law re-check

The user's request to reuse the current application design governs this work.
The full supplied design law was rechecked against each changed interface.

- Typography, fonts, palette, icon vocabulary, card surfaces, nav and input
  geometry come from the current app. No new typeface, gradients, decorative
  badges, tiles, logos, shadows, grids or hero/marketing compositions were added.
- The photo background blur serves the requested modal context; it is not a new
  glass surface. Overlay labels and close controls use readable white ink in
  both themes. Buttons retain the existing component and tonal styling.
- Every new control is wired to its action. Widget pointer tests cover tabs,
  category/family disclosures, author/player navigation, all filter pickers,
  reset, crop preview and cancel. Browser pointer tests cover upload validation,
  failure/retry, saving and header updates. Save ownership and rollback are
  checked separately against mocked service calls.
- Text and controls have existing gutters and safe-area padding. Input remains
  accessible when results disappear. Large-text testing found and fixed a long
  action label. The preview uses one square diameter bounded by available space;
  centering and circular dimensions are asserted.
- Content is visible from the initial frame. The modal scale starts at 0.92,
  never zero opacity; reduced-motion disables its transition. Existing card and
  button interactions remain the app's existing design.
- There is no added decorative footer, hero, testimonial, pricing, illustration,
  mock window, fake social proof, metadata-chip pattern, section seam, grain,
  display-type composition or comparison grid. Those law entries are inapplicable
  to these collection controls; no new designs were introduced to satisfy them.
- Shared code changes remain narrow. Default queries and layouts retain their
  behavior. Explicit sorts preserve the server sequence, including board
  previous/next order, rather than silently regrouping it into chapter order.

Live mobile verification belongs to the user under this repository's AGENTS.md.
No Flutter build, run, app attachment or on-device inspection was performed.

## Device checks after release

1. Open a published book, select Players, tap a player, collapse a date header,
   search/filter, and open a game. Back returns to that book's Players tab.
2. Combine search, ECO, year, result and annotations on Games. Clear text, reset
   filters, change layout, and verify the board's previous/next sequence.
3. Use all three Collections tabs, expand an opening family, and open an author's
   books. Refresh after a photo changed on web.
4. Tap the top-left avatar, then the sidebar avatar. Preview, cancel, then upload
   and save. Verify the header photo and the published author's card. Check
   `/account` Change photo, plus an existing live event and linked chess profile.

## Opening catalog consistency follow-up

- The catalog now uses the existing filter's tree builder without changing its
  grouping logic: All Openings, A–E categories, parent families, then specific
  positions. Categories start collapsed; disclosure state is retained locally.
- Every card occupies the same outer width and minimum height. Tree indentation
  is inside the header, avoiding progressively narrower cards. Heights may grow
  for accessible text rather than clipping content.
- Specific positions use the existing horizontal OpeningEventCard and themed
  game mini-board, with the API FEN and actual book count (1 book / N books).
  Opening taps preserve the active collection query when opening related books.
- Design-law recheck: existing typography, colors, card surfaces and controls
  were reused. No decorative gradients, chips, fonts, shadows or motion were
  introduced. Controls remain visible by default. Outer alignment, internal
  gutters, board centering, title truncation, disclosure actions and card sizing
  were checked in code and widget tests. Existing filter behavior remains covered.
- Validation: scoped flutter analyze on five changed files reports no issues;
  all 42 collection catalog, collection screen and opening filter tests pass.
  Live device checking remains with the user: expand All Openings → category →
  family, compare the position cards, check the displayed boards/book counts,
  and tap a position to open its books.

### Specific opening event-image frame correction

Specific position cards now use the exact event image slot dimensions from
CollectionPlateRow.eventPlate, rather than the smaller square board and shared
header minimum height. The square board is centered inside that landscape slot,
fully visible without stretching or cropping. Range headers retain their tree
controls. The new frame is opt-in for the catalog, preserving other callers.
Widget checks confirm the event slot dimensions, board size, FEN and book count;
all 29 collection screen/search tests pass. The existing component language,
gutters, alignment, visible controls and readable metadata were rechecked.

### Hierarchy indentation correction

The user requested visible left padding through every expanded level. Cards now
step inward by the Home filter's 6.w spacing per level: category, parent family,
deeper family and specific position. Their right edges remain aligned. This
replaces the previous internal-only header indent and also indents position
cards. Event-image slot sizing and book counts are unchanged. Widget assertions
check that descendants move inward while their right edges align; all 29
collection screen/search tests pass and scoped analysis reports no issues.
Design recheck: existing surfaces, typography and controls remain intact, with
consistent tree gutters and no added decoration or animation.

## Author spacing and production avatar repair

- Authors continue using FigmaPlayerCard with its unchanged internal padding,
  56.w circular avatar and name/count typography. The catalog now follows the
  player list's adaptive 16.sp phone / 24.sp tablet gutters and 8.sp top padding;
  rows have the collection player list's 8.sp separation.
- Production returned avatarUrl=null for the published Vasif Durarbayli book.
  Its verified owner has a Google avatar, but the Auth admin lookup rejected the
  legacy HS256 service-role JWT after the project's signing-key migration.
- Gamebase profile-photo operations now optionally prefer a modern secret API
  key, sent only as apikey. Legacy fallback is preserved. Existing legacy keys
  and unrelated integrations were not changed. Caller-session verification,
  ownership checks, bounded photo lookup, project allowlist and upload rollback
  remain intact. The existing main project's default secret key was configured
  server-side for these profile operations only; no key was created or rotated.
- Deployed Gamebase commit 76daf166ed2468e36dbd0bfcb6b3ec3fc23a311a through Coolify
  deployment 516809c1-53e6-4778-ae68-7acbb8ceb331. Deployment finished, server healthy,
  six workers running. Production authors API now returns the Google photo;
  its image responds 200 image/jpeg. Search metadata and published-books routes
  also return 200. No database or account metadata was mutated.
- Validation: TypeScript build passes, 10 avatar tests pass (legacy + modern
  lookup/upload), 29 mobile collection tests pass, scoped flutter analyze clean.
  The widget check confirms the server avatar URL reaches the shared avatar.
  Mobile spacing edits remain local until the app release. Pull-to-refresh
  Authors retrieves the backend photo immediately in an existing app.
- Design-law recheck: shared player-card geometry, typography and surfaces are
  preserved; only list gutters/spacing changed. No decorative effects or new
  control designs were added. Live mobile visual verification remains with the
  user under AGENTS.md.

## Book search pinned above tabs

- The book Games search/filter bar now appears between the detail header and
  About/Games/Players switcher, matching TournamentDetailScreen's ordering and
  adaptive 20.sp phone / 32.sp tablet inset plus 4.h / 8.h vertical spacing.
  It is hidden on About/Players, and remains pinned while Games content scrolls.
- EventViewShell gained an optional beforeTabsBuilder with unchanged defaults.
  Only book detail opts in; existing collection/event routes retain their layout.
- Book search state is owned by the detail screen rather than the Games page.
  Text, filters, debounce and opening scope survive tab switches. Search clear,
  filter application and combined server query behavior retain the same logic.
  Other Games routes own their local search state as before.
- Validation: 87 collection screen/search/premium tests pass; the strengthened
  search test additionally verifies the input lies above the tabs, switching
  tabs retains text, the filter button opens its dialog, and searching/clearing
  updates games. Its final targeted run passes. Scoped analysis is clean.
- Design-law recheck: existing SimpleSearchBar, surface, radius, filter button
  and tournament spacing are reused; no new styles or entrance effects. Controls
  remain visible on Games, including empty results. Geometry is asserted in the
  widget test. Runtime mobile verification remains with the user.

## Shared Home filter popup components

- Extracted Home FilterPopup's actual panel, option grids, section labels and
  Reset/Apply footer into filter_popup_components.dart. Home now consumes the
  same components as Collections, preserving its values, callbacks and layout.
- Collections use the identical 280.w panel, 600.h maximum height, surface,
  radius/border, 20.w / 16.h inset, section spacing and button sizes/colors.
  Removed the separate title/close toolbar, text-button Apply, native switches
  and result/sort dropdown treatment. Result, year activation, annotations and
  sort now use Home's two-column option boxes. Opening tree, author picker and
  year wheels remain the existing app components.
- Collection query combinations, search text preservation, author identity,
  pending edits, reset and barrier dismissal remain covered. Exact ECO choices
  remain intentional because the collection API accepts exact ECO codes only;
  unsupported Home event status/time-control/rating filters are not presented.
- Validation: 49 collection/search/Home-filter/combination tests pass; a final
  nine Home opening popup tests also pass after adding shared-component checks.
  Scoped analyze on six changed files reports no issues. Both popup contexts
  are asserted to use the same FilterPopupFrame and FilterChoiceGrid widgets.
- Design-law recheck: requested reuse takes precedence over generic redesign
  defaults. The actual existing Home design is shared rather than reinterpreted.
  Controls use real callbacks, selected semantics and existing animation/colors;
  no new fonts, decoration or effects were introduced. The scrollable panel
  preserves access to controls and footer. Live mobile review remains with user.

## Author row numbering

Authors now use FigmaPlayerCard's existing rank column with rank=index+1 and
showRank=true, exactly as Favorites/Countrymen player rows do. No new number
badge or padding was introduced. CollectionCatalogList offers an optional
indexed builder so numbering follows display order and continues across pages;
existing item-builder callers retain their behavior. Query resets start from 1.
Widget checks verify the author rank is visible and indexes survive a next-page
failure/retry. Scoped analyze clean, all 29 collection screen/search tests pass.
Design recheck: the shared rank geometry, text style and alignment are reused;
avatars, counts and tap behavior remain unchanged.

## Book Openings, hidden About and tournament search-size parity

- Unlocked book detail now defaults to Games within [About, Openings, Games,
  Players]. It uses the same scrollable SegmentedSwitcher as team events, with
  each segment occupying one third of the viewport. Initial Games selection
  scrolls right, showing Openings/Games/Players and keeping About off the left.
  Openings selection scrolls left to reveal About; Games/Players scroll right.
  About remains available by strip scrolling or page swiping. Existing event
  collections retain their original three-tab layout. Locked books still open
  on About and preserve the existing access-confirmation behavior.
- Book Openings reuses CollectionOpeningCatalog and its identical hierarchy,
  indentation and event-image mini-boards, backed by collectionOpeningsProvider
  with the current book slug. Its leaf count is games in that book. The global
  catalog continues showing book counts and opening related books.
- Opening taps push the same scoped game-screen implementation used for player
  taps, passing the book slug and exact ECO. Games group by calendar date with
  collapsible tournament headers; board navigation uses that filtered list.
  Back returns to the book's expanded Openings tab. The redundant clear-opening
  row is omitted in this scoped route, as the route title already identifies it.
- Tournament and collection detail now share EventSearchBarFrame. The collection
  filter tile opts into compact vertical padding, keeping the existing search
  row dimensions while retaining its filter callback and badge. Other search
  bars retain their default geometry. Query persistence and filter behavior
  remain covered.
- Completion evidence: the book widget test verifies four-tab ordering, team
  scrolling offsets, slug-scoped metadata requests, exact book/ECO game query,
  game exclusion, date-header collapse and returning to expanded Openings.
  Search comparisons verify measured width/height against the tournament frame
  and search control. Four additional geometry tests cover phone/tablet at 1x
  and 2x text, with a working filter button and active badge.
- Validation: 129 collection/catalog/premium/Home-search/tournament regression
  tests pass; all four additional size-parity tests pass. The final scoped
  opening-route test passes after adding an explicit book-slug assertion.
  Scoped analyze on eight changed files reports no issues.
- Production read-only verification: Advanced's existing book-scoped opening
  metadata endpoint returns 200, ECO B12/C02, and game counts. No backend change,
  migration or deployment was required. Mobile edits remain local until release.
- Design-law recheck: existing team tabs, opening cards/tree, date headers and
  tournament search surfaces were reused. No new designs, fonts or effects were
  added. Controls and geometry were exercised in widget tests; deliberate tab
  clipping is the requested horizontal scrolling behavior. Live mobile testing
  remains with the user under AGENTS.md; no Flutter run/build was performed.

## Persistent book search and combined results

- Book detail now retains its search/filter bar above every tab, including About
  and locked content. Tab changes no longer insert or remove the search row.
  The main Collections search was already persistent and remains unchanged.
- An active search or filter shows one book-scoped result list beneath the tabs:
  Openings, Games and Players. It reuses OpeningEventCard with the event-image
  board frame, DiscoveryGameList in the selected layout, and the exact shared
  collection player row. Search matches opening names/ECO and player names;
  game text search continues using Gamebase. Game filters constrain eligible
  openings and players through the same filtered game memberships.
- EventViewShell has an optional content override, keeping its tab pages mounted
  and offstage during search. Clearing the query restores the selected tab and
  its existing page state. Premium gates, book scope and export restrictions
  remain in place. Existing event callers use the unchanged default behavior.
- Design recheck: existing fonts, surfaces, card geometry, gutters and controls
  are reused; no new card design, decorative effects or hidden entrance content.
  Results are lazy sliver rows with visible section labels and retry/empty states.
  Pointer/widget tests check stable search-bar bounds across every book tab,
  shared opening/game/player cards, scoped queries, filter intersections, reset
  and returning to the selected tab. Live device checking remains with the user.
- Validation: scoped Flutter analysis reports no issues. The collection screen,
  premium, catalog search, search-size parity and My Likes regression suites pass
  97 tests. The strengthened unified-search filter/reset test also passes. No
  Flutter build/run or deployment was performed for this mobile-only change.

## Collection filter simplification and player result parity

All collection popups now omit Annotations and Sort, including the main catalog.
Apply clears any legacy hidden values to the default query. Result choices reuse
the player-profile Games dialog's actual adaptive chip component, extracted
without changing its layout, typography, selected state or enabled callbacks.
Choices are All, 1-0, 0-1 and ½-½, with the existing PGN query values. Unfinished
is absent; no live/completed status control was added. Remaining opening, year
and author controls keep their shared Home components. Source/design checks
confirm existing surfaces, visible controls and adaptive large-text layout.
Scoped analysis is clean; 40 collection and shared game-filter tests pass.
Mobile changes remain local; device checks belong to the user.
