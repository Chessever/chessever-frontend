# Engine Depth & Lichess Rate Limit Issues - Analysis & Fixes

## 🚨 Critical Issues Found

### Issue 1: Depth 0 Bug (BROKEN!)

**Symptoms:**
```
✅ QUICK EVAL: Returning depth 0 result with 1 moves  // ❌ Should be depth 12!
✅ BACKGROUND UPGRADE: Cached depth 0 result with 1 moves  // ❌ Should be depth 20!
```

**Root Cause:**
Stockfish is returning immediately without analyzing, sending `bestmove` without any `info depth` lines.

**Possible Reasons:**
1. **Terminal position** (checkmate/stalemate) - But FEN shows active game
2. **Stockfish crashed/hung** - Engine not responding properly
3. **Queue issue** - Jobs being cancelled before completion
4. **Supabase duplicate key errors** - Background upgrades failing

**Fix Applied:**
Added critical error detection in `stockfish_singleton.dart`:
- Detect when depth=0 with PVs (set minimum depth to 1)
- Log comprehensive error info for debugging
- Track what was requested vs what was received

**What You Should See:**
```
❌ CRITICAL: Stockfish returned NO depth info for [FEN]
   Requested: depth 12
   PVs found: X
   Last UCI line: bestmove ...
```

### Issue 2: Lichess Rate Limiting (429)

**Symptoms:**
```
📡 Lichess: Response status 429
⚡ Lichess: Rate limited (429), falling back to Stockfish
⚠️ LICHESS: Rate limited, entering 2min cooldown
```

**Reality Check:**
Lichess rate limits are **REAL** and **NECESSARY**:

| Rate Limit | Value | Source |
|------------|-------|--------|
| **Cloud Eval API** | ~60 req/min | [Lichess Docs](https://lichess.org/api#tag/Opening-Explorer/operation/apiCloudEval) |
| **General API** | 200 req/min | Lichess Fair Use Policy |
| **Cooldown** | 2 minutes | Your app's safeguard |

**Why You're Hitting Limits:**

1. **Navigating through moves** - Each move triggers eval request
2. **5 PVs requested** - More work for Lichess API
3. **Multiple concurrent games** - PageView caching adjacent pages
4. **Background upgrades** - Multiple Stockfish requests when Lichess fails

**Current Safeguards:**

✅ 2-minute cooldown after 429  
✅ Sequential cascade (Local → Supabase → Lichess → Stockfish)  
✅ Local cache to avoid repeat requests  
✅ Supabase cache as middle layer  

**What Won't Work:**

❌ "Bypassing" rate limits → **API ban**  
❌ Removing cooldown → **More 429s, faster ban**  
❌ Parallel requests → **Hit limits even faster**  

## 🔧 Recommended Fixes

### Fix 1: Improve Stockfish Reliability

**Problem:** Depth 0 indicates Stockfish isn't analyzing

**Solution:** Investigate why Stockfish returns immediately:

```dart
// Add to stockfish_singleton.dart debug output
if (line.startsWith('info depth')) {
  print('📊 STOCKFISH INFO: $line');  // Log ALL info lines
}

// Check if engine is actually running
if (line.startsWith('readyok')) {
  print('✅ Engine confirmed ready');
}
```

**Action Items:**
1. Check if `go depth 12` command is actually sent
2. Verify engine responds with `info depth 1`, `info depth 2`, etc.
3. Look for engine crashes in system logs
4. Test with simpler positions first

### Fix 2: Optimize Request Flow

**Current Flow (INEFFICIENT):**
```
Move change → Clear cache → Request eval
  ↓
Lichess (if not in cooldown)
  ↓ (429)
Stockfish fallback (depth 12)
  ↓
Background upgrade (depth 20)
  ↓ (tries to save to Supabase)
ERROR: Duplicate key
```

**Optimized Flow:**
```
Move change → Check cache → Request eval
  ↓
Local cache (instant) ✅
  ↓ (miss)
Supabase (fast) ✅
  ↓ (miss)
Lichess (if available) or Stockfish
  ↓
Background upgrade ONLY if Stockfish was used
  ↓
Save to cache (deduplicate)
```

**Implementation:**

```dart
// In current_eval_provider.dart, add deduplication
final Set<String> _pendingSaves = {};

Future<void> _saveWithDedup(String fen, CloudEval eval) async {
  final key = '$fen-${eval.depth}-${eval.pvs.length}';
  if (_pendingSaves.contains(key)) {
    print('⏭️ Skipping duplicate save for $key');
    return;
  }
  
  _pendingSaves.add(key);
  try {
    await persist.call(fen, eval);
  } finally {
    _pendingSaves.remove(key);
  }
}
```

### Fix 3: Reduce Lichess Requests

**Add Request Debouncing:**

```dart
// Debounce rapid move changes
Timer? _evalDebouncer;

void requestEval(String fen) {
  _evalDebouncer?.cancel();
  _evalDebouncer = Timer(Duration(milliseconds: 300), () {
    _actuallyRequestEval(fen);  // Only request after 300ms of no changes
  });
}
```

**Better Caching Strategy:**

```dart
// Cache for 24 hours instead of forever
final cacheExpiry = Duration(hours: 24);

// Clean old cache entries
Future<void> cleanOldCache() async {
  final cutoff = DateTime.now().subtract(cacheExpiry);
  await local.removeOlderThan(cutoff);
}
```

### Fix 4: Smarter Cooldown

**Current:** 2-minute blanket cooldown  
**Better:** Exponential backoff

```dart
class _LichessRateLimitTracker {
  static int _consecutiveRateLimits = 0;
  static DateTime? _lastRateLimitTime;
  
  static Duration _calculateCooldown() {
    // Exponential backoff: 30s, 1m, 2m, 5m, 10m
    final backoffMinutes = [0.5, 1, 2, 5, 10];
    final index = _consecutiveRateLimits.clamp(0, backoffMinutes.length - 1);
    return Duration(minutes: backoffMinutes[index].toInt());
  }
  
  static void recordRateLimit() {
    _consecutiveRateLimits++;
    _lastRateLimitTime = DateTime.now();
    final cooldown = _calculateCooldown();
    print('⚠️ LICHESS: Rate limited (#$_consecutiveRateLimits), ${cooldown.inMinutes}min cooldown');
  }
  
  static void recordSuccess() {
    if (_consecutiveRateLimits > 0) {
      _consecutiveRateLimits--;  // Gradually reduce on success
    }
  }
}
```

## 📊 Engine Depth Search Status

**Question:** Is the "engine depth search" mechanism working?

**Answer:** **PARTIALLY** - Here's what's happening:

### Evaluation Gauge (✅ WORKING)

```dart
// In chess_board_screen_provider_new.dart:2590-2595
final searchDuration = effectiveEngineSettings.searchDurationFor(
  EngineComponent.evaluationGauge,  // Uses dynamic time-based search
);
final maxDepth = effectiveEngineSettings.maxDepthFor(
  EngineComponent.evaluationGauge,  // Max depth 99
);
```

This DOES use dynamic search with increasing depth!

### PV Cards (❌ FIXED DEPTH)

```dart
// In current_eval_provider.dart:250, 305
final sfEval = await StockfishSingleton().evaluatePosition(
  fen,
  depth: 12,  // ❌ HARDCODED - no dynamic search!
  multiPV: multiPV,
);

// Background:
depth: 20,  // ❌ HARDCODED - no dynamic search!
```

PV cards use **FIXED depths** (12 and 20), not dynamic search.

### To Enable Dynamic Depth for PVs:

```dart
// In current_eval_provider.dart
final engineSettings = ref.read(engineSettingsProviderNew).valueOrNull;
final searchDuration = engineSettings?.searchDurationFor(EngineComponent.cascadeEval);
final maxDepth = engineSettings?.maxDepthFor(EngineComponent.cascadeEval);

final sfEval = await StockfishSingleton().evaluatePosition(
  fen,
  searchDuration: searchDuration,  // Dynamic time-based search
  maxDepth: maxDepth,               // Max depth cap (45)
  multiPV: multiPV,
  isCurrentPosition: isCurrentPosition,
  onDepthUpdate: (depth, nodes) {
    // Update UI with increasing depth
    print('PV DEPTH UPDATE: depth=$depth, nodes=$nodes');
  },
);
```

## 🎯 Action Plan

### Immediate (Fix Depth 0 Bug)

1. ✅ Add depth 0 detection (DONE)
2. Run app and reproduce issue
3. Check new error logs for root cause
4. Fix Supabase duplicate key errors

### Short Term (Reduce Rate Limits)

1. Add request deduplication
2. Implement debouncing for move changes
3. Improve cache hit rate
4. Add exponential backoff

### Long Term (Optimize Performance)

1. Enable dynamic depth for PV cards
2. Implement proper cache expiry
3. Add request batching
4. Consider self-hosted Stockfish API

## 📝 Testing Commands

```bash
# Run with verbose logging
flutter run --release --verbose

# Watch for depth issues
flutter run 2>&1 | grep "depth 0"

# Monitor Lichess requests
flutter run 2>&1 | grep "Lichess:"

# Track rate limits
flutter run 2>&1 | grep "429\|Rate limited"
```

## 🚫 What NOT To Do

❌ Remove rate limit cooldown → Will get API banned  
❌ "Bypass" Lichess limits → Against ToS, will be blocked  
❌ Parallel Lichess requests → Hits limits faster  
❌ Ignore depth 0 bug → Users see wrong evaluations  

## ✅ What TO Do

✅ Fix Stockfish depth 0 bug (root cause)  
✅ Improve caching (reduce requests)  
✅ Add deduplication (prevent waste)  
✅ Use exponential backoff (smarter recovery)  
✅ Monitor logs (understand behavior)  

---

**Bottom Line:**  
- Depth 0 is a BUG that needs fixing  
- Lichess rate limits are REAL and must be respected  
- Optimize by caching better, not bypassing limits  
- Dynamic depth search works for eval gauge, not for PV cards (yet)
