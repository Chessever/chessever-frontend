# Gamebase Documentation

## Overview

Gamebase is a chess game database service containing hundreds of thousands of professional chess games. It provides APIs for querying move statistics, player information, and game data. The backend is built with **Hono.js** (TypeScript) and uses **PostgreSQL** with **Prisma ORM**.

**Production URL:** `https://service.chessever.com`

---

## Authentication

All API requests require an API key passed in the `X-API-Key` header:

```
X-API-Key: <your-api-key>
```

The API key is configured via the `CLIENT_API_KEY` environment variable on the backend.

---

## Data Models

### Player

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Internal player identifier |
| `fideId` | String | FIDE player ID |
| `name` | String | Player name (format: "LastName, FirstName") |
| `gender` | Enum | `MALE` or `FEMALE` |
| `fed` | String | Country federation code (e.g., "NOR", "USA") |
| `title` | String? | Chess title (e.g., "GM", "IM", "FM") |
| `ratingClassical` | Int? | Classical rating |
| `ratingRapid` | Int? | Rapid rating |
| `ratingBlitz` | Int? | Blitz rating |

### Game

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Game identifier |
| `date` | DateTime | Date game was played |
| `result` | Enum | `W` (white wins), `B` (black wins), `D` (draw) |
| `timeControl` | Enum | `CLASSICAL`, `RAPID`, or `BLITZ` |
| `whitePlayerId` | UUID? | White player's ID |
| `blackPlayerId` | UUID? | Black player's ID |
| `data` | JSON | Full game data including moves and metadata |

### GamePosition

The `GamePosition` model stores each position that occurred in games, enabling efficient position-based queries:

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Position record identifier |
| `gameId` | UUID | Reference to the game |
| `moveNumber` | Int | Move number in the game |
| `fen` | String | FEN notation of the position |
| `nextMoveUci` | String | The move played (UCI notation, e.g., "e2e4") |
| `playerId` | UUID? | Player who made the move |
| `rating` | Int? | Player's rating at the time |
| `result` | Enum | Game result from this player's perspective |
| `timeControl` | Enum | Time control of the game |

**Note:** The `fen` field is indexed for fast position lookups.

### MoveAggregate (API Response)

Aggregated statistics for moves played from a given position:

| Field | Type | Description |
|-------|------|-------------|
| `uci` | String | Move in UCI notation |
| `white` | Int | Number of games won by white |
| `black` | Int | Number of games won by black |
| `draws` | Int | Number of draws |
| `total` | Int | Total games with this move |
| `gameId` | String? | Only present when `total === 1` |

---

## API Endpoints

### 1. Get Position Aggregates

Get move statistics for a given chess position.

```
GET /api/game-position/aggregates
```

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `fen` | String | Yes | FEN notation of the position |
| `playerId` | UUID | No | Filter by specific player |
| `timeControl` | Enum | No | `CLASSICAL`, `RAPID`, or `BLITZ` |
| `minRating` | Int | No | Minimum player rating filter |
| `maxRating` | Int | No | Maximum player rating filter |

**Example Request:**
```
GET /api/game-position/aggregates?fen=rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR%20b%20KQkq%20-%200%201&minRating=2500
```

**Response Format:**
```json
{
  "status": "success",
  "data": {
    "moves": [
      {
        "uci": "c7c5",
        "white": 12500,
        "black": 8200,
        "draws": 9300,
        "total": 30000
      },
      {
        "uci": "e7e5",
        "white": 8000,
        "black": 5500,
        "draws": 6500,
        "total": 20000
      }
    ]
  }
}
```

### 2. Search Players

Search for players by name or FIDE ID.

```
GET /api/player
```

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | String | No | Player name search |
| `fideId` | String | No | FIDE ID search |
| `pageNumber` | Int | No | Page number (default: 1) |
| `pageSize` | Int | No | Results per page (default: 20) |

**Example Request:**
```
GET /api/player?name=Carlsen&pageNumber=1&pageSize=10
```

**Response Format:**
```json
{
  "status": "success",
  "data": [
    {
      "id": "uuid-here",
      "fideId": "1503014",
      "name": "Carlsen, Magnus",
      "gender": "MALE",
      "fed": "NOR",
      "title": "GM",
      "ratingClassical": 2830,
      "ratingRapid": 2823,
      "ratingBlitz": 2886
    }
  ],
  "metadata": {
    "pageNumber": 1,
    "pageSize": 10
  }
}
```

### 3. Get Player by ID

Get a specific player's details.

```
GET /api/player/:id
```

**Response Format:**
```json
{
  "status": "success",
  "data": {
    "id": "uuid-here",
    "fideId": "1503014",
    "name": "Carlsen, Magnus",
    "gender": "MALE",
    "fed": "NOR",
    "title": "GM",
    "ratingClassical": 2830,
    "ratingRapid": 2823,
    "ratingBlitz": 2886
  }
}
```

### 4. Get Game by ID

Get a specific game's details.

```
GET /api/game/:id
```

**Response Format:**
```json
{
  "status": "success",
  "data": {
    "id": "uuid-here",
    "date": "2024-01-15T00:00:00.000Z",
    "result": "W",
    "timeControl": "CLASSICAL",
    "whitePlayerId": "uuid-white",
    "blackPlayerId": "uuid-black",
    "data": {
      "moves": "1. e4 e5 2. Nf3 ...",
      "event": "Tournament Name",
      "site": "Location"
    }
  }
}
```

---

## Chess Notation Reference

### FEN (Forsyth–Edwards Notation)

FEN encodes a chess position in a single string. Example starting position:
```
rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
```

Components:
1. Piece placement (from rank 8 to 1)
2. Active color (`w` = white, `b` = black)
3. Castling availability (`KQkq` or `-`)
4. En passant target square (or `-`)
5. Halfmove clock
6. Fullmove number

**Important:** URL-encode the FEN when passing as query parameter (spaces become `%20`).

### UCI (Universal Chess Interface) Notation

UCI notation represents moves as `<from><to>[promotion]`:
- `e2e4` - pawn from e2 to e4
- `g1f3` - knight from g1 to f3
- `e7e8q` - pawn promotion to queen

---

## Error Handling

### HTTP Status Codes

| Status | Description |
|--------|-------------|
| 200 | Success |
| 400 | Bad Request (invalid parameters) |
| 401 | Unauthorized (missing/invalid API key) |
| 404 | Not Found (resource doesn't exist) |
| 500 | Internal Server Error |

### Error Response Format

```json
{
  "status": "error",
  "message": "Description of the error"
}
```

---

## Frontend Integration Notes

### Current Discrepancies (NEEDS FIXING)

The current frontend implementation (`gamebase_repository.dart`) has parameter naming mismatches with the backend:

| Frontend (Current) | Backend (Correct) | Fix Required |
|--------------------|-------------------|--------------|
| `time_controls` (plural, comma-separated) | `timeControl` (singular enum) | Change to singular |
| `player_ids` (plural, comma-separated) | `playerId` (singular UUID) | Change to singular |
| `limit` / `offset` | `pageNumber` / `pageSize` | Change pagination params |
| Expects raw array response | Returns `{ status, data }` wrapper | Parse response wrapper |

### Required Repository Changes

```dart
// Current (INCORRECT):
queryParams['time_controls'] = timeControls.map((tc) => tc.name.toUpperCase()).join(',');
queryParams['player_ids'] = playerIds.join(',');

// Should be (CORRECT):
if (timeControl != null) {
  queryParams['timeControl'] = timeControl.name.toUpperCase();
}
if (playerId != null) {
  queryParams['playerId'] = playerId;
}
```

### Response Parsing

```dart
// Current (expects raw array):
final List<dynamic> data = json.decode(response.body);

// Should be (parse wrapper):
final Map<String, dynamic> responseBody = json.decode(response.body);
final List<dynamic> data = responseBody['data']['moves'];
```

---

## Architecture Diagram

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Flutter App    │────▶│  Gamebase API    │────▶│  PostgreSQL     │
│  (Frontend)     │     │  (Hono.js)       │     │  (Prisma ORM)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │
                              ▼
                        ┌──────────────────┐
                        │  chess.js        │
                        │  (FEN validation)│
                        └──────────────────┘
```

---

## Usage Examples

### Query Opening Statistics

To get statistics for the Sicilian Defense (after 1.e4 c5):

```dart
final aggregates = await repository.getPositionAggregates(
  fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2',
  minRating: 2500,
  timeControl: TimeControl.classical,
);

for (final move in aggregates) {
  print('${move.uci}: ${move.total} games, '
        'White: ${move.whiteWinPercent}, '
        'Draw: ${move.drawPercent}, '
        'Black: ${move.blackWinPercent}');
}
```

### Search for a Grandmaster

```dart
final players = await repository.getPlayers(
  name: 'Carlsen',
  pageNumber: 1,
  pageSize: 10,
);

for (final player in players) {
  print('${player.titleAndName} (${player.fed}) - Rating: ${player.highestRating}');
}
```

---

## Backend Technology Stack

- **Runtime:** Node.js
- **Framework:** Hono.js (TypeScript)
- **ORM:** Prisma
- **Database:** PostgreSQL
- **Validation:** Zod with @hono/zod-validator
- **Chess Logic:** chess.js (FEN validation)
- **Deployment:** Coolify on DigitalOcean Droplet

---

## Related Files

- Repository: `lib/screens/gamebase/repository/gamebase_repository.dart`
- Models: `lib/screens/gamebase/models/`
  - `gamebase_game.dart` - Game model with TimeControl and GameResult enums
  - `gamebase_player.dart` - Player model
  - `move_aggregate.dart` - Move statistics model
- Backend Source: https://github.com/Chessever/gamebase
