# Fix: PV Cards Showing Wrong Count (3 instead of 5)

## Problem
PV cards sometimes showed only 3 variations even though user selected 5 in settings. This happened because cache keys didn't include the multiPV count, so a cached 3-PV result would be returned when requesting 5 PVs.

## Root Cause
Three cache systems had the same bug:
1. **Local memory cache** (`_pvCache`, `_evaluationCache` in chess_board_screen_provider_new.dart)
2. **SharedPreferences cache** (local_eval_cache.dart)
3. **Supabase cache** (evals table)

All used FEN-only as cache key: `rnbqkbnr/pppppppp/8 w KQkq -`

This meant:
- Evaluate position with 3 PVs → cached as `rnbqkbnr...`
- User changes setting to 5 PVs
- Re-evaluate same position → returns cached 3-PV result ❌

## Solution Applied

### 1. Updated Cache Keys (Include MultiPV Count)
**New cache key format:** `rnbqkbnr/pppppppp/8 w KQkq -_pv5`

- `_fenCacheKey()` now accepts `multiPV` parameter
- Keys include PV count: `${baseFen}_pv${multiPV}`
- Separate cache entries for different PV counts (3 vs 5)

### 2. Updated Files
```dart
// chess_board_screen_provider_new.dart
String _fenCacheKey(String fen, {int? multiPV}) {
  final baseFen = ...;
  if (multiPV != null && multiPV > 0) {
    return '${baseFen}_pv$multiPV'; // ← Include PV count
  }
  return baseFen;
}

// local_eval_cache.dart
Future<void> save(String fen, CloudEval eval, {int? multiPV}) // ← New param
Future<CloudEval?> fetch(String fen, {int? multiPV})         // ← New param
```

### 3. Bumped Cache Versions (Auto-clear old caches)
- **SharedPreferences**: v5 → v6
- **main.dart `_clearEvaluationCache()`**: v5 → v6

Old caches without multiPV in keys will be automatically cleared on next app launch.

---

## Action Required: Clear Supabase Cache

### Option A: Clear All Evals (Recommended)
Run this SQL in your Supabase SQL Editor:

```sql
-- DANGER: This deletes ALL evaluation data
-- Run only once to clear old cache without multiPV tracking
DELETE FROM evals;

-- Optional: Confirm deletion
SELECT COUNT(*) FROM evals; -- Should return 0
```

### Option B: Selective Clear (If you want to keep some data)
If your Supabase evals table has many entries and you only want to clear duplicates:

```sql
-- Find positions with multiple depth entries (likely different PV counts)
SELECT position_id, COUNT(*) as count
FROM evals
GROUP BY position_id
HAVING COUNT(*) > 1;

-- Delete all but the highest depth for each position
-- (Keep the best quality eval, user will re-fetch with correct PV count)
DELETE FROM evals
WHERE id NOT IN (
  SELECT MAX(id)
  FROM evals
  GROUP BY position_id
);
```

### Option C: Add multiPV column (Future-proof)
If you want to track multiPV in Supabase for debugging:

```sql
-- Add column to track multiPV count
ALTER TABLE evals ADD COLUMN multi_pv INTEGER;

-- Optional: Set default for existing rows (guess based on pvs array length)
UPDATE evals
SET multi_pv = jsonb_array_length(pvs::jsonb)
WHERE multi_pv IS NULL;

-- Optional: Create index for faster lookups
CREATE INDEX idx_evals_position_multipv ON evals(position_id, multi_pv);
```

Then update `evals.dart` model to include `multiPv` field (optional enhancement).

---

## Testing
1. **Clear all caches** (SQL + app restart clears SharedPreferences)
2. **Select 3 PVs** in settings
3. **Navigate to a position** → Should show 3 PV cards
4. **Check logs:** `⚡ CACHE HIT: ... (eval=X, 3 PVs)` or fresh fetch
5. **Change to 5 PVs** in settings
6. **Navigate to SAME position** → Should fetch fresh and show 5 PV cards (not cached 3)
7. **Navigate away and back** → Should see cache hit with 5 PVs

---

## Expected Logs

### First evaluation (3 PVs selected):
```
🎯 EVAL START: Evaluating position rnbqkbnr... (requesting 3 PVs)
🎯 QUICK EVAL: Built 3 PV lines from 3 raw PVs
🎯 QUICK PHASE: Applied 3 PVs to state (isEvaluating=false)
```

### Cache hit (same settings):
```
⚡ CACHE HIT: Instant display for rnbqkbnr... (eval=0.2, 3 PVs)
```

### After changing to 5 PVs (no cache hit, fresh fetch):
```
🎯 EVAL START: Evaluating position rnbqkbnr... (requesting 5 PVs)
🎯 QUICK EVAL: Built 5 PV lines from 5 raw PVs
🎯 QUICK PHASE: Applied 5 PVs to state (isEvaluating=false)
```

### Second visit (5 PVs, cache hit):
```
⚡ CACHE HIT: Instant display for rnbqkbnr... (eval=0.2, 5 PVs)
```

---

## Summary of Changes

| File | Change | Version |
|------|--------|---------|
| `chess_board_screen_provider_new.dart` | Include `multiPV` in `_fenCacheKey()` | - |
| `local_eval_cache.dart` | Add `multiPV` param to `save()`/`fetch()` | v5 → v6 |
| `main.dart` | Bump `cacheVersion` to trigger clear | v5 → v6 |
| Supabase `evals` table | **Manual:** Run SQL to clear old data | - |

---

## Why This Matters
- **Correct PV count:** Users always see the number of variations they selected
- **Better UX:** No confusion from seeing wrong number of lines
- **Cache efficiency:** Different PV counts don't collide
- **Future-proof:** Supports dynamic PV count changes without cache issues
