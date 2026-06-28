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

## The patch — the only change vs. upstream

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

## How to bump to a newer chessground (keep at newest)

1. `flutter pub get` with `chessground: ^<newest>` so the new version lands in
   the pub cache.
2. `rm -rf third_party/chessground && cp -R ~/.pub-cache/hosted/pub.dev/chessground-<newest> third_party/chessground && chmod -R u+w third_party/chessground`
3. Reapply the patch above to `lib/src/widgets/board_controller.dart`.
4. Update the "Current vendored version" line here.
5. `flutter pub get` && `flutter analyze` (app + this package).

When upstream ships an equivalent detached-getter guard, drop this override
entirely and depend on the plain pub package.
