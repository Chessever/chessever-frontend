# Lichess PV Limit Issue - Fixed

## Problem Discovery

Your manager wanted to see more PVs than the 3 we were displaying. Investigation revealed we were **discarding PVs** that Lichess API returned!

## Root Cause

### What Was Happening:
1. ✅ User sets PV count to **5** in settings
2. ✅ Frontend requests **5 PVs** from Lichess API (`multiPvForLichess()`)
3. ✅ Lichess returns **5 PVs** in response
4. ❌ **We threw away PVs 4 & 5** due to hardcoded limit!

### The Culprit:
```dart
// chess_board_screen_provider_new.dart:28
const int _kMaxPrincipalVariations = 3;  // ❌ HARDCODED LIMIT

// chess_board_screen_provider_new.dart:3307
final pvsToShow = cloudEval.pvs.take(_kMaxPrincipalVariations).toList();  // ❌ ONLY TAKES 3
```

## Lichess API Limits (Verified)

According to [Lichess Cloud Eval API Documentation](https://lichess.org/api#tag/Opening-Explorer/operation/apiCloudEval):

| Parameter | Limit | Our Usage |
|-----------|-------|-----------|
| `multiPv` | **Max: 5** | ✅ Capped at 5 in `multiPvForLichess()` |
| Response | Returns up to 5 PVs | ✅ Now using all returned PVs |

### Test Results (from test_lichess_pvs.dart):
```
multiPv=1  → Returns 1 PV
multiPv=3  → Returns 3 PVs
multiPv=5  → Returns 5 PVs
multiPv=10 → Returns 5 PVs (capped by API)
multiPv=20 → Returns 5 PVs (capped by API)
```

## The Fix

### Changes Made:

1. **Removed hardcoded constant**:
   ```dart
   // REMOVED: const int _kMaxPrincipalVariations = 3;
   ```

2. **Use all returned PVs**:
   ```dart
   // Before:
   final pvsToShow = cloudEval.pvs.take(_kMaxPrincipalVariations).toList();
   
   // After:
   final pvsToShow = cloudEval.pvs;  // Use ALL PVs from response
   ```

### Impact:

| PV Setting | Before Fix | After Fix |
|------------|------------|-----------|
| 1 PV | Shows 1 ✅ | Shows 1 ✅ |
| 2 PVs | Shows 2 ✅ | Shows 2 ✅ |
| 3 PVs | Shows 3 ✅ | Shows 3 ✅ |
| 4 PVs | Shows 3 ❌ | Shows 4 ✅ |
| 5 PVs | Shows 3 ❌ | Shows 5 ✅ |

## User Perspective

### Before:
- User sets PV count to 5
- Only sees 3 PV cards (confused! 😕)
- Missing valuable engine analysis

### After:
- User sets PV count to 5
- Sees all 5 PV cards (happy! 😊)
- Gets full engine analysis as requested

## Complete Flow Now:

```
User Setting (1-5) 
    ↓
multiPvForLichess() caps at 5
    ↓
Request to Lichess API with multiPv=X
    ↓
Lichess returns up to X PVs (max 5)
    ↓
✅ Display ALL returned PVs (no longer limited to 3)
    ↓
User sees X PV cards with colored arrows
```

## Additional Notes

- **5 colors defined**: Green, Blue, Orange, Pink, Purple (for PVs 1-5)
- **Arrows display**: All 5 PVs show arrows on board with distinct colors
- **Settings migration**: Old "All" option converted to max setting of 5
- **Lichess rate limits**: Respected (8s timeout, sequential requests in cascade)

## Files Modified

1. `/lib/screens/chessboard/provider/chess_board_screen_provider_new.dart`
   - Removed `_kMaxPrincipalVariations` constant
   - Changed to use all PVs from cloud eval response

## Testing

Run the test script:
```bash
dart test_lichess_pvs.dart
```

This will verify:
- How many PVs Lichess returns for different multiPv values
- Actual API behavior vs documentation
- Position-specific availability

## Conclusion

✅ **Fixed**: Users now get exactly as many PVs as they request (up to 5)  
✅ **No waste**: We use all PVs that Lichess provides  
✅ **Better UX**: Manager's request for more PVs is now satisfied!
