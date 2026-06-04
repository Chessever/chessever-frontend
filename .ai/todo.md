# PiP fixes (feat/pip → test/pip) — DONE

Shared contract: payload key `followLive` (bool). true = at live head → native polls + ticks. false = frozen on viewed move.

## Bug 1 — board/piece theme parity ✅
- [x] iOS `drawBoard`: 25-entry chessground theme table (boardSquareColors), default 9. Pieces already correct.
- [x] Android `boardThemeColors`: full 25-entry chessground table (ARGB), default 9.
- [x] Android pieces: load from flutter_assets piece_sets/<set>/<code>.png by pieceStyleIndex (39-set list), drawable fallback. Threaded drawBoard→drawPiece→loadPieceBitmap.

## Bug 2 — live position updates ✅
- [x] native polls games(fen,last_move,…) @4s; now gated on followLive.

## Bug 3 — countdown parity ✅
- [x] native displayClock already matches live-card algo (active side only, baseSeconds - elapsedSince(lastMoveTime)).
- [x] padding `%d:%02d`→`%02d:%02d` (iOS x2, Android x2) + Dart `_formatPipClock`.

## Bug 4 — preserve focused (non-latest) move ✅
- [x] Dart followLive = !isInAnalysisVariation && isAtEnd (snapshot=true).
- [x] iOS mergeLiveRow early-return + displayClock static when !followLive.
- [x] Android mergeLiveRow early-return + displayClock static when !followLive.

## Validate
- [x] flutter analyze touched dart — no new errors (19 pre-existing lints only).
- [ ] manual: iOS device + Android emu (debug = any game eligible). Live game needed to fully see Bug 2/3/4-follow.

## Files
- lib/screens/chessboard/chess_board_screen_new.dart (_buildPipPayload, _formatPipClock)
- ios/Runner/ChessPipController.swift (boardSquareColors, drawBoard, mergeLiveRow, displayClock, formatClock x2)
- android/.../MainActivity.kt (boardThemeColors, piece asset loader, drawBoard/drawPiece, mergeLiveRow, displayClock, formatClock x2)
