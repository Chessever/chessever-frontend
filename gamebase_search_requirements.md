# Search Implementation for Chessever Frontend

This document describes how search works in the Chessever mobile app for "Countrymen" and "Favorites" features.

---

## Overview

Both features combine results from **Supabase** (live/recent games) and **Gamebase API** (historical game database) with:
- Parallel fetching for fast loading
- Content-based deduplication
- Infinite scroll pagination
- Minimum ELO filtering (2000+)

---

## 1. Countrymen Search

### How It Works

When user is on Countrymen page (e.g., Turkey selected) and searches "erdogmus":

**Supabase Query:**
```sql
SELECT * FROM games 
WHERE players @> '[{"fed": "TUR"}]'  -- Country filter
  AND name ILIKE '%erdogmus%'         -- Text search on "WhitePlayer - BlackPlayer"
ORDER BY last_move_time DESC
```

**Gamebase Query:**
```
GET /api/search?q=erdogmus country:Turkiye&resources[]=game&ratingFrom=2000&pageSize=15
```

### Token Usage

| Scenario | Gamebase Query |
|----------|----------------|
| Initial load (no search) | `country:Turkiye` |
| Search "erdogmus" | `erdogmus country:Turkiye` |
| Search "sicilian" | `sicilian country:Turkiye` |

### Country Name Mapping

The app maps country names to Gamebase format:

| User Selection | Gamebase Token |
|----------------|----------------|
| Turkey | `country:Turkiye` |
| United States | `country:"United States of America"` |
| United Kingdom | `country:England` |

---

## 2. Favorites Search

### How It Works

When user is on Favorites page (has Carlsen, Caruana favorited) and searches "sicilian":

**Supabase Query:**
```sql
SELECT * FROM games 
WHERE name ILIKE '%sicilian%'
ORDER BY last_move_time DESC
-- Then filter in Dart to only include games with favorited players
```

**Gamebase Query (for each favorite):**
```
GET /api/search?q=sicilian player:"Carlsen, Magnus"&resources[]=game&pageSize=5
GET /api/search?q=sicilian player:"Caruana, Fabiano"&resources[]=game&pageSize=5
```

### Token Usage

| Scenario | Gamebase Query |
|----------|----------------|
| Initial load | `player:"Carlsen, Magnus"` (per favorite) |
| Search "sicilian" | `sicilian player:"Carlsen, Magnus"` |
| Search "london" | `london player:"Carlsen, Magnus"` |

### Multi-Player Search (New Feature)

To find games between two specific players:
```
player:Carlsen player:Caruana
```
This uses AND logic to find games where BOTH players appear.

---

## 3. API Token Reference

| Token | Description | Example |
|-------|-------------|---------|
| `player:NAME` | Player on either side (repeatable for AND) | `player:Carlsen player:Caruana` |
| `white:NAME` | White player only | `white:Carlsen` |
| `black:NAME` | Black player only | `black:Caruana` |
| `country:COUNTRY` | Player federation (either side) | `country:Turkiye` |
| `event:NAME` | Tournament/event name | `event:London` |
| `eco:CODE` | ECO opening code | `eco:C45` |
| `opening:NAME` | Opening name | `opening:Sicilian` |

**All tokens support partial matching and are case-insensitive.**

---

## 4. Response Fields Used

The app uses these fields from Gamebase game preview:

| Field | Usage |
|-------|-------|
| `id` | Game identification |
| `white` | White player name |
| `black` | Black player name |
| `whiteElo` | Display rating |
| `blackElo` | Display rating |
| `whiteFed` | Display country flag |
| `blackFed` | Display country flag |
| `date` | Display date, sorting |
| `result` | Display outcome (W/B/D) |
| `eco` | Display opening code |
| `opening` | Display opening name |
| `event` | Display tournament |

---

## 5. Implementation Details

### Files

| File | Purpose |
|------|---------|
| `lib/screens/countrymen/provider/countrymen_combined_games_provider.dart` | Countrymen search state & logic |
| `lib/screens/favorites/player_games/provider/favorites_combined_games_provider.dart` | Favorites search state & logic |
| `lib/repository/supabase/game/game_repository.dart` | Supabase queries |
| `lib/repository/gamebase/gamebase_repository.dart` | Gamebase API calls |
| `lib/utils/country_utils.dart` | Country name mapping |

### Key Methods

**Countrymen Provider:**
- `searchGames(query)` - Triggers search with user query
- `_searchSupabase()` - Uses `searchCountrymenGames()` with ILIKE + country filter
- `_searchGamebase()` - Uses `country:` token combined with query

**Favorites Provider:**
- `searchGames(query)` - Triggers search with user query  
- `_searchSupabase()` - Uses `searchFavoritesGames()` with ILIKE + favorites filter
- `_searchGamebase()` - Uses `player:` token combined with query

### Deduplication

Games are deduplicated by content key:
```
{normalized_white_name}|{normalized_black_name}|{date}|{result}
```

This ensures the same game from Supabase and Gamebase appears only once.

---

## 6. Country Name Reference

| Common Name | Gamebase Value | FIDE Code (Supabase) |
|-------------|----------------|----------------------|
| Turkey | Turkiye | TUR |
| USA | United States of America | USA |
| UK | England | ENG |
| Russia | Russia | RUS |
| Germany | Germany | GER |
| Norway | Norway | NOR |
| France | France | FRA |
| India | India | IND |
| China | China | CHN |

---

## 7. Troubleshooting

### No Results from Gamebase

1. Check country name format (use `Turkiye` not `Turkey`)
2. Check player name format (use full name like `"Carlsen, Magnus"`)
3. Verify API key is valid
4. Check network connectivity

### No Results from Supabase

1. Check country code (FIDE format like `TUR`, `NOR`)
2. Verify `name` column has player names
3. Check `players` JSONB has `fed` field

### Slow Initial Load

- Page size is 15 for fast first render
- Both sources are fetched in parallel
- Results are streamed as they arrive
