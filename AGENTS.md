# Chessever Frontend — Agent Rules

## Validation

- **Never run `flutter build`** (any flavor: apk, ios, ipa, web, macos, etc.). Builds are slow and unnecessary for validation.
- `flutter analyze` is the canonical correctness check. If it passes for changed files, the change is validated.
- Use `flutter analyze --no-pub <paths>` to scope output to touched files when the whole-repo report is noisy.
- Static type errors, missing imports, and API misuse are caught by `flutter analyze`. Trust it.
- For runtime behavior verification, ask the user to test on device — do not invoke `flutter run` or `flutter build` proactively.
- **Never run the app to test things — always delegate runtime/on-screen testing to the user.** Do not start/`flutter run` the app, do not attach to or drive a running app (Marionette, VM Service, DevTools), and do not hunt for a debug instance to connect to. Your job ends at: code change + `flutter analyze` clean + (when useful) unit/widget tests. The user does all live-app/UI verification. Hand them the exact steps to check; don't try to observe it yourself even if a Stop hook or goal asks for runtime confirmation.

## Stockfish in debug (DO NOT "fix")

We **purposefully deactivate local Stockfish in debug mode** because its native FFI isolates hang Flutter **hot restart / hot reload** ("Performing hot restart…" never finishes).

- Source of truth: `lib/screens/chessboard/provider/stockfish_singleton.dart`
  - `kEnableStockfishInDebug = false` (intentional)
  - `evaluatePosition` / `warmUp` take `allowInDebug` (default **false**)
- **Board analysis / eval bar / MultiPV must never pass `allowInDebug: true`.** Empty board PVs in a debug session are expected.
- Only explicit workflows like **Game Review** may opt in with `allowInDebug: true`.
- **Never** add a bypass such as `_allowBoardStockfishInDebug = true`, flip `kEnableStockfishInDebug` to "make engine lines work while coding", or rewire restart policy to start the real engine in debug. That has already broken hot restart for the team.
- To test real board Stockfish: use profile/release, or flip the kill switch yourself knowing hot restart will hang until a full stop+relaunch — do not change the default for everyone.
