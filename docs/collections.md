# Collections (Discovery › Collection)

A collection is a curated set of annotated games: a GM's annotated games from
one tournament (`kind = event`, e.g. "US Championship 2025"), or the games of a
book (`kind = book`, with an About text on the author and the book). The app
lists them under For You › Discovery › Collection, laid out like an event:
About, Games and Players tabs.

## Where they live

In **chessever_gamebase** (the `service.chessever.com` API and its Postgres),
not in Supabase. A collection has:

- its metadata: slug, kind, title, subtitle, author, annotator, about, cover,
  location and dates (events), publisher and year (books), sort order and a
  status (`draft`, `published`, `archived`);
- a **section tree**: rounds (or stages) for an event; parts holding chapters
  for a book. A section carries a label ("Round 5", "Chapter 7", "Part I"),
  the printed number, a title, a round date, and for a chapter an intro text;
- its **games**, each with its whole PGN (comments, NAGs and variations
  intact), the section it sits in (or none: "unsorted") and its order there;
- derived data the importer rebuilds on every change: the players table
  (games, W/D/L, best rating per player), counts, player names and ECOs.

The app only ever sees `published` collections. The old Supabase tables
(`discovery_collections`, `discovery_collection_games`, migration
`supabase/migrations/20260925120000_create_discovery_collections.sql`) are no
longer read by the app, and `scripts/collections/upload_collection.py`, which
filled them, has been removed. The migration stays so the schema history is
intact, which is why its header still names that script.

## How the app reads them

`lib/repository/gamebase/gamebase_repository.dart` (`getCollections`,
`getCollection`, `getCollectionGames`, `getCollectionPlayers`) with the models
in `lib/repository/gamebase/collections/collections_models.dart`. Same Dio
client, base URL and `X-API-Key` as every other gamebase call (the
`GAMEBASE_API_KEY` dart-define, or `.env` in debug builds).

| Endpoint | Used for |
| --- | --- |
| `GET /api/collections?limit=100&offset=…` | the Events / Books lists (paged until `total`) |
| `GET /api/collections/:slug` | About text and the section tree |
| `GET /api/collections/:slug/games?include=pgn&limit=200&offset=…` | every game with its PGN (paged until `total`) |
| `GET /api/collections/:slug/players` | the Players tab |

Every response is the gamebase envelope `{ "status": "success", "data": … }`.
`lib/screens/collections/collections_data.dart` turns each PGN into the game
card / board model and groups the games under the tree for the Games tab: an
event's games under their rounds (label and date), a book's under its parts
and chapters (each chapter's number, title and intro above its games), games
in no section last. Games without sections use the same round surface,
grouped by Event, calendar date and Round (or the supplied PGN tags when an
older API omits the structured fields). Opening a game hands the board the
selected chapter/round list in that order; All games walks the full collection.

## Uploading one

Use the admin console on chessever.com: **Content › Collections**.

1. **Create** the collection: pick Event or Book, give it a title (the slug is
   made from it) and fill in what applies: subtitle, author, annotator,
   location and dates, publisher and year, cover URL, sort order (lower comes
   first), and the About text (blank lines separate paragraphs). It starts as
   a **draft**, which the app does not show.
2. **Import** a PGN file (up to 10 MB / 1,000 games per import). Keep the
   annotations in the PGN: comments `{...}`, NAGs (`$1`, `!?`) and variations
   all reach the board as they are. `WhiteTitle`, `WhiteElo`, `WhiteFed`,
   `WhiteFideId` (and the Black ones) fill the players' titles, ratings, flags
   and identities. Choose how games are grouped:
   - **Round**: one section per `[Round]` (its major part: "5.3" is round 5,
     board 3). The usual choice for an event.
   - **Chapter**: one section per `[Chapter]` tag. Games without the tag go to
     Unsorted.
   - **Single**: every game into one chosen section.
   - **None**: everything into Unsorted.

   and what to do with games already in the collection (matched by players,
   round, start position and moves): **update** replaces their PGN, **keep**
   leaves them. Run the **dry run** first: it shows, per section, how many
   games would be added, updated, left unchanged or failed (an illegal move
   holds that one game back; the rest still import). Then apply it. Imports
   never delete games, and each one is recorded in the collection's import
   history.
3. **Arrange** the sections: labels, numbers, titles, round dates and chapter
   intros; put chapters under parts; reorder sections and move games between
   them. Deleting a section moves its games to Unsorted.
4. **Publish** it (status → published). To take it down, set it back to
   draft or archive it.

The app picks up changes on the next load or pull-to-refresh; the API caches
responses and clears that cache after every admin write.


## Shared tournament detail components

The collection's Games tab reuses `TournamentRoundHeader` (also used by the
live tournament's `RoundHeader`), `TextDropDownWidget` and the existing
`DiscoveryGameList` adapter to tournament GameCard/board/grid components.
Author parts and chapters retain their order and introductions. The selector
opens the chosen chapter/round, collapse controls keep their state, and a
parent heading provides context without admitting sibling games into board
navigation. Unsectioned games fall back to event + date + round groups in
first-appearance/file order. Date-only headers do not fabricate a start time;
verified API `startsAt`/`playedAt` values display a labelled UTC time.

The layout switch is in the upper-right beside the three-dot menu. It cycles
list, board grid and board, while retaining this screen's selection across
its tabs. The about tab uses `TournamentAboutField` for event/edition and
contents alongside the book's actual cover, supplied credits and foreword.
The Players tab uses `FigmaPlayerCard`, including the same photo/title/flag
logic as Favorites and Countrymen. Missing ratings stay absent. Legacy split
name/FIDE rows merge only with unambiguous identity/federation evidence and
retain aliases so tapping one person includes every matching game.

The structured card augments PGN player IDs, titles, ratings, federation and
opening fields. Missing API side names never replace real PGN names with
White/Black. The source PGN remains byte-for-byte intact for annotations,
variations, clocks and board replay.

### Validation and device checks

Scoped `flutter analyze --no-pub` passes. The focused collection, PGN hydration,
Premium and event-focus suites pass 118 tests, including actual widget taps on
collapse/selector, all three layouts and the shared player card's alias filter.
Large books mount visible card rows lazily. Existing entitlement, favorites,
context menus and board evaluation providers retain their behavior.

The requested design re-check follows the existing tournament/card language:
no new font, palette, decorative badge, mock window, logo, gradient, background
field, floating artifact, pricing/testimonial/footer/hero composition or
entrance animation was introduced. Those marketing patterns are inapplicable
here. The checks that apply to these screens cover consistent gutters, text
contrast in both themes, flexible multiline headers, centered bare controls,
readable dates/credits, actual game data, valid selector/collapse/layout/player
interactions and large-text overflow. Existing shared card styling is retained
as explicitly requested. Real device runtime/visual testing remains the user's
responsibility under AGENTS.md; no Flutter app was launched or built.

On the test app, check:

1. A chaptered book: select a chapter, collapse/reopen it, and step previous/next
   on the board. The selection excludes sibling games. Select All games to
   restore the full order.
2. A book without chapters: event/date/round headers, calendar-only dates and
   labelled UTC times when provided; all three card layouts from the icon next
   to the menu.
3. Players: one card for a player whose games mix explicit FIDE IDs and names;
   tapping it includes all their games. Known namesakes remain separate.
4. About/credits/foreword, context menus, signed-out and Premium states, both
   themes, a narrow phone and larger accessibility text.

Deployment order is the test Gamebase additive migration, concurrent indexes,
API, then matching web/mobile clients. See the Gamebase collection runbook.
The old Supabase discovery schema and production environments are untouched.
