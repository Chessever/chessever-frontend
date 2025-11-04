# Dynamic Engine Depth Search - Testing Guide

## 🎯 What Should Happen

When you change engine settings, the system should:
1. ✅ Save settings to Supabase immediately
2. ✅ Cache settings locally to SharedPreferences
3. ✅ Clear all evaluation caches
4. ✅ Force re-evaluation with new parameters
5. ✅ Show live depth updates under computer icon
6. ✅ Use dynamic time-based search (not fixed depth)

## 📊 Complete Log Flow

### 1. When You Change Settings (e.g., Search Time to 10s)

```
🎛️  Settings UI: Search time changed to index=1 (10s)
🔧 EngineSettings: Search time changed to 10s
🧠 DepthTracker: cleared all (settings changed)
[EngineSettings] ✅ Saved to Supabase
[EngineSettings] Cached settings locally
```

### 2. When Chess Board Provider Detects Settings Change

```
🔄 ═══ ENGINE SETTINGS CHANGED ═══
   Previous: searchTime=5s
   New: searchTime=10s
   SearchDuration: 10s
   MaxDepth: 30
🗑️  Cleared evaluation cache (3 items removed)
   → Forcing re-evaluation...
```

### 3. When Stockfish Evaluation Starts

```
🎯 ═══ STARTING STOCKFISH EVALUATION ═══
   FEN: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR...
   Reason: Need eval + Need more PVs (have 0/3)
   Settings loaded: true
   SearchDuration: 10s (DYNAMIC)
   MaxDepth: 30
   Fallback depth: 15
```

### 4. When Stockfish Runs (Dynamic Search)

```
🔍 STOCKFISH: Analyzing fen (dynamic 10s)
   → Sending: MultiPV 3, movetime 10000ms, depth 30
⚡ STOCKFISH UCI: depth=12 knodes=45k
💡 EVAL: Depth update callback -> depth=12 knodes=45k
🧠 DepthTracker: EvaluationGauge depth=12 knodes=45 [evaluating position]
📊 BottomNav: Displaying depth=D:12 (45k nodes)
⚡ STOCKFISH UCI: depth=15 knodes=89k
💡 EVAL: Depth update callback -> depth=15 knodes=89k
🧠 DepthTracker: EvaluationGauge depth=15 knodes=89
📊 BottomNav: Displaying depth=D:15 (89k nodes)
⚡ STOCKFISH UCI: depth=18 knodes=156k
💡 EVAL: Depth update callback -> depth=18 knodes=156k
🧠 DepthTracker: EvaluationGauge depth=18 knodes=156
📊 BottomNav: Displaying depth=D:18 (156k nodes)
🎯 EVAL: Stockfish completed, isCancelled=false, pvs.length=3
```

### 5. What You Should See On Screen

**Under the Computer Icon (Laptop Button):**
- Text showing: **D:12** → **D:15** → **D:18** → **D:20** (updating in real-time)
- Text in semi-transparent white
- Only visible when engine analysis is enabled
- Updates every time depth increases

## 🧪 Step-by-Step Test

### Test 1: Settings Save & Sync

1. **Open Board Settings:**
   - Tap 3-dot menu → "Board Settings"
   - OR long-press computer icon

2. **Change Search Time:**
   - Move slider to "10s"
   - **Expected Logs:**
     - `🎛️  Settings UI: Search time changed to index=1 (10s)`
     - `🔧 EngineSettings: Search time changed to 10s`
     - `[EngineSettings] ✅ Saved to Supabase`

3. **Verify Persistence:**
   - Close app completely
   - Reopen app
   - Open Board Settings again
   - **Expected:** Slider still at "10s"

### Test 2: Immediate Effect

1. **Open a game with engine analysis ON**

2. **Change Search Time to 20s**

3. **Expected Logs (within 1 second):**
   ```
   🔄 ═══ ENGINE SETTINGS CHANGED ═══
   🗑️  Cleared evaluation cache
   🎯 ═══ STARTING STOCKFISH EVALUATION ═══
      SearchDuration: 20s (DYNAMIC)
   🔍 STOCKFISH: Analyzing fen (dynamic 20s)
   ```

4. **Move to a different position**

5. **Watch depth display under computer icon**
   - Should show: D:12 → D:15 → D:18 → D:20 → D:22...
   - Updates should happen smoothly every few seconds
   - Search should run for ~20 seconds total

### Test 3: Dynamic vs Static Search

**With Settings = "∞" (Infinite):**
```
SearchDuration: null (STATIC)
→ Sending: MultiPV 3, depth 15
```
- Uses fixed depth 15
- Completes in ~2-5 seconds
- No live depth updates

**With Settings = "10s":**
```
SearchDuration: 10s (DYNAMIC)
→ Sending: MultiPV 3, movetime 10000ms, depth 30
```
- Searches for 10 seconds
- Progressive depth: 12 → 15 → 18 → 20 → 22...
- Live depth updates under computer icon

## ⚠️ Common Issues & Solutions

### Issue: No depth displayed under computer icon

**Check:**
- Is engine analysis enabled? (computer icon should be highlighted)
- Are you seeing `📊 BottomNav: Displaying depth=D:XX` in logs?
- Move to a new position to trigger fresh evaluation

**Fix:** Enable engine analysis by tapping the computer icon

### Issue: Settings not persisting

**Check Logs For:**
- `[EngineSettings] ❌ Error saving to Supabase`
- `PostgrestException: duplicate key`

**Fix:**
- Verify Supabase table exists with unique constraint on `user_id`
- Check you're logged in (settings require authentication)

### Issue: Depth not updating / stuck

**Check:**
- Evaluation might be using cached result
- Force new evaluation by moving to different position
- Check for: `📦 CACHE HIT` in logs (means using cache)

**Fix:**
- Change settings → cache auto-clears
- OR close/reopen app

### Issue: No dynamic search happening

**Check Logs:**
- Should see: `SearchDuration: Xs (DYNAMIC)`
- Should see: `movetime X000ms` in UCI command
- If you see `depth 15` only → settings not loaded

**Fix:**
- Ensure `engineSettingsProviderNew` is loaded
- Check: `Settings loaded: true` in logs
- Try changing settings to force reload

## 📋 Supabase Table Structure

Your `user_engine_settings` table should have:

```sql
CREATE TABLE user_engine_settings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) UNIQUE NOT NULL,
  show_engine_gauge BOOLEAN DEFAULT true,
  show_depth_overlay BOOLEAN DEFAULT true,
  show_pv_arrows BOOLEAN DEFAULT true,
  search_time_index INTEGER DEFAULT 0,
  principal_variation_count INTEGER DEFAULT 3,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE user_engine_settings ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own settings
CREATE POLICY "Users can view own settings"
  ON user_engine_settings FOR SELECT
  USING (auth.uid() = user_id);

-- Policy: Users can insert/update their own settings
CREATE POLICY "Users can manage own settings"
  ON user_engine_settings FOR ALL
  USING (auth.uid() = user_id);
```

## ✅ Success Criteria

Your dynamic engine depth search is working correctly if you see:

1. ✅ Settings slider changes reflected immediately
2. ✅ Logs show `SearchDuration: Xs (DYNAMIC)`
3. ✅ Logs show `movetime X000ms` in UCI command
4. ✅ Depth number appears under computer icon
5. ✅ Depth updates progressively: D:12 → D:15 → D:18...
6. ✅ Settings persist after app restart
7. ✅ Cache clears when settings change
8. ✅ Evaluation uses new parameters immediately

## 🔧 Quick Debug Commands

**Check if settings provider is loaded:**
```dart
final settings = ref.read(engineSettingsProviderNew);
debugPrint('Settings: ${settings.value?.searchTimeLabel()}');
```

**Force clear all caches:**
```dart
ref.read(engineDepthTrackerProvider.notifier).clearAll();
// Then move to new position
```

**Manually trigger evaluation:**
```dart
_evaluatePosition(force: true);
```
