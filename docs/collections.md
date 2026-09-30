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
in no section last. Opening a game hands the board the whole list in that
order, so prev/next walks the collection.

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

## Production integration (35.25.1+3502)

This release reuses tournament round headers, game cards, About fields and the Favorites/Countrymen player cards. Book Games tabs begin directly with collapsible chapters or event/date groups; the redundant All games selector and game-count toolbar are removed. The existing layout switcher sits beside the three-dot menu in the header. Event collections retain the round selector.

Book list pictures share the event card's 5:4 proportions, retaining the pixel placeholder. Unique reader counts use an eye icon; the existing star pins books and displays the star count. The folder publication action moves from folder cards into the far right of the folder header, alongside all original controls in one row. Smart Events omits its header tally.

Library owners submit drafts for superadmin approval. Metadata and PGN snapshots never auto-publish. Nested owned folders supply chapters. Source variations, comments, NAGs and clocks are preserved. Ownership, staff takedowns, source deletion and concurrent updates are checked on the server. Existing public collection contracts and premium gates remain supported.

Production folder publishing reuses the existing authenticated Gamebase client, with the user's session and redirect forwarding disabled. The web profile uses its server bridge. Browser challenges on the marketing site cannot block native folder operations.

New server summary fields and SQL tables/columns are additive. Shared widget options retain their original defaults outside Collections. This isolated stable patch excludes unrelated Feed/My Space work from the development checkout. The .env asset line is commented for clean CI builds.

Validation: scoped Flutter analysis and 133 relevant collection/publishing regressions pass. Device verification remains with the product manager: open a book, collapse chapters, switch the three game layouts in the header, tap a deduplicated player to filter games, star a book and check its pinned order; then check the one-row folder header and submit a draft. Verify a live tournament and Favorites/Countrymen in both themes.
