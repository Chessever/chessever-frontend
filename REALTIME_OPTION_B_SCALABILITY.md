# Supabase Realtime Scalability: Option B (Future Reference)

> **Status:** NOT IMPLEMENTED - Saved for future scalability needs
> **Current Implementation:** Option A (batched `onPostgresChanges` with `inFilter`)

---

## When to Implement Option B

Consider implementing Option B when you experience:
- **Thousands of concurrent users** watching the same live games
- Database CPU spikes during popular tournaments
- Latency increases in live game updates

**Option A handles thousands of GAMES fine.** Option B is for thousands of USERS.

---

## Scalability Comparison

| Metric | Option A (Current) | Option B (This Guide) |
|--------|-------------------|----------------------|
| Channels per 100 games | 1 | 1 |
| DB load per move | O(users) RLS checks | O(1) trigger |
| Concurrent user limit | ~500 | Thousands |
| Latency | ~50-100ms | ~10-30ms |

---

## Option B: Broadcast from Database

Instead of clients subscribing to Postgres Changes (which triggers RLS checks per user), a database trigger broadcasts changes once to all clients.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Backend: UPDATE games SET fen='...', pgn='...'             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  PostgreSQL TRIGGER fires (once)                            │
│  → realtime.broadcast_changes('games:{id}', ...)            │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Supabase Realtime: Fans out to ALL connected clients       │
│  → No per-user RLS checks                                   │
│  → Single broadcast, thousands of recipients                │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Steps

### Step 1: Create Database Migration

**File:** `chessever_data_hub_monorepo/supabase/migrations/YYYYMMDDHHMMSS_add_games_broadcast_trigger.sql`

```sql
-- Enable realtime broadcast for games table updates
-- More efficient than Postgres Changes for high user counts

CREATE OR REPLACE FUNCTION public.broadcast_game_update()
RETURNS TRIGGER
SECURITY DEFINER
AS $$
BEGIN
  PERFORM realtime.broadcast_changes(
    'games:' || NEW.id::text,    -- Topic/channel name
    TG_OP,                        -- 'INSERT' or 'UPDATE'
    TG_TABLE_NAME,                -- 'games'
    TG_TABLE_SCHEMA,              -- 'public'
    NEW,                          -- New row data
    OLD                           -- Old row data (null for INSERT)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER games_broadcast_trigger
AFTER INSERT OR UPDATE ON public.games
FOR EACH ROW
EXECUTE FUNCTION public.broadcast_game_update();

COMMENT ON FUNCTION public.broadcast_game_update() IS
  'Broadcasts game updates to Realtime for live streaming.';
```

### Step 2: Apply Migration

```bash
cd ~/projects/chessever_data_hub_monorepo
supabase db push
```

### Step 3: Update Frontend

**File:** `lib/repository/supabase/game/game_stream_repository.dart`

Change `SharedGameStreamManager._rebuildChannels()`:

```dart
// BEFORE (Option A - Postgres Changes)
final channel = _client
    .channel('shared-games-$timestamp-$batchIndex')
    .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'games',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.inFilter,
        column: 'id',
        value: batch,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        final gameId = newRecord['id'] as String?;
        // ... process update
      },
    )
    .subscribe();

// AFTER (Option B - Broadcast)
final channel = _client
    .channel('shared-games-$timestamp-$batchIndex')
    .onBroadcast(
      callback: (payload) {
        final newRecord = payload['new'] as Map<String, dynamic>?;
        if (newRecord == null) return;
        final gameId = newRecord['id'] as String?;
        // ... process update (same logic)
      },
    )
    .subscribe();
```

---

## Backward Compatibility

The broadcast trigger is **ADDITIVE**:
- Old app versions using `.stream()` → Still work (Postgres Changes still active)
- Current app using `onPostgresChanges` → Still work
- New app using `onBroadcast` → Works with trigger

All versions can coexist during migration period.

---

## Rollback

If issues occur, drop the trigger:

```sql
DROP TRIGGER IF EXISTS games_broadcast_trigger ON public.games;
DROP FUNCTION IF EXISTS public.broadcast_game_update();
```

Frontend automatically falls back to Postgres Changes (Option A).

---

## Backend Reference

**Repository:** `~/projects/chessever_data_hub_monorepo`

**Games table location:** `supabase/migrations/20250907143039_remote_schema.sql`

**Key columns for live updates:**
- `id` (text) - Primary key
- `fen` (text) - Current board position
- `pgn` (text) - Full game notation
- `status` (text) - "*", "1-0", "0-1", "1/2-1/2"
- `last_move` (text) - e.g., "e7e5"
- `players` (jsonb) - Player data with clock times

---

## Resources

- [Supabase Realtime Broadcast](https://supabase.com/docs/guides/realtime/broadcast)
- [Broadcast from Database](https://supabase.com/docs/guides/realtime/broadcast#broadcast-from-database)
- [realtime.broadcast_changes() function](https://supabase.com/docs/guides/realtime/broadcast#broadcast-from-database)

---

*Created: December 2024*
*For: Chessever Frontend scalability planning*
