# Mobile notification destinations

Notifications may carry `data.route` as an explicit mobile destination. An inbox
publication without an override carries `inbox_message_id` and opens that exact
published message. A valid explicit route takes precedence over the attached
inbox message. An unsupported route falls back to the attached message, then
Home. Dismissing a Premium prompt consumes the route without another navigation.

Use `/app/...` or `https://chessever.com/app/...`. The mobile parser also accepts
the `www.chessever.com` HTTPS host, explicit HTTPS port 443, and
`com.chessever.app://app/...`. Every accepted route normalizes to the canonical
HTTPS URL. Existing notification `url` links for games, broadcasts, books,
databases and players continue to work.

## Catalog

Every path component is meaningful. Unknown suffixes and unknown query keys are
rejected, including suffixes after an otherwise supported parent. A single
trailing slash is allowed. Values shown as `<id>` are percent-encoded path
segments; a FIDE ID is a positive integer of at most 12 digits.

| Route | Landing page | Optional query |
| --- | --- | --- |
| `/app`, `/app/home` | Home, Today | None |
| `/app/home/today` | Home, Today | None |
| `/app/home/my-space`, `/app/my-space` | Home, My Space | None |
| `/app/my-space/prep` | My Space Prep component | None |
| `/app/my-space/library` | My Space Library component (databases only) | None |
| `/app/my-space/likes` | My Space Likes component | None |
| `/app/home/discovery` | Home, Discovery | None |
| `/app/events` | Events main tab | None |
| `/app/inbox` | Inbox list | None |
| `/app/inbox/<message-id>` | Exact visible inbox publication | None |
| `/app/feed` | Feed | None |
| `/app/news` | Discovery News | None |
| `/app/news/<id>[/<slug>]` | Published ChessEver article in the shared reader | None |
| `/app/news/partners/<source>/<id>[/<slug>]` | Published partner article in the shared reader | None |
| `/app/likes` | Public most-liked games | None |
| `/app/likes/<period>` | Likes on `today`, `week`, `month`, or `year` | `date=YYYY-MM-DD`, `view=games` or `players` |
| `/app/my-likes` | The reader's liked games | None |
| `/app/miniatures` | Miniatures | None |
| `/app/miniatures/about`, `/app/miniatures/players` | Selected Miniatures tab | None |
| `/app/miniatures/games` | Miniatures Games, optionally filtered to one PGN calendar day | `date=YYYY-MM-DD` |
| `/app/reports` | Game Reports, behind its existing Premium gate | None |
| `/app/reports/<type>` | Selected report-type tab, with the same Premium gate | `date=YYYY-MM-DD` |
| `/app/my-prep` | My Prep | None |
| `/app/my-prep/<profile-id>` | Existing local Prep profile | `account` |
| `/app/library` | Library | None |
| `/app/library/database` | ChessEver Database | `event`, exact database event name |
| `/app/collections` | Published collections | None |
| `/app/collections/<collection-id>` | Collection, with fresh access and Premium checks | None |
| `/app/calendar` | Calendar, optionally on one day | `date=YYYY-MM-DD` |
| `/app/favorites` | Favorites games | None |
| `/app/favorites/games` | Favorites games | None |
| `/app/favorites/list`, `/app/favorites/events` | Saved Favorites list | None |
| `/app/favorites/players` | Player rankings | None |
| `/app/settings` | Settings | None |
| `/app/settings/board` | Settings with Board expanded | None |
| `/app/settings/engine` | Settings with Engine expanded | None |
| `/app/settings/botvinnik` | Settings with Botvinnik expanded | None |
| `/app/settings/notifications` | Settings with Notifications expanded | None |
| `/app/settings/customization` | Settings with Customization expanded | None |
| `/app/players/<fide-id>` | Player About | `name` |
| `/app/players/<fide-id>/about` | Player About | `name` |
| `/app/players/<fide-id>/games` | Player Games | `name` |
| `/app/players/<fide-id>/events` | Player Events | `name` |
| `/app/players/<fide-id>/openings` | Player opening tree, behind its existing Premium gate | `name`, `color`, `fen`, `moves` |
| `/app/streaks` | Streaks wall | `tc` |
| `/app/streaks/<fide-id>` | Player streak card | `tc` |
| `/app/explorer` | Isolated board and opening explorer | `fen`, `moves` |
| `/app/positions` | Explorer at a position | **Required** `fen`; optional `moves` |
| `/app/openings/<ECO>` | Explorer on the catalog opening line | None |
| `/app/games/<game-id>` | Existing game resolver | `fen`, `src=gamebase` |
| `/app/books/<share-token>` | Existing book preview resolver | None |
| `/app/databases/<folder-id>`, `/app/folders/<folder-id>` | Existing database resolver | None |
| `/app/player/<route-id>` | Existing FIDE or Memorial profile resolver | None |
| `/app/player/<name-slug>/<route-id>` | Existing FIDE or Memorial profile resolver | None |
| `/app/broadcast/<event-id>` | Existing broadcast resolver | `tab` |
| `/app/broadcast/<slug>/<event-id>` | Existing broadcast resolver | `tab` |
| `/app/broadcast/<slug>/<event-id>/player/<fide-id>` | Event player scorecard | None |
| `/app/broadcast/<slug>/<event-id>/team/<team-name>` | Event team scorecard | None |

`account` is the exact existing Prep account key, such as `lichess:username`;
the profile and account must exist on the receiving device. These local IDs
are appropriate for a known recipient, not a general campaign.

`color` is `white`, `black`, or `all`. `tc` is `standard`, `rapid`, or `blitz`.
`tab` is `about`, `games`, `standings`, `bracket`, or `players`; the existing
event screen normalizes tabs to the selected event's actual layout. Streaks
destinations respect the app's feature flag.

`ECO` is an uppercase code from A00 to E99 with a playable bundled catalog
line. `fen` must describe a valid standard-chess position. `moves` is a
space-separated SAN or UCI line played from the standard start. Move numbers
are accepted. Every move must be legal; when both `fen` and `moves` are given,
the entire line must reach that FEN. Invalid lines never open a partial position.

## Validation and routing boundary

News shares use `https://chessever.com/news/<id>/<slug>` or
`https://chessever.com/news/partners/<source>/<id>/<slug>`. The same paths work
with `www.chessever.com` and `com.chessever.app://news/...`. The id and publisher
resolve the article; an absent or stale slug does not break it. Cold links wait
for startup/session restoration and open above Home. Warm News links preserve
the current stack. `/news` and paginated index links open the News catalog.

News, news posts in Feed, article links and incoming shares open the same
unrestricted reader. On supported mobile platforms, readers without a paid
subscription see Feed's swipeable ad pages between articles, at positions
3, 8, 13…; the News grid stays article-only. No ad-or-subscription prompt gates
reading. Pulling up past the bottom of an article fills an indicator; releasing
past its threshold advances one page, including an ad when due. The footer can
also be tapped. Short pulls and momentum scrolling do not turn pages.
Only published records are resolved, including articles outside the latest Feed
batch. Partner original URLs remain separate from ChessEver share URLs.

`test/fixtures/news-links.json` is mirrored in `chessever_web_frontend`; both
test suites verify the same identity and slug contract. The website owns the
iOS association file and the `/api/og/news` previews. Android already claims
all paths on both ChessEver HTTPS hosts.

The whole route is limited to 4,096 characters and each decoded path segment
to 200. Empty segments, dot traversal, backslashes, decoded slashes, controls,
malformed percent escapes, fragments, credentials, external hosts, non-HTTPS
web URLs, duplicate query keys and empty query values are rejected. An internal
path is a supported route schema, never an arbitrary Flutter named route.

The parser lives in `lib/services/app_destination.dart`. The executor in
`lib/services/app_destination_service.dart` constructs real screens and retains
their access checks. It delegates exact Inbox loading and existing content
resolution back to DeepLinkService. Adding a destination requires an explicit
parser branch, executor, tests, and a matching admin validator/catalog change.

## Examples

```json
{"type":"inbox_message","inbox_message_id":"published-message-id"}
```

```json
{"type":"inbox_message","inbox_message_id":"published-message-id","route":"/app/settings/notifications"}
```

```json
{"type":"call_to_action","route":"/app/players/1503014/games"}
```

```json
{"type":"call_to_action","route":"/app/broadcast/olympiad/event-id/team/United%20States"}
```

For device verification, tap a default Inbox push on a terminated app, then an
Inbox push with `/app/settings/notifications`, then a standalone push targeting
a player Games tab or event scorecard. Confirm the exact target and Back to Home.
Repeat a Premium destination as a free reader and cancel its prompt; there must
be no unexpected fallback navigation. Live-app testing is performed by the user.

Switching between Today, Week, Month and Year resets to the latest range.
Likes section links follow the current calendar period when `date` is absent.
With `date`, the ranking opens the day, Monday-based week, month or year
containing that date. Long-press a period or the date label, then choose Share.
These URLs also work as notification `data.route` or `data.url` values.

## Likes ranking pagination

Likes reads 12 games at a time and loads another page when its footer enters the
scroll cache. Boards use lazy slivers in board, grid and compact-row views.
Games and Players share the loaded pages for the selected calendar window;
Players aggregates those loaded games. Changing the period/date or refreshing
starts a new ranking. Failed pages retain earlier games and offer Retry.

The additive migration `20261028150850_likes_ranking_pagination.sql` installs
`most_liked_ranking_page` in production project `oelbsuggrzyqwzmvidju`. It keeps
the older `most_liked_ranking_preview` API intact. Until the new RPC is deployed,
the app falls back to that preview and its existing cap.

Pages use `(like_count DESC, source_game_id ASC)` keyset cursors and fetch one
extra aggregate row to detect the next page. Only games with at least two distinct
likes qualify. Cursors advance over unresolved games, and appended IDs are
deduplicated if the live ranking changes. Ranks reflect the positions read;
pull-to-refresh gets a fresh ordering. Only authenticated callers may read the
aggregate IDs/counts; individual game access retains its existing Premium guard.

`supabase/tests/likes_ranking_pagination.sql` verifies the actual migration in an
empty disposable PostgreSQL database, including more than 50 results, ties,
window boundaries, distinct-user likes, page caps, cursors and authentication.
It is a local fixture, never a production SQL script.

## Miniatures sharing

Long-press any Miniatures tab or a dated heading in Games, then choose Share.
Tab links open that tab with the default Games filters. A Games date link sets
both date bounds to the shared PGN calendar day and opens Games. Other search
and filter settings are reset in the linked screen's own scope. These routes
work through HTTPS links, the app scheme and notification `data.route`/`data.url`.

## Reports sharing

Long-press a Reports type chip or date heading, then choose Share. `<type>` is
`all`, `upside_down`, `comeback`, `one_blunder`, `great_escape`, `domination`,
`squeeze`, `deadlock`, `miniature` or `marathon`. A date link preserves the type
and filters the paginated query to that UTC calendar day, using inclusive
midnight and exclusive next midnight. Undated type links browse all days.
The linked screen owns its type/date state, preserving an already-open Reports
screen. HTTPS, app-scheme and notification routes use the same Premium guard.

My Space: hold Prep, Library, or Likes outside Edit and choose Share. These
links open the recipient's own workspace; they do not publish private data.
