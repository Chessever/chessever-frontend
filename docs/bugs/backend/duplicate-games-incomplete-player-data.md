# Bug Report: Duplicate Games with Incomplete Player Data

**Date:** 2026-01-06
**Reported by:** Frontend Team
**Severity:** Medium
**Affected Event:** 30. Open Bosnjaci, Croatia (and potentially others)

---

## Summary

When fetching games for certain tournaments, the API returns duplicate game entries with the same `game_id` but different data quality. Some entries have complete player data (rating, federation, title) while others have incomplete data (rating=0, empty federation).

---

## Observed Behavior

When viewing a player's scorecard in the "30. Open Bosnjaci, Croatia" event, the following was observed:

| Round | Opponent | Rating | Flag | Issue |
|-------|----------|--------|------|-------|
| 1 | Mesar, Darko | 1893 | ✅ CRO | OK |
| 2 | Mesar, Darko | 0 | ❌ None | **Duplicate with incomplete data** |
| 3 | Mesar, Darko | 0 | ❌ None | **Duplicate with incomplete data** |
| 4 | Mesar, Darko | 0 | ❌ None | **Duplicate with incomplete data** |
| 5 | WIM Saric, Kristina | 2115 | ✅ CRO | OK |
| 6 | FM Ghersinich, Enrico | 2244 | ✅ ITA | OK |
| 7 | Ghersinich, Enrico | 0 | ❌ None | **Duplicate with incomplete data** |
| 8 | FM Safar, Sandro | 2322 | ✅ CRO | OK |

The same opponent appears multiple times with:
- Some entries having correct rating (e.g., 1893) and federation code (e.g., "CRO")
- Other entries having rating=0 and empty federation

---

## Expected Behavior

Each game should appear **exactly once** in the API response with complete player data:
- `players[].rating` should contain the actual player rating (not 0)
- `players[].fed` should contain the federation code (e.g., "CRO", "ITA")
- `players[].title` should contain the title if applicable (e.g., "FM", "WIM")
- `players[].fideId` should contain the FIDE ID if available

---

## Data Structure Reference

Games are fetched with this structure:
```json
{
  "id": "game_id",
  "round_id": "round_id",
  "round_slug": "round-1",
  "tour_id": "tour_id",
  "players": [
    {
      "name": "Surname, FirstName",
      "title": "GM",
      "rating": 2500,
      "fideId": 12345678,
      "fed": "CRO",
      "clock": 0,
      "team": ""
    },
    {
      "name": "Opponent, Name",
      "title": "FM",
      "rating": 2300,
      "fideId": 87654321,
      "fed": "ITA",
      "clock": 0,
      "team": ""
    }
  ]
}
```

---

## Potential Causes

1. **Multiple data sources being merged incorrectly**
   - Broadcast data and stored game data may be creating duplicate entries
   - One source has complete player info, another has partial info

2. **Race condition during data ingestion**
   - Game might be inserted before player data is fully resolved
   - Later update adds complete data but doesn't remove/merge with incomplete entry

3. **Round/game relationship issue**
   - Same game might be associated with multiple rounds incorrectly

---

## Questions for Backend

1. Is there a unique constraint on `game_id` in the games table?
2. Are games being upserted or inserted separately from multiple sources?
3. Is player data being enriched asynchronously after initial game creation?
4. Can you check the `games` table for this specific tournament (`tour_id` for "30. Open Bosnjaci, Croatia") to see if there are actual duplicates?

---

## Frontend Workaround Applied

We've added client-side deduplication in `ScoreCardScreen` that:
1. Groups games by `gameId`
2. When duplicates exist, keeps the entry with the most complete data
3. Scores entries based on: rating > 0, federation not empty, title not empty

**Location:** `lib/screens/standings/score_card_screen.dart:289-334`

This is a temporary fix. The root cause should be addressed in the backend to prevent duplicate/incomplete data from being returned.

---

## How to Reproduce

1. Open the app
2. Navigate to "30. Open Bosnjaci, Croatia" tournament
3. Open any game
4. Tap on a player name to view their scorecard
5. Observe duplicate entries with rating=0 and missing flags

---

## Additional Notes

- This issue may affect other tournaments as well
- The deduplication logic adds overhead on the client side
- Incomplete player data affects performance rating calculations and display quality
