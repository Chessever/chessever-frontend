# FEN Null Issue in Grid/List View

**Date:** January 3, 2026
**Status:** FIXED (backend) but Frontend also better to have a fallback.
**Priority:** Medium

---

## Problem

Some chess boards in grid/list view display **no pieces** while the detailed chess board screen works correctly.

**Affected files:**
- `lib/screens/chessboard/widgets/chess_board_from_fen_new.dart` (line 698)
- `lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/`

---

## Root Cause

The `fen` field is `null` for some games in the database.

**Why FEN is null:**

1. **Lichess API behavior**: Returns `fen` only for **live/ongoing** games, not for finished games in historical rounds
2. **Streaming** (`streamer.py`) computes FEN from PGN and saves it - so actively streamed games have FEN
3. **Finished rounds** fetched via API hydration often have `fen: null` because Lichess doesn't include it

| Scenario | FEN in DB | Board Display |
|----------|-----------|---------------|
| Live game being streamed | Has FEN | Shows position |
| Finished game that was streamed | Has FEN | Shows position |
| Finished game never streamed | **NULL** | **Empty board** |
| Historical round from API | **NULL** | **Empty board** |

---

## Current Code Path

```
GamesTourModel.fromGame()
  → fen: game.fen?.isNotEmpty == true ? game.fen : null

liveGameCardProvider
  → fen: gameData['fen'] as String? ?? baseGame.fen  (still null if both null)

_ChessBoardWidget.build()
  → fen: fen ?? ''  (empty string = no pieces)
```

---

## Proposed Fix

When `fen` is null but `pgn` exists, **parse the PGN to extract the final position FEN**.

### Option 1: In `GamesTourModel.fromGame()`

```dart
factory GamesTourModel.fromGame(Games game) {
  // ... existing code ...

  String? computedFen = game.fen?.isNotEmpty == true ? game.fen : null;

  // Fallback: compute FEN from PGN if available
  if (computedFen == null && game.pgn != null && game.pgn!.isNotEmpty) {
    computedFen = _computeFenFromPgn(game.pgn!);
  }

  return GamesTourModel(
    // ...
    fen: computedFen,
    // ...
  );
}

static String? _computeFenFromPgn(String pgn) {
  try {
    final game = PgnGame.parsePgn(pgn);
    // Play through all moves to get final position
    var position = Chess.initial;
    for (final node in game.moves.mainline()) {
      position = position.play(position.parseSan(node.san)!);
    }
    return position.fen;
  } catch (e) {
    return null;
  }
}
```

### Option 2: In `_ChessBoardWidget`

```dart
child: Chessboard.fixed(
  // ...
  fen: fen ?? _computeFenFromPgn(pgn) ?? '',
  // ...
),
```

### Option 3: Backend fix (preferred long-term)

In `supabase_client.py`, compute FEN from PGN during initial hydration when Lichess doesn't provide it.

---

## Dependencies

- `dartchess` package (already imported) for PGN parsing
- Or use existing `chess` package utilities

---

## Notes

- The detailed chess board screen works because it parses the full PGN to replay moves
- Grid/list views only use the pre-computed `fen` field for performance
- Computing FEN from PGN adds CPU overhead but only when `fen` is null
