# Lichess FIDE API Integration

This document explains how we integrate Lichess FIDE API to fetch official FIDE ratings for players.

## Overview

The Lichess FIDE API provides access to official FIDE player data including:
- Player names and titles (GM, IM, FM, etc.)
- Federation/country codes
- Birth year
- **Classical (Standard) ratings**
- **Rapid ratings**
- **Blitz ratings**

## API Endpoints

### 1. Get Player by FIDE ID
```
GET https://lichess.org/api/fide/player/{playerId}
```

**Example:**
```
https://lichess.org/api/fide/player/25059530
```

**Response:**
```json
{
  "id": 25059530,
  "name": "Praggnanandhaa R",
  "federation": "IND",
  "year": 2005,
  "title": "GM",
  "standard": 2785,
  "rapid": 2691,
  "blitz": 2707
}
```

**Note:** In FIDE terminology, "standard" = classical time control

### 2. Search Players by Name
```
GET https://lichess.org/api/fide/player?q={name}
```

**Example:**
```
https://lichess.org/api/fide/player?q=Erigaisi
```

Returns an array of matching players.

## Implementation

### Models

**FidePlayer** (`lib/repository/lichess/fide/fide_player.dart`)
```dart
class FidePlayer {
  final int id;
  final String name;
  final String? federation;
  final int? year;
  final String? title;
  final int? standard;  // Classical rating
  final int? rapid;
  final int? blitz;
  
  int? getRating(String timeControlType) {
    // Returns rating for 'standard', 'rapid', or 'blitz'
  }
}
```

### Repository

**LichessFideRepository** (`lib/repository/lichess/fide/lichess_fide_repository.dart`)
```dart
final repo = ref.read(lichessFideRepoProvider);

// Get player by ID
final player = await repo.getPlayerById(25059530);

// Search by name
final players = await repo.searchPlayersByName("Carlsen");
```

### Providers

**Get player data:**
```dart
final playerAsync = ref.watch(fidePlayerProvider(25059530));
```

**Get specific rating:**
```dart
final request = FideRatingRequest(
  fideId: 25059530,
  timeControlType: "standard", // or "rapid" or "blitz"
);
final ratingAsync = ref.watch(fideRatingProvider(request));
```

## Usage in Score Card Screen

The `_RatingDisplay` widget automatically:
1. **Tries Lichess FIDE API first** if a FIDE ID is available
2. **Falls back to PGN-based ratings** from Supabase if:
   - No FIDE ID is available
   - FIDE API returns no rating
   - FIDE API request fails

```dart
_RatingDisplay(
  playerName: player.name,
  fideId: player.fideId,  // Optional: enables FIDE API lookup
  timeControlType: "standard",
  assetPath: 'assets/pngs/classical.png',
)
```

## Limitations

### What Lichess FIDE API Provides:
✅ Latest official FIDE ratings (standard/rapid/blitz)
✅ Player titles and federations
✅ Real-time data from FIDE downloads

### What It Does NOT Provide:
❌ Historical rating changes
❌ Rating progression over time
❌ Performance statistics

For historical data, you would need to source this from separate FIDE datasets.

## Benefits

1. **Official FIDE Ratings:** Direct from FIDE's official data
2. **No Database Queries:** Reduces load on our Supabase
3. **Always Up-to-Date:** Lichess updates from FIDE regularly
4. **Graceful Fallback:** Still works without FIDE ID using PGN data
5. **Clean API:** Simple REST endpoints, no authentication required

## Error Handling

The implementation includes robust error handling:
- Timeouts (5 seconds)
- 404 handling (player not found)
- Automatic fallback to PGN-based ratings
- Console logging for debugging

## Example Console Output

```
🌐 Lichess FIDE: Requesting player 25059530
📡 Lichess FIDE: Response status 200
✅ Lichess FIDE: Found player Praggnanandhaa R - Classical: 2785, Rapid: 2691, Blitz: 2707
```
