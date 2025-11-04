# Knockout Tournament Match Display Implementation

## Overview

This implementation adds intelligent detection and improved display for knockout tournament formats where players face each other multiple times in matches (e.g., best-of-N series with tiebreaks).

## Problem Statement

In knockout tournaments like the FIDE World Cup, players don't play single games but compete in **matches** consisting of:
- 2+ classical games (e.g., Game 1, Game 2)
- Tiebreak games if needed (Rapid 1, Rapid 2, Blitz 1, Blitz 2, Armageddon)

The previous implementation displayed all games in a flat list, making it hard to:
1. Understand which games belong to the same match
2. See the current match score (e.g., 1.5 - 0.5)
3. Track multiple games between the same player pair

## Solution Architecture

### 1. Knockout Match Detection (`knockout_match_detector.dart`)

**Key Features:**
- Automatically detects knockout format by analyzing game patterns
- Groups games into matches (same player pairs)
- Calculates match scores
- Formats round names (e.g., "game-1" → "Game 1", "tiebreak-1-rapid-1" → "Tiebreak 1 - Rapid 1")

**Detection Algorithm:**
```dart
bool isKnockoutMatchFormat(List<GamesTourModel> games) {
  // 1. Check for game-N and tiebreak patterns in round slugs
  // 2. Check for repeated player matchups (multiple games between same players)
  // 3. Requires >30% pattern match and >50% multi-game matchups
}
```

**Example Data Structure:**

**Database Structure** (how games are stored):
```
Round t8DzIZPc (round_slug: "game-1") - All first games
├── Game: Adams vs Alrehaili - Game 1: 0-1
├── Game: Abasov vs Suyarov - Game 1: 1-0
└── ...

Round NUcmLDqC (round_slug: "game-2") - All second games
├── Game: Adams vs Alrehaili - Game 2: 1-0
└── ...

Round xyz (round_slug: "tiebreak-1-rapid-1") - Tiebreaks
└── ...
```

**Display Structure** (how we show to users - GROUPED BY MATCHES):
```
Tournament: Round 1 ⚫ 117 games in 78 matches
├── Match: Adams vs Alrehaili (Score: 2-0) ✓
│   ├── Game 1: 0-1 (from round t8DzIZPc)
│   └── Game 2: 1-0 (from round NUcmLDqC)
├── Match: Abasov vs Suyarov (Score: 1-0) ✓
│   └── Game 1: 1-0 (from round t8DzIZPc)
├── Match: Grandelius vs Damaj (Score: 1.5-0.5)
│   ├── Game 1: 1-0
│   ├── Game 2: ½-½
│   └── Tiebreak 1 - Rapid 1: ongoing
└── ... (75 more matches)
```

**Key Insight:** Games are stored by "game number" rounds in the database, but displayed by "match" (player pairs) to users!

### 2. Match Header Widget (`match_header_widget.dart`)

**Visual Design:**
```
┌─────────────────────────────────────────┐
│ │ Player1 vs Player2                    │
│ │ 1.5 - 0.5  │  3 games  │  Complete   │
└─────────────────────────────────────────┘
```

**Features:**
- Color-coded status indicator (green = complete, primary = ongoing)
- Live score display
- Game count
- Completion status badge
- Expandable/collapsible (optional)

### 3. Enhanced Games List View (`games_list_view.dart`)

**Structure:**
```
Before (Flat):
- Round 1
  - Game 1: Abasov vs Suyarov
  - Game 1: Adams vs Alrehaili
  - ...

After (Grouped):
- Game 1
  - Match: Abasov vs Suyarov (1-0)
    - Game 1: 1-0
  - Match: Adams vs Alrehaili (0-1)
    - Game 1: 0-1
  - ...
- Game 2
  - Match: Adams vs Alrehaili (2-0)
    - Game 2: 1-0
  - ...
```

**Key Changes:**
1. Added match header rendering between round header and games
2. Updated item count calculation to include match headers
3. Modified scroll indexing to account for extra headers
4. Maintained backward compatibility with non-knockout formats

### 4. Round Header Formatting (`round_header_widget.dart`)

**Improvements:**
- Automatically formats round slugs for knockout tournaments
- "game-1" → "Game 1"
- "tiebreak-1-rapid-2" → "Tiebreak 1 - Rapid 2"
- Falls back to original name for non-knockout formats

## Usage Examples

### Example 1: Standard Knockout (FIDE World Cup Style)

```
Round slugs: game-1, game-2, tiebreak-1-rapid-1, tiebreak-1-rapid-2

Display:
┌─ Game 1 ⚫ 78 games ─────────────┐
│ │ Abasov vs Suyarov              │
│ │ 1.0 - 0.0  │  1 game           │
│ ├─ Game 1: Abasov - Suyarov     │
│ │  Status: 1-0                   │
└────────────────────────────────────┘
```

### Example 2: Match with Tiebreaks

```
Match: Grandelius vs Damaj
├── Game 1: 1-0 (White wins)
├── Game 2: ½-½ (Draw)
├── Tiebreak 1 - Rapid 1: 1-0 (White wins)

Score Display: 2.5 - 0.5 ✓ Complete
```

## Technical Details

### Match Score Calculation

```dart
// Tracks score relative to first player in match
for (game in matchGames) {
  if (game.whiteWins && isPlayer1White) → player1Score += 1.0
  if (game.blackWins && isPlayer1Black) → player1Score += 1.0
  if (game.draw) → both players += 0.5
}
```

### Round Slug Sorting

Ensures games appear in logical order:
1. game-1, game-2, game-3... (priority 0)
2. tiebreak-1-rapid-1, tiebreak-1-rapid-2... (priority 10+)
3. tiebreak-2-blitz-1, tiebreak-2-blitz-2... (priority 20+)
4. armageddon (priority 30+)

### Performance Optimizations

1. **Detection Caching**: Match format detection runs once per round
2. **Pre-computed Groups**: Matches grouped once, then reused
3. **Efficient Indexing**: O(1) lookup for scroll position calculation

## Critical Fix: Group Event Override

### The Problem
Tournament CBWLKDSY had team metadata in the database (players.team field), which caused the UI to route to `GroupEventGamesTourContentBody` instead of the knockout match view, even though the games followed a perfect knockout pattern.

**Root Cause:**
In `games_tour_screen_mode_provider.dart`, the code checked if all players have team metadata and set mode to `groupEvent` without considering if the games follow a knockout match format.

```dart
// WRONG: Only checks team metadata
if (all_players_have_teams) {
  mode = groupEvent;  // ❌ Ignores knockout format!
}
```

### The Solution
Modified `games_tour_screen_mode_provider.dart` to check knockout format FIRST:

```dart
// CORRECT: Priority order
1. Check for knockout match format (game-N patterns + repeated matchups)
   → If detected: Use normal mode (displays matches)
2. Check for team metadata
   → If all have teams: Use group event mode
3. Otherwise: Use normal mode
```

**Key Implementation:**
- Reads all games from `gamesTourProvider`
- Converts to `GamesTourModel` for analysis
- Calls `KnockoutMatchDetector.isKnockoutMatchFormat()`
- If detected → Sets mode to `normal` (which renders with match grouping)
- Early return prevents team check from overriding

**Result:**
Knockout tournaments with team metadata now correctly display as matches, not group events.

## Backward Compatibility

**Non-Knockout Tournaments:**
- Automatically fall back to original flat display
- No visual changes
- No performance impact

**Group Events:**
- Team-based tournaments without knockout patterns continue to use group event view
- Knockout detection has priority, so won't affect true group events

**Detection Threshold:**
- Requires >30% of games to match knockout patterns
- Requires >50% of matchups to have multiple games
- This ensures false positives are minimal

## Testing

### Test with Tournament CBWLKDSY

```bash
# Query the tournament data
SELECT * FROM games WHERE tour_id = 'CBWLKDSY'
ORDER BY round_slug, player_white, player_black;

# Expected structure:
# - game-1: 78 games (all first games of matches)
# - game-2: 39 games (winners continue)
# - tiebreak rounds: as needed
```

### Visual Testing Checklist

- [ ] Round headers show "Game 1", "Game 2" instead of raw slugs
- [ ] Match headers appear between round headers and games
- [ ] Scores are calculated correctly (1.5 - 0.5, etc.)
- [ ] "Complete" badge shows when all games finished
- [ ] Tiebreak rounds formatted properly
- [ ] Regular tournaments still work normally

## Future Enhancements

1. **Match Collapsing**: Allow users to collapse/expand individual matches
2. **Match Statistics**: Add win/loss/draw breakdown per match
3. **Tiebreak Indicators**: Show when tiebreaks are scheduled but not started
4. **Player Performance**: Track performance across multiple matches
5. **Round Names**: Support for "Quarter-finals", "Semi-finals", "Finals"

## Configuration

No configuration needed - the system automatically detects and adapts to the tournament format based on the game data structure.

## Related Files

- `/lib/screens/tour_detail/games_tour/utils/knockout_match_detector.dart` - Detection logic
- `/lib/screens/tour_detail/games_tour/widgets/match_header_widget.dart` - Match header UI
- `/lib/screens/tour_detail/games_tour/widgets/games_list_view.dart` - List rendering
- `/lib/screens/tour_detail/games_tour/widgets/round_header_widget.dart` - Round header formatting
- `/lib/screens/tour_detail/games_tour/providers/games_tour_screen_mode_provider.dart` - **CRITICAL**: Determines rendering mode (normal vs group event)

## Database Schema

The implementation works with the existing schema without modifications:

```sql
games {
  id: text
  round_id: text       -- e.g., "t8DzIZPc", "NUcmLDqC" (all Game 1s, all Game 2s)
  round_slug: text     -- e.g., "game-1", "game-2", "tiebreak-1-rapid-1"
  tour_id: text
  player_white: text
  player_black: text
  status: text         -- "1-0", "0-1", "½-½", "*"
  ...
}
```

**Key Understanding:**
- **Database rounds** (`round_id`) group by **game number** (all first games, all second games, etc.)
- **Display grouping** shows by **player matchups** (Adams vs Alrehaili across all their games)
- The `round_slug` field indicates which game in the match this is

## Summary: What Changed

### The Core Problem
In tournament CBWLKDSY:
- Adams plays Alrehaili in **multiple games** (Game 1, Game 2, tiebreaks)
- Database stores these in **separate rounds** by game number
- User wants to see **all games between Adams and Alrehaili together**
- **CRITICAL**: Tournament has team metadata, causing it to render as "group event" view instead of knockout view

### The Solution
✅ **Groups games by player matchups across ALL database rounds**
✅ **Shows complete match context**: "Adams vs Alrehaili (2-0)" with all their games
✅ **Maintains game order**: Game 1 → Game 2 → Tiebreak 1 → etc.
✅ **Knockout detection overrides group event detection**: Detects knockout format FIRST, before checking team metadata

### Visual Result
**Before:**
```
Game 1 Round
- Adams vs Alrehaili: 0-1
- Other games...

Game 2 Round
- Adams vs Alrehaili: 1-0
- Other games...
```

**After:**
```
Round 1 ⚫ 117 games in 78 matches

Match: Adams vs Alrehaili (2-0) ✓
├─ Game 1: 0-1
└─ Game 2: 1-0

Match: Grandelius vs Damaj (1.5-0.5)
├─ Game 1: 1-0
├─ Game 2: ½-½
└─ Tiebreak 1 - Rapid 1: ongoing
```

### Implementation Details
- `groupByMatchesAcrossAllRounds()` - Groups all tournament games by player pairs
- `_computeItemCountKnockout()` - Calculates list items for match-based display
- `_lookupItemKnockout()` - Maps list index to correct match/game
- Tournament header shows: "Round 1 ⚫ X games in Y matches"
- Match headers show current score and completion status
- **CRITICAL FIX**: `games_tour_screen_mode_provider.dart` checks for knockout format FIRST (before team metadata), overriding group event view when knockout patterns detected
