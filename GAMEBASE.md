# Gamebase Database Reference

The TWIC Database ("Gamebase") is a self-hosted Supabase PostgreSQL database powering the Library's game search. Backend lives at `/projects/chessever_gamebase`.

## Database Schema

### `player` table
| Column | Type | Notes |
|--------|------|-------|
| id | TEXT (UUID) | Primary key |
| name | TEXT | "Carlsen, Magnus" |
| gender | player_gender | MALE / FEMALE |
| fide_id | TEXT | UNIQUE — FIDE ID as string |
| title | TEXT? | GM, IM, FM, CM, WGM, WIM, WFM, WCM |
| fed | TEXT | FIDE country **name** ("Norway", not "NOR") |
| rating_classical | INTEGER? | |
| rating_rapid | INTEGER? | |
| rating_blitz | INTEGER? | |

### `game` table (millions of rows)
| Column | Type | Notes |
|--------|------|-------|
| id | TEXT (UUID) | Primary key |
| data | JSONB | Full game (PGN headers + moves in `data->'md'`) |
| white_player_id | TEXT? | FK → player.id |
| black_player_id | TEXT? | FK → player.id |
| eco | TEXT? | Denormalized from `data->'md'->'ECO'` |
| opening | TEXT? | Denormalized |
| variation | TEXT? | Denormalized |
| event | TEXT? | Tournament name |
| site | TEXT? | Venue |
| white_name / black_name | TEXT? | Denormalized player names |
| white_fide_id / black_fide_id | TEXT? | Denormalized |
| white_elo / black_elo | INTEGER? | Denormalized |
| white_fed / black_fed | TEXT? | FIDE country **names** |
| search_tsv | TSVECTOR? | Weighted full-text search |
| date | TIMESTAMP? | Game date |
| time_control | game_time_control | CLASSICAL / RAPID / BLITZ |
| result | game_result | W / B / D |

> Denormalized columns are auto-populated by the `game_set_search_columns()` trigger on INSERT/UPDATE of `data`.

### `game_position` table (hundreds of millions, partitioned)
| Column | Type | Notes |
|--------|------|-------|
| id | TEXT | Game ID |
| move_number | INTEGER | Ply (1-based) |
| fen | TEXT | Full FEN |
| next_move_uci | TEXT | UCI notation |
| player_id | TEXT? | FK → player (side to move) |
| rating | INTEGER | Player's rating |
| result | game_result | W / B / D |
| time_control | game_time_control | |

PK: (id, move_number). Range-partitioned by move_number (partitions for moves 1-21, then rest).

### Enums
- **game_result**: `W` (white wins), `B` (black wins), `D` (draw)
- **game_time_control**: `CLASSICAL`, `RAPID`, `BLITZ`
- **player_gender**: `MALE`, `FEMALE`

## API Endpoints

All require `X-API-Key` header.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/search` | Global search (games + players) with field tokens |
| GET | `/api/player` | Search players by name |
| GET | `/api/player/{id}` | Player by gamebase UUID |
| GET | `/api/player/{id}/games` | Player's games with filters |
| GET | `/api/game/{id}` | Game by ID (?includePgn for PGN) |
| GET | `/api/game-position/aggregates` | Opening explorer position stats |
| POST | `/api/search/query` | Advanced structured query |

### Search Preview Fields (from `GET /api/search`)
The `preview` object on game results contains:
```
whitePlayerId, blackPlayerId    — gamebase UUIDs (not FIDE IDs)
white, black                    — player names
whiteElo, blackElo              — ratings
whiteFed, blackFed              — FIDE country names
whiteTitle, blackTitle          — titles (GM, IM, etc.) — may be absent
eco, opening, variation         — opening data
event, site, date, result       — game metadata
timeControl                     — CLASSICAL/RAPID/BLITZ
```

## Key Relationships

```
Frontend PlayerCard.gamebasePlayerId  →  Gamebase player.id (UUID)
Gamebase player.fide_id               →  Supabase chess_players.fideid (integer)
```

To enrich a player: `getPlayerById(uuid)` → get `fide_id` → query `chess_players` for title + country.

## Important Notes

- `player.fed` stores FIDE country **names** (e.g. "Norway"), not ISO/FIDE codes
- `whiteTitle`/`blackTitle` in search preview come from `player.title` — absent for untitled players
- Gamebase player UUID is different from FIDE ID — must bridge through `player.fide_id`
- Only first ~21 plies indexed in `game_position` (opening explorer coverage)
- `game.data` JSONB holds the complete game; denormalized columns are for fast search only
