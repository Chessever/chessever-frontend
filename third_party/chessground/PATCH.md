# Vendored chessground — ChessEver patch

This is the **verbatim** `chessground` pub package, vendored only so we can carry a
tiny patch. It is wired in via the app's `pubspec.yaml`:

```yaml
dependency_overrides:
  chessground:
    path: third_party/chessground
```

The app's normal dependency stays on the newest published version
(`chessground: ^10.1.1`); this copy must always be re-vendored from that same
newest version so we never fall behind upstream.

## Current vendored version

`10.1.1` (copied verbatim from `~/.pub-cache/hosted/pub.dev/chessground-10.1.1`).

## The patches — the only changes vs. upstream

There are two, both marked `CHESSEVER PATCH` in the source.

## Patch 1: detached-controller guard

**File:** `lib/src/widgets/board_controller.dart`
**Fixes:** fatal Sentry **CHESSEVER-1N2** — `ChessboardController.fadeAnimation`
"Null check operator used on a null value", phone/Android, on live/game-card
scrolling, board navigation, and Android PiP resume.

### Root cause

The interactive `Chessboard` reads `controller.fadeAnimation` and
`controller.translationAnimation` on **every `build()`**. chessground wires the
controller's `detach()` (which disposes and nulls those animations) into
`_BoardState.deactivate()`. On phone, reparent/remount timing — Android
predictive-back, PiP surface recovery, list/page recycling — can run a board
`build()` while its controller is momentarily detached. Upstream's getters then
do `return _fadeAnimation!`, whose null-check is only an `assert` in debug but a
hard throw in release → fatal.

### The change

Both getters return a settled fallback instead of throwing when detached:

```dart
@internal
Animation<double> get translationAnimation {
  return _translationAnimation ?? kAlwaysCompleteAnimation;
}

@internal
Animation<double> get fadeAnimation {
  return _fadeAnimation ?? kAlwaysCompleteAnimation;
}
```

(Return type widened `CurvedAnimation` → `Animation<double>`; the only consumers
are the board's two piece painters, which already accept `Animation<double>`.)
`kAlwaysCompleteAnimation` is a non-ticking, fully-settled animation — the
correct semantic for "no controller attached": the static position renders with
no animation, no crash.

## Patch 2: landing settle (classified moves)

**Files:** `lib/src/widgets/board.dart`, `lib/src/widgets/board_painter.dart`
**Why:** a classified move (brilliant, blunder, ...) gets a small landing moment
on its destination square. The app draws the colour effect as an overlay
(`lib/screens/chessboard/classification_fx/classification_landing.dart`); this
patch lets the landed PIECE itself settle, which an overlay cannot do.

### The change (purely additive — defaults reproduce upstream exactly)

- `Chessboard` gains two optional parameters, `landingSquare` (`Square?`) and
  `landingKey` (`Object?`). When `landingKey` changes and `landingSquare` is
  set, the piece on that square springs from scale 1.08 back to 1.0 (~300 ms,
  `SpringSimulation`, damping ratio 0.7) once its move animation has committed.
- `_BoardState` waits for the square to leave `translatingPiecesNotifier`
  (post-frame, then a listener), runs the spring on its own unbounded
  `AnimationController`, and cancels on any later position change, controller
  swap, `landingSquare` → null, deactivate or dispose. Skipped when
  `animationDuration` is zero or `MediaQuery.disableAnimations` is set.
- `PiecesPainter` gains an optional `landingSquareNotifier`; it skips that
  square while set (and repaints when it changes).
- New `LandingPiecePainter` draws just that piece, scaled around the square
  centre, in its own `CustomPaint` layer right above the translating pieces —
  added to the stack only when `landingSquare != null`, so boards that never
  pass it render and cost exactly what they did before.

Wire it from the app by passing the classified move's destination square and a
per-ply key (the same `trigger` given to `ClassificationLanding`).

## How to bump to a newer chessground (keep at newest)

1. `flutter pub get` with `chessground: ^<newest>` so the new version lands in
   the pub cache.
2. `rm -rf third_party/chessground && cp -R ~/.pub-cache/hosted/pub.dev/chessground-<newest> third_party/chessground && chmod -R u+w third_party/chessground`
3. Reapply both patches above (`board_controller.dart`; `board.dart` +
   `board_painter.dart`). `grep -rn "CHESSEVER PATCH"` in the old copy lists
   every hunk.
4. Update the "Current vendored version" line here.
5. `flutter pub get` && `flutter analyze` (app + this package).

When upstream ships an equivalent detached-getter guard AND a landing hook (or
the app drops the settle), drop this override entirely and depend on the plain
pub package.
