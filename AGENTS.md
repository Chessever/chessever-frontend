# Chessever Frontend — Agent Rules

> One file for every agent: `CLAUDE.md` is the one-line import `@AGENTS.md`;
> edit only this file. (`third_party/chessground/CLAUDE.md` belongs to the
> vendored package and is separate.)

## Fast checks — run these first

| What | Fast (use while iterating) | Reference / gate |
|---|---|---|
| Dart analyze | `dartr analyze <paths>` when `dartr` is on PATH (`brew install orestesgaolin/tap/dartr`) | `flutter analyze` (or `flutter analyze --no-pub <paths>`) — once before you finish |
| Dart format | `dartr format <paths>` | `dart format <paths>` |
| Dart fixes | `dartr fix --dry-run` | `dart fix --dry-run` |
| Edge-function tests (`supabase/tests`) | `npm run test:rewarded` there (Node, under a second — no faster runner needed) | same |

- dartr is a preview Rust port of the Dart 3.13.3 analyzer and we run Dart 3.14
  beta, so it is a fast first pass only: run `flutter analyze` once before
  finishing, and if the two disagree, `flutter analyze` wins.
- Run the narrowest tests that cover the change first; the full suite once at the end.
- No Oxlint/Bun here on purpose: the repo has no JS lint, and its only JS test
  suite (`supabase/tests`, 9 tests) already finishes in ~0.2 s on Node.

## Production app and environment selection

This repository targets the **production ChessEver app** by default. Berkay
retired the ChessEver Test app on 2026-10-06. Do not select the `chessevertest`
flavor, `lib/main_test.dart`, test Supabase, or a test release workflow unless
the user explicitly requests historical test-environment work.

- Mobile releases use `stable`, the production flavor/entrypoint (`lib/main.dart`),
  and GitHub Actions `.github/workflows/mobile-release.yml`. Codemagic is retired.
- The workflow's default `store: testing` uploads to TestFlight and Google Play
  internal testing and submits nothing for review (product decision,
  2026-10-23). Never make review submission the default again. When a review is
  explicitly requested (`store: review`), hold both stores for manual release:
  iOS must use `--release-type MANUAL`, and before each Android production
  submission verify Google Play Managed publishing is ON; the publishing API
  cannot read it. Read `docs/ci/github-actions-release.md` before changing or
  triggering releases.
- App, Supabase, and companion broadcasting work at `../chessever-broadcasting`
  targets the intended production configuration when that work is in scope.
- Verify the exact project, URL, credentials, topic, migration target, and release
  workflow before every backend-affecting or external command. Do not infer an
  environment from a similar name or fall back to test configuration.
- Production is the default target, not permission to make unrelated changes.
  Perform only the operations authorized by the user's task; ask when the actual
  target or a destructive operation is ambiguous.
- Never use the abandoned `main` branch for development, merging, or releases.
  Keep credentials and local environment files out of commits and published assets.

## Branches: work directly on `stable`

**`stable` is the main branch: development, integration, and release all happen
on it.** The local checkout stays on `stable`. Edit, commit, and push there
directly. Production GitHub Actions builds target `stable` (`--ref stable`).
ChessEver Test workflows are retired and are not release targets.

- When the user says "main", "the main branch", or "latest main", they mean
  `stable`. Fast-forward it first (`git pull --ff-only origin stable`).
- **Do not create feature branches, PRs, or extra worktrees** unless the user
  deliberately asks for a PR. If the checkout is on another branch, get back to
  `stable` (tree clean) before editing.
- Commit on `stable` and push to `origin stable`. Stage explicit paths only;
  other automation may dirty the tree mid-session.
- Only when the user explicitly asks for a PR: branch from `stable`, set the
  PR base to `stable` explicitly (never GitHub's default), and delete the branch
  and any worktree once it merges.

`main` is an **abandoned branch**, not a release line. As of 2026-08-11 it sits
at `36a466da` (2026-06-16, `pubspec` version `21.0.0+2100`) — **383 commits
behind `stable` and 0 ahead**. Building it would produce build number `2100`
against the `3305`+ already published, which the stores reject outright. Nothing
is merged into it, nothing is built from it, nothing is shipped off it. Treat
its GitHub "default branch" badge as a leftover, not a signal.

`dev` is likewise stale (167 behind `stable`, 12 ahead) but is still the base
GitHub picks for contributor PRs. Override that default with `stable`. Work
already merged into `dev` must be ported onto `stable` (cherry-pick) before it
can ship.

When a request says "**the main production app**", that means the **production
flavor** — the counterpart to the test-flavored app — and never the `main`
branch. Read it that way and work on `stable`.

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
  PR lands without one, bump immediately in a follow-up PR rather than letting
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

## Edge Functions: NEVER deploy with `verify_jwt` enabled

**Rule: every ChessEver Edge Function ships with `verify_jwt = false`. No exceptions on the list below.** Gateway JWT verification is not our auth boundary and never was — each function authenticates its own callers, and turning the gateway check on does not add security, it only makes the function unreachable.

Two independent reasons it breaks things, both silent:

1. **Third-party callers have no Supabase JWT.** Stripe, RevenueCat, GitHub and our own stream pipeline sign their requests their own way (HMAC signature, or a shared secret in a header). With the gateway check on, Supabase answers `401 UNAUTHORIZED_NO_AUTH_HEADER` **before the function body runs**, so nothing is logged and the provider just queues retries.
2. **Our own apps' keys are rejected too.** This project migrated to ES256 JWT signing keys on 2026-08-04. The Functions gateway now rejects the legacy anon key with `401 UNAUTHORIZED_LEGACY_JWT` (the REST API still accepts it, which is why this hid for weeks). Any function called before sign-in — onboarding photos, annotations — became unreachable for every new user.

These must be `false`, whichever repo owns them:

```
stripe-webhook             revenuecat-webhook        revenuecat-sync
onesignal-dispatch         github-webhook            fetch-fide-photo-webp
fetch-lichess-annotations  stripe-checkout           stripe-portal
entitlement                prep-games-check
```

### How to deploy

```bash
supabase functions deploy <slug> --project-ref oelbsuggrzyqwzmvidju --no-verify-jwt
```

`supabase/config.toml` in this repo already pins `verify_jwt = false` per function and the CLI honours it (precedence: `--flag` > config > remote). Do not delete those blocks; add one for every new function.

**The `--no-verify-jwt` flag matters because config.toml does not cover every deploy path.** The Supabase MCP `deploy_edge_function` tool, the dashboard, and the Management API all ignore this file and send `verify_jwt` explicitly, **defaulting to `true`**. The MCP tool's own description even instructs the agent to enable it. If you deploy by any of those routes, you will silently re-create the outage.

### After ANY deploy, by any route

```bash
chessever_frontend_desktop_oss/scripts/check_edge_function_auth.sh    # must exit 0
```

It asserts every flag against intent and probes each endpoint from outside. Read the **body**, not the status code: a healthy `revenuecat-webhook` answers 401 from its own auth check, identical to a gateway rejection. Only the gateway says `UNAUTHORIZED_NO_AUTH_HEADER`.

### Before deploying a function that exists in more than one repo

```bash
chessever_frontend_desktop_oss/scripts/which_repo_owns_function.sh <slug>
```

`onesignal-dispatch`, `fetch-fide-photo-webp` and `revenuecat-webhook` have stale copies in other repos. Deploying from the wrong one rolls production back — it happened on 2026-08-26 and reverted an auth check to a version that accepted any request with no token header. This repo is the source of truth for the notification, RevenueCat and photo functions.

## My Space: removal preserves the source

- Removing anything from My Space changes only its shortcut or My Space
  visibility, including bulk removal and automatic cards. Preserve the original
  favorite, event, prep profile, downloaded games, database, liked game, and
  subscription. Undo restores only My Space state.
- Keep deletion, unfavoriting, unliking, and unsubscribe actions on their source
  screens. My Space cards offer `Remove from My Space` instead.
- Exception, by product decision (Trello #1225): smart event, collection and
  Prep player cards in My Space end in their own star, the same star as the
  Events list, Discovery and the Prep profile, because starring is how their
  notifications are turned on (unstarring turns them off; smart events and
  Prep players have no separate switch). The star is the thing's own
  favorite; the shortcut stays when it is unstarred.

## Broadcast clocks: the event's time control is only a guess for a game

`lib/utils/time_control_bonus.dart` adds a classical event's second period
("+30 min after move 40") to clocks the relay has not credited yet. It reads
the period from `tours.info->>'tc'`, the EVENT's main control, and applies it
to every game of the event.

**What broke (2026-10-22).** The U.S. Championship's 15+10 rapid playoff ran
under the same tour as the classical rounds. From move 40 the app, chessever.com
and the spectator site showed **30:48 for a player with 0:48**. The broadcast
delay was not the cause.

- **The guard.** `secondaryPeriodFitsGame` gates both clock paths:
  `applySecondaryBonusToLiveClocks` (cards and countdowns) and
  `applySecondaryBonusToMoveClocks` (move lists and shares). Take each side's
  earliest reading in its first 10 moves. When every side that has one is
  under half the parsed base (or under the bonus when no base is named), the
  game is a shorter control and keeps its raw clocks. One low side is a late arrival
  and still gets the bonus.
- **Three copies, one rule.** The same logic lives in chessever-broadcasting
  `packages/domain/src/clockRule.ts` (ingest) and chessever_web_frontend
  `src/broadcast/lib/clock-rule.ts` (chessever.com). Change one, change all
  three, each with a test in `test/time_control_bonus_test.dart`.
- **A new clock surface must go through one of the two helpers.** Calling
  `secondaryBonusOffsetSeconds` directly skips the fit check.
- **Clock off by exactly one period** (30:00, 15:00, 50:00): the cause is this
  rule, not delay. Compare the organizer file and Lichess for the same board
  before changing anything.
- **Old builds stay wrong until users update.** The emergency fix is data:
  rewrite `tours.info.tc` into a form the parser declines, e.g.
  `Rounds 1-11: … | Playoff: 15+10 …`, since a `|` or `Round N-M` is rejected.

## Commits and delivery

- Commit completed changes on `stable` after validation, including the required
  version bump when shipped code changes.
- Push `stable` when the user asks to push, merge, or ship. Open a PR only when
  the user deliberately asks for one; it must target `stable`.
- Exclude credentials and local environment configuration, and preserve unrelated working-tree changes.
