# Player Titles Not Displaying in Games

## Problem

Player titles (GM, IM, FM, etc.) are not showing in the game cards and chessboard screen, even though titles are correctly stored in the database.

## Root Cause

The `games.players` JSONB column does not contain the `title` field, but `tours.players` does.

### Data Structure Comparison

**tours.players** (has titles):
```json
[
  {
    "name": "Carlsen, Magnus",
    "fideId": 1503014,
    "title": "GM",
    "rating": 2830,
    "fed": "NOR"
  }
]
```

**games.players** (missing titles):
```json
[
  {
    "name": "Carlsen, Magnus",
    "fideId": 1503014,
    "title": "",
    "rating": 2830,
    "fed": "NOR"
  }
]
```

The `title` field exists in `games.players` but is empty string `""` instead of the actual title.

## Solution: One-Time Backfill Migration

Run this SQL to backfill existing games with player titles from their parent tournament:

```sql
-- Backfill player titles from tours.players into games.players
-- This is a ONE-TIME migration, not a trigger

UPDATE games g
SET players = (
  SELECT jsonb_agg(
    CASE
      WHEN gp->>'title' IS NULL OR gp->>'title' = '' THEN
        gp || jsonb_build_object(
          'title',
          COALESCE(
            (
              SELECT tp->>'title'
              FROM tours t,
                   jsonb_array_elements(t.players) AS tp
              WHERE t.id = g.tour_id
                AND tp->>'title' IS NOT NULL
                AND tp->>'title' != ''
                AND (
                  -- Match by fideId first (most reliable)
                  (
                    (gp->>'fideId')::int > 0
                    AND (tp->>'fideId')::int = (gp->>'fideId')::int
                  )
                  OR
                  -- Fallback to name match
                  (tp->>'name' = gp->>'name')
                )
              LIMIT 1
            ),
            ''
          )
        )
      ELSE gp
    END
  )
  FROM jsonb_array_elements(g.players) AS gp
)
WHERE EXISTS (
  SELECT 1
  FROM jsonb_array_elements(g.players) AS gp
  WHERE gp->>'title' IS NULL OR gp->>'title' = ''
);
```

### What This Does

1. Iterates through all games where at least one player has an empty/null title
2. For each player in the game, looks up their title from `tours.players` by:
   - First matching on `fideId` (most reliable)
   - Falling back to `name` match if no fideId
3. Updates the `games.players` JSONB with the enriched title

## Why NOT a Trigger?

We considered adding a trigger to automatically enrich titles on INSERT/UPDATE:

```sql
-- DO NOT USE THIS - Performance concern
CREATE OR REPLACE FUNCTION enrich_game_player_titles()
RETURNS TRIGGER AS $$
BEGIN
  -- ... enrichment logic
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enrich_titles_on_game_insert
  BEFORE INSERT OR UPDATE ON games
  FOR EACH ROW
  EXECUTE FUNCTION enrich_game_player_titles();
```

### Performance Concerns

1. **Query overhead on every game insert/update**: During live tournaments, games are updated frequently (every move). Adding a subquery to `tours.players` on every update adds latency.

2. **JSONB operations are expensive**: Parsing and rebuilding JSONB arrays on every write is CPU-intensive.

3. **Blocking writes**: Triggers run synchronously, blocking the original INSERT/UPDATE until complete.

4. **Scaling issues**: During major tournaments with 100+ boards, this could create a bottleneck.

## Recommended Approach

### Option A: Fix at Data Ingestion (Preferred)

Modify the backend service that creates/updates games to include the title when building the `players` JSONB:

```python
# Pseudo-code for backend
def create_game_player(player_data, tour_players):
    title = player_data.get('title', '')

    # If no title, look it up from tour_players
    if not title:
        for tp in tour_players:
            if tp['fideId'] == player_data['fideId']:
                title = tp.get('title', '')
                break

    return {
        'name': player_data['name'],
        'fideId': player_data['fideId'],
        'title': title,  # Now populated
        'rating': player_data['rating'],
        'fed': player_data['fed']
    }
```

This way:
- No database trigger overhead
- Title is set correctly from the start
- No need for backfill on new games

### Option B: Async Background Job

If Option A isn't feasible, run a periodic background job (e.g., every 5 minutes) that backfills missing titles for recently created/updated games. This avoids blocking writes.

## Verification Query

After running the migration, verify titles are populated:

```sql
-- Check games with missing titles
SELECT
  g.id,
  g.name,
  gp->>'name' as player_name,
  gp->>'title' as player_title
FROM games g,
     jsonb_array_elements(g.players) AS gp
WHERE gp->>'title' IS NULL OR gp->>'title' = ''
LIMIT 20;

-- Should return 0 rows after successful migration
```

## Summary

| Approach | Pros | Cons |
|----------|------|------|
| One-time backfill | Simple, no ongoing cost | Doesn't fix future games |
| Trigger | Automatic | Performance overhead on every write |
| Fix at ingestion | Best performance, correct by design | Requires backend change |
| Background job | Non-blocking | Slight delay in title appearing |

**Recommendation**: Run the one-time backfill SQL, then fix the data ingestion layer to include titles from the start.
