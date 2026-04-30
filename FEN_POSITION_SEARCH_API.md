# FEN Position Search — Games Endpoint

This endpoint returns games that **ever reached** a given chess position, regardless of move order or how many half-moves it took to get there. It's the FEN-only counterpart to the opening-explorer games endpoint (`/api/game-position/games`).

## When to use this vs. the opening-explorer endpoint

| Endpoint | Anchored on | Returns |
|---|---|---|
| `/api/game-position/games` (explorer) | `(fen, fullmove counter)` from the FEN — i.e. the position **at a specific ply** | Games that reached the position at exactly that ply |
| `/api/game-position/fen/games` (this one) | `(fen_key)` only — first 4 FEN fields, ply ignored | Games that reached the position at **any** ply |

Use the explorer when you want canonical opening-tree behavior. Use **this** endpoint when the user is exploring a specific position and wants every game that contains it, including transpositions reached after extra shuffling moves or via different move counts.

The result set of `/fen/games` is a strict superset of `/games` for the same position.

---

## Endpoints

Both variants use the same response shape. Pick GET for simple cases, POST for multi-key sorting (`orderBy`).

### `GET /api/game-position/fen/games`

Query params (all filters/sorts are optional):

| Param | Type | Notes |
|------:|:-----|:------|
| `fen` | string (required) | First 4 FEN fields are sufficient (`pieces turn castling en-passant`). Halfmove/fullmove are ignored. URL-encode the spaces. |
| `uci` | string | Filter to games where the next move played from this position equals this UCI move (e.g. `e2e4`, `e7e8q`). Lowercase. |
| `playerId` | UUID | Restrict to games involving this player. |
| `color` | `white` \| `black` | When combined with `playerId`, restrict to games where that player had this color. |
| `timeControl` | `CLASSICAL` \| `RAPID` \| `BLITZ` | |
| `result` | `W` \| `B` \| `D` | White wins / Black wins / Draw. |
| `isOnline` | `true` \| `false` | Online (chesscom/lichess) vs OTB. |
| `minRating` | int | Minimum average rating of the two players. |
| `maxRating` | int | Maximum average rating of the two players. |
| `yearFrom` | int | Inclusive lower bound on game year. |
| `yearTo` | int | Inclusive upper bound on game year. |
| `sortBy` | string | See **sortable fields** below. |
| `sortDirection` | `asc` \| `desc` | Default `desc`. |
| `pageNumber` | int (≥ 0) | 0-indexed. Default `0`. |
| `pageSize` | int (1–50) | Default `20`. |

### `POST /api/game-position/fen/games/query`

JSON body shape — same fields as the GET variant, plus:

| Param | Type | Notes |
|------:|:-----|:------|
| `orderBy` | `Array<{ field: string, direction: "asc" \| "desc" }>` | Multi-key sort. Applied in order. `sortBy` (if also provided) is appended to the end. Falls back to `date DESC, id DESC` if no valid fields are given. |

Example:

```json
{
  "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
  "minRating": 2400,
  "timeControl": "CLASSICAL",
  "orderBy": [
    { "field": "avgElo", "direction": "desc" },
    { "field": "date", "direction": "desc" }
  ],
  "pageNumber": 0,
  "pageSize": 20
}
```

---

## Sortable fields

Pass any of these as `sortBy` or in `orderBy[].field`:

`id`, `date`, `eco`, `opening`, `variation`, `event`, `site`, `whiteName`, `blackName`, `whiteTitle`, `blackTitle`, `whiteFideId`, `blackFideId`, `whiteElo`, `blackElo`, `whiteFed`, `blackFed`, `whitePlayerId`, `blackPlayerId`, `timeControl`, `result`, `avgElo`.

Default sort if none specified: `date DESC, id DESC`. Date and id are always appended as tiebreakers if not already in the sort list.

---

## Auth

Like all `/api/*` endpoints:

```
X-API-Key: <your-key>
```

Missing/invalid keys return `401`.

---

## Response

```json
{
  "status": "success",
  "data": [
    {
      "id": "uuid",
      "date": "2024-01-15T00:00:00.000Z",
      "timeControl": "CLASSICAL",
      "result": "W",
      "eco": "C42",
      "opening": "Petrov Defense",
      "variation": "Classical Attack",
      "event": "Some Open",
      "site": "Reykjavik",
      "isOnline": false,
      "white": "Carlsen, Magnus",
      "black": "Caruana, Fabiano",
      "whitePlayerId": "uuid",
      "blackPlayerId": "uuid",
      "whiteElo": 2839,
      "blackElo": 2820,
      "avgElo": 2829,
      "whiteFed": "NOR",
      "blackFed": "USA",
      "whiteFideId": "1503014",
      "blackFideId": "2020009",
      "whiteTitle": "GM",
      "blackTitle": "GM"
    }
  ],
  "metadata": {
    "pageNumber": 0,
    "pageSize": 20,
    "hasMore": true
  }
}
```

`hasMore` is computed by fetching `pageSize + 1` rows internally; if it's `true`, request `pageNumber + 1` to continue.

---

## FEN matching rules

- Only the first **4 FEN fields** are used as the lookup key: piece placement, side to move, castling rights, en-passant square.
- Halfmove clock and fullmove number are **ignored**.
- The endpoint accepts both 4-field and 6-field FENs. If your client computes FENs from a board state, you can omit the trailing two fields.
- Spaces must be URL-encoded in GET requests (`%20`).

If you're getting empty results when you expect matches:
- Check `castling` and `en-passant` are correct for the position. A live board may have stale rights/en-passant that don't match the canonical FEN of the same visual position.
- Confirm the side-to-move (`w`/`b`) matches.

---

## Caching & performance notes (for client behavior)

- Pages 0–4 with `pageSize ≤ 100` are cached server-side for 6h. Subsequent identical requests are fast.
- Beyond page 4, results are uncached and may be slow on popular positions.
- Cache key includes every filter, sort spec, and pagination input — changing any filter triggers a fresh query.
- Cold queries on very popular positions (e.g. starting position, classical openings) with selective filters and non-date sort can take several seconds. Consider showing a loading state and avoiding non-essential filter changes when it costs another network roundtrip.

---

## Examples

### Most recent classical games at a position, OTB only

```
GET /api/game-position/fen/games?fen=...&timeControl=CLASSICAL&isOnline=false&pageSize=20
```

### Highest-rated games where White played 1.e4

```
GET /api/game-position/fen/games?fen=<starting-position>&uci=e2e4&sortBy=avgElo&sortDirection=desc
```

### A specific player's games where this position appeared, sorted by rating then date

```http
POST /api/game-position/fen/games/query
Content-Type: application/json
X-API-Key: ...

{
  "fen": "...",
  "playerId": "<uuid>",
  "color": "white",
  "orderBy": [
    { "field": "avgElo", "direction": "desc" },
    { "field": "date", "direction": "desc" }
  ]
}
```

### Year-range scan

```
GET /api/game-position/fen/games?fen=...&yearFrom=2020&yearTo=2024
```

---

## Differences vs. `/api/game-position/games` (explorer)

If you previously hit `/api/game-position/games` and want broader coverage:

- **Drop the ply assumption.** Explorer endpoint requires the queried FEN's fullmove counter to match the ply the position was reached at in the indexed table. FEN endpoint ignores the counter.
- **No `moves` array.** The explorer accepts a `moves` array to derive an effective FEN by replaying moves from a starting position. The FEN endpoint uses the FEN as the lookup key directly.
- **Same response shape.** Drop-in compatible for your row renderer.
- **Same filter & sort surface.** All filters and sort fields available on the explorer's `postGamesQuery` are now available here, except `moves`.
