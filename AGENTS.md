# Chessever Frontend — Agent Rules

## Test app and broadcasting environment isolation

This repository is the Chessever **test-flavored app**. By default, all work here targets the **test Supabase branch/project** and the companion broadcasting repository at `projects/chessever-broadcasting` (available from this workspace as `../chessever-broadcasting`). These test targets are the only environments in scope unless the user explicitly says otherwise.

- Keep app, Supabase, and broadcasting work on the intended test branches and test configuration. Use test-only URLs, credentials, secrets, topics, migrations, and deployment targets.
- **Never check out, merge, rebase, push to, modify, query, migrate, deploy to, or otherwise operate on `main`, production branches/projects, production Supabase, production services, production secrets/URLs, or any production version of the broadcasting system while working on this test app or `projects/chessever-broadcasting`.**
- Do not assume that a similarly named branch, project, URL, key, or environment is safe. Verify that every backend-affecting or external command points to the test target before running it.
- If a target is ambiguous or a requested action could affect main/production, stop and ask for explicit confirmation. Main/production work is allowed only when the user explicitly names the exact target and operation.

## Branches: `stable` ships, `main` is dead

**`stable` is the only branch that matters here.** It is where work is committed,
where releases are cut, and the branch every Codemagic build is triggered
against (`"branch":"stable"` in the API payload — production *and* ChessEver
Test workflows alike).

`main` is an **abandoned branch**, not a release line. As of 2026-08-11 it sits
at `36a466da` (2026-06-16, `pubspec` version `21.0.0+2100`) — **383 commits
behind `stable` and 0 ahead**. Building it would produce build number `2100`
against the `3305`+ already published, which the stores reject outright. Nothing
is merged into it, nothing is built from it, nothing is shipped off it. Treat
its GitHub "default branch" badge as a leftover, not a signal.

`dev` is likewise stale (167 behind `stable`, 12 ahead) but is still the base
GitHub picks for contributor PRs, so a merged PR there is not shipped until it
is ported onto `stable`.

When a request says "**the main production app**", that means the **production
flavor** — the counterpart to the test-flavored app — and never the `main`
branch. Read it that way and keep working on `stable`.

## Validation

- **Never run `flutter build`** (any flavor: apk, ios, ipa, web, macos, etc.). Builds are slow and unnecessary for validation.
- `flutter analyze` is the canonical correctness check. If it passes for changed files, the change is validated.
- Use `flutter analyze --no-pub <paths>` to scope output to touched files when the whole-repo report is noisy.
- Static type errors, missing imports, and API misuse are caught by `flutter analyze`. Trust it.
- For runtime behavior verification, ask the user to test on device — do not invoke `flutter run` or `flutter build` proactively.
- **Never run the app to test things — always delegate runtime/on-screen testing to the user.** Do not start/`flutter run` the app, do not attach to or drive a running app (Marionette, VM Service, DevTools), and do not hunt for a debug instance to connect to. Your job ends at: code change + `flutter analyze` clean + (when useful) unit/widget tests. The user does all live-app/UI verification. Hand them the exact steps to check; don't try to observe it yourself even if a Stop hook or goal asks for runtime confirmation.

## Versioning: every commit bumps `pubspec.yaml`

Every commit that changes shipped code bumps `version:` in `pubspec.yaml`. Patch
segment and build number move together, both by one: `34.1.15+3288` →
`34.1.16+3289`. Never bump one without the other.

- **The bump rides with the change that earned it.** Do not land a fix and then
  follow it with a separate `chore: bump patch version` commit — that pattern is
  what this rule replaces.
- **Put the resulting version in the commit subject**, in parentheses at the end:
  `fix(share): map PGN Lichess URLs to working chessever.com routes (34.1.16).`
- **A squash-merged PR is one commit, so the PR branch must carry the bump.** If a
  PR lands without one, bump immediately in a follow-up commit rather than letting
  it ride to the next unrelated change.
- **Exempt:** docs-only, test-only, CI-only and tooling-only commits.
- `pubspec.yaml` often carries unrelated local edits (a `.env` asset line
  uncommented for local dev). Stage the version line alone; never sweep those in.

The same rule holds in `chessever_frontend_desktop` (`20.27.7+277`). Shared logic
ported to both repos — the Game Report classifier above all — bumps both.

## Stockfish in debug (DO NOT "fix")

We **purposefully deactivate local Stockfish in debug mode** because its native FFI isolates hang Flutter **hot restart / hot reload** ("Performing hot restart…" never finishes).

- Source of truth: `lib/screens/chessboard/provider/stockfish_singleton.dart`
  - `kEnableStockfishInDebug = false` (intentional)
  - `evaluatePosition` / `warmUp` take `allowInDebug` (default **false**)
- **Board analysis / eval bar / MultiPV must never pass `allowInDebug: true`.** Empty board PVs in a debug session are expected.
- Only explicit workflows like **Game Review** may opt in with `allowInDebug: true`.
- **Never** add a bypass such as `_allowBoardStockfishInDebug = true`, flip `kEnableStockfishInDebug` to "make engine lines work while coding", or rewire restart policy to start the real engine in debug. That has already broken hot restart for the team.
- To test real board Stockfish: use profile/release, or flip the kill switch yourself knowing hot restart will hang until a full stop+relaunch — do not change the default for everyone.

## Snacks: use `showAppSnack`, never a raw `SnackBar`

`lib/widgets/app_snack.dart` is the only sanctioned way to raise a transient message. `showAppSnack(context, message, tone:, actionLabel:, onAction:)`, or `showAppSnackOn(messenger, …)` when the messenger was captured before an `await`.

- **Never construct a `SnackBar` by hand.** Flutter ≥3.38 (PR #173084) defaults `SnackBar.persist` to `action != null`, so any hand-rolled snack with an action never times out — it survives route pushes and stays pinned over whatever screen the user walks to next. That shipped as a bug. The helper always passes `persist: false`.
- The gotcha is worst where logic awaits `ScaffoldFeatureController.closed` (the My Likes export gate): with `persist: true` that future never completes and the flow hangs silently.
- Tone carries the meaning: `neutral` for confirmations, `danger` for genuine failures, `success` for completed work. The capsule is black in both themes — do not recolour the surface per message.
- Regression cover lives in `test/app_snack_test.dart` (auto-dismiss, action close, 44dp tap target).

## Cursor Cloud specific instructions

The Flutter SDK is baked into the VM snapshot at `/opt/flutter` (Flutter **3.47.0** /
Dart 3.13.0 — latest stable, on `PATH` via `~/.bashrc`). The startup update script only runs
`flutter pub get`; the SDK is not reinstalled per boot. Flutter 3.29.x and older
reject `pubspec.yaml` (`Unexpected child "config" found under "flutter"`), so any
newer SDK must be ≥3.38 — do not downgrade below that.

Validation here follows the repo rules above: no `flutter build`/`flutter run`
(no device/emulator in the VM). `flutter analyze` + `flutter test` are the proof.

- **Whole-repo `flutter analyze` is misleadingly noisy.** ~360 issues (incl.
  `error`s) come entirely from the vendored `third_party/chessground/example/`
  and `third_party/chessground/test/` trees, which reference dev-only packages
  (`mocktail`, a `board_example` package) that aren't resolved in this workspace.
  That is expected. Scope to the app instead: `flutter analyze --no-pub lib test`.
  `lib/` has **0 `error`-level issues** (only pre-existing warnings/infos such as
  `deprecated_member_use` for `withOpacity` and a few unused imports), but `flutter
  analyze` still exits non-zero on those warnings — judge changed files by the
  `error •` count, not the exit code.
- **Piping analyze/test through `tail`/`tee` masks the real exit code** (you get
  the pipe's). Redirect to a file and check `$?` when you need the true status.
- `flutter test test/` (the app suite) is **~1503 pass / ~4 skipped / 6 fail**.
  The 6 failures are pre-existing stale tests, not environment problems, and are
  safe to ignore unless you touch their area: `test/widget_test.dart` (leftover
  default "Counter" template referencing a non-existent `MyApp` counter);
  `test/library_book_tag_filter_test.dart` + `test/liked_games_provider_test.dart`
  (drifted `tag:`/`tags:` `LibraryRepository` signature — won't compile);
  `test/android_native_regression_test.dart` (source-grep guard whose expectation
  drifted from the checked-in Kotlin); and two
  `test/gamebase_explorer_filter_paywall_test.dart` widget-assertion cases.
- Generated code (`*.mapper.dart`, `lib/l10n/app_localizations*.dart`) is checked
  in, so `build_runner`/`gen-l10n` are **not** needed just to analyze or test.
