# Collections search

The Collections home bar uses the same `SimpleSearchBar` and `HomeTopBarRow`
geometry as the other main routes. Search is debounced by 300 ms and shared
across Openings, Games, and Books. The filter dialog intersects ECO, game result,
game-year range and author, with recommended/date/name ordering. Opening selection
reuses the shared searchable ECO picker. Year selection uses the existing two-wheel
range, initially last year through this year (2025–2026 in 2026); Reset restores
that range. Both bounds are applied on the server before pagination. Author
selection reuses the shared expandable dropdown with published book credits.

Search is server-side, before pagination. Each tab loads 40 rows at a time;
scrolling near the bottom requests the next page. A changed query discards older
responses, resets pagination and scroll position, and retains the current filters.
A failed next page retains existing rows and offers a retry at the same offset.

Words match indexed book metadata or parsed player/event/opening metadata in the
same game. Prefixes and canonical ECO opening names are supported. PGN header
search supports `[White "Carlsen"] [Black "Anand"]`, Event, Site, Date, Round,
ECO, Result, Opening and Annotator. All game filters must match one game;
matching separate games in a book does not satisfy a combined query.

Scope: this searches PGN metadata, not arbitrary comments, variation text,
move sequences or every intermediate FEN. It never downloads the complete PGN
catalog to perform filtering. Game dates drive date sort on Games/Openings;
publication dates drive it on Books. Unknown game dates sort last.

The API addition is in `chessever_gamebase-catalog-fix`:
`GET /api/collections/catalog/books`, and optional search/filter/sort parameters
on the existing `/api/collections/openings` and `/api/collections/games` routes.
Existing unfiltered routes, publishing, and Premium access rules remain intact.
The implementation uses the existing `collection.search_tsv` and
`collection_game.search_tsv` GIN indexes and collection-membership index.
No database migration, backfill, main-games-table change, or trigger is needed.

Validation: 192 combinations of text/ECO/result/year/annotation/sort against
an isolated PostgreSQL fixture, including page order and access boundaries;
Flutter tests for request serialization, stale responses, retry offsets,
filter selection and reset, and the shared main-route search bar. Device verification
belongs to the user: search a known player, combine ECO + year, switch all
three tabs, clear search/reset filters, and scroll to load another page.

Release evidence (2026-09-28): Gamebase commit `fe62349` is on its production
release branch. The live API's three pre-existing collection modules matched
the deployment baseline exactly. The additive release changes only those three
modules and the new query helper. The separate production-data check confirmed
the three required existing indexes and measured 6–53 ms for the tested service
queries on the current small catalog. These are server timings, not an end-to-end
network guarantee. TypeScript type-check and scoped Flutter analysis passed.
The backend integration suite passed all 23 tests. Search-specific Flutter tests
and the main-route search/filter/clear interaction passed. The wider backend unit
run had one unrelated, unchanged PGN-decoding wall-clock benchmark exceed its
3-second threshold under local load; its isolated rerun also exceeded that
threshold. No decoder changes were made or deployed.

Production rollout completed successfully. Seven public HTTPS endpoint checks
returned 200, covering the legacy collection list and catalog routes plus combined
filters, sorting and PGN-header search. Observed public request times were
69–977 ms including cold connection/proxy overhead. The first rollout attempt
rolled back automatically because it checked routing before Docker health was
ready; the successful attempt waited for container health and proxy readiness.
Only the API server was recreated. The previous image remains tagged
`gamebase:before-collection-search-20260928` for rollback.

The additive range/author API accepts `minYear`, `maxYear` (inclusive) and `author`.
The legacy `year` parameter remains supported. `GET /api/collections/catalog/authors`
returns paginated public book-credit names only. Account-role grants are managed
by staff on the web; no role or account data is exposed by this public endpoint.

Range/author release (2026-09-28): Gamebase `a2dda70` is deployed and persisted
on its release branch. All 24 local integration tests passed, including author
role CRUD and ownership/revocation. Production read-only canaries took 5–44 ms
on the current catalog. Eight public HTTP checks passed, including reversed-range
validation, unauthenticated role denial and the legacy year parameter. No schema
changes or role grants were applied. Rollback image: `gamebase:before-author-range-20260928`.
The corresponding staff controls in the web repository are local changes; they
have not been deployed to chessever.com in this turn.
