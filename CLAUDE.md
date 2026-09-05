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
entitlement
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
