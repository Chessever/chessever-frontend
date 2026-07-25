# Handoff: Stockfish / hot-restart regression — Arun PR #276 revert

> **SENIOR REVIEW APPENDED 2026-07-25 (second pass).** Revert verdict: **correct**,
> but it over-reached by one commit-hunk. See
> [Senior review addendum](#senior-review-addendum-2026-07-25) at the bottom
> before acting on anything above — two sections of this document
> (the "worth keeping?" tables) are now known to be wrong on one row.


**Date:** 2026-07-25  
**Branch:** `stable`  
**Author of incident:** Arun N (`arundhathinaik01@gmail.com`, GitHub arunn10)  
**Handled by:** Berkay + agent session  
**Audience:** senior review / second pair of eyes  

---

## TL;DR

Arun merged **PR #276** today that “stabilized” board engine suggestions / PV previews. It:

1. Re-enabled **real Stockfish in debug** for ordinary board analysis (`allowInDebug: true` via a local `_allowBoardStockfishInDebug = true` flag).
2. Rewired eval restart policy, PV preview lifecycle, and review-sheet eval deferral.

That undid an **intentional** product constraint: local Stockfish is **off in debug** because native FFI isolates hang Flutter **hot restart / hot reload**.

We **reverted PR #276** and added guardrail comments + agent-doc notes so this is harder to reintroduce by vibecoding.

**Not pushed yet.** `stable` is **1 commit ahead** of `origin/stable`.

---

## Symptom (reported)

- Stockfish / board engine path misbehaving after Arun’s latest commits.
- Hot restart broken again (“Performing hot restart…” style hang).

Context from product: the team already knew Stockfish + hot restart is incompatible in debug. That was deliberate, not a bug to “fix” by turning the engine back on.

---

## Root cause

### Bad merge

| Item | Value |
|------|--------|
| Author commit | `0888f68a` — `fix(chessboard): stabilize engine suggestions and PV previews` |
| Merge | `4e74d49b` — `Merge pull request #276 from Chessever/feat/game-analysis` |
| When | 2026-07-25 ~00:24 -0400 |

### Files touched by the bad PR

- `lib/screens/chessboard/chess_board_screen_new.dart`
- `lib/screens/chessboard/provider/board_eval_restart_policy.dart`
- `lib/screens/chessboard/provider/chess_board_screen_provider_new.dart` (large)
- `lib/screens/chessboard/provider/current_eval_provider.dart`
- `test/board_eval_restart_policy_test.dart`
- `test/board_expand_provider_stability_test.dart` (new; removed by revert)

### Why it broke hot restart

Canonical policy lives in:

`lib/screens/chessboard/provider/stockfish_singleton.dart`

```dart
const bool kEnableStockfishInDebug = false;
// evaluatePosition(..., { bool allowInDebug = false, ... })
// if (kDebugMode && !kEnableStockfishInDebug && !allowInDebug) -> empty cancelled eval
```

`package:stockfish` parks isolates in blocking native FFI. A hot restart cannot kill those isolates, so restart hangs forever if the engine was started. There is no pre-hot-restart dispose hook.

**Board analysis must keep `allowInDebug` default false.**  
**Only Game Review** (and similar explicit report workflows) may pass `allowInDebug: true`.

Arun added:

```dart
const bool _allowBoardStockfishInDebug = true;
// ...
StockfishSingleton().evaluatePosition(..., allowInDebug: _allowBoardStockfishInDebug, ...);
```

That bypassed the kill switch for every board eval in debug → hot restart hangs return.

### Other behavioral churn in the same PR (also reverted)

Not all of this is the hot-restart smoking gun, but it all shipped together and was rolled back as one unit:

| Change | Effect |
|--------|--------|
| `hasCompleteUsableBoardEval` requires full MultiPV count | More aggressive “incomplete → restart” decisions |
| `cloudEvalSkipsBoardStockfish` requires enough usable PVs | Less cloud short-circuit → more local engine work |
| PV preview re-evaluates after cancel instead of freezing engine | Undoes lichess-style “engine frozen while stepping PV” |
| Review sheet defers board eval; no force on close | Lifecycle races with `onBecameVisible` |
| Post-frame `_syncExpandedGameProvidersAfterFrame` | Delayed game list / page index provider updates |
| PV list `slotCount` polish, quieter classification logs | Cosmetic only |

### Was anything worth keeping?

Judged **no** as a clean cherry-pick on top of the intentional debug policy. Only maybe-interesting piece later: nested PV prefix trim + illegal-move guard for nested PV side-to-move. That should be a **small targeted fix** if product still sees a nested-PV bug — not a full engine lifecycle rewrite.

---

## What we did

### 1. Revert (committed, not pushed)

```
6ec084c0 Revert "Merge pull request #276 from Chessever/feat/game-analysis"
```

- Reverts merge `4e74d49b` with `-m 1` (back to first parent `63d2555f`).
- Applied cleanly; later miniatures time-bonus work in `chess_board_screen_provider_new.dart` (`applySecondaryBonusToMoveClocks`) **preserved**.
- `flutter analyze` clean on touched board/eval files after revert.

Verified post-revert:

- No live `_allowBoardStockfishInDebug` / `chessBoardEvaluationSchedulingEnabledProvider` / `_refreshPreviewPvsAfterCancellation` code paths.
- PV freeze comments and `setGameReviewVisible` → `_updateEvaluation(force: true)` restored.
- `kEnableStockfishInDebug == false` intact.

### 2. Code guardrails (local WIP, not in the revert commit)

Comments added so agents don’t “fix empty debug PVs” again:

- `stockfish_singleton.dart` — banner on `kEnableStockfishInDebug`, `allowInDebug`, debug early-return, `warmUp`
- `chess_board_screen_provider_new.dart` — board `evaluatePosition` call: do **not** pass `allowInDebug: true`
- `game_analysis_report.dart` — marks Game Review as the **only** intentional opt-in

### 3. Agent docs (local WIP)

Same policy section added to both:

- `CLAUDE.md`
- `AGENTS.md`

Section title: **Stockfish in debug (DO NOT "fix")**.

---

## Current git state (as of handoff write)

```
branch: stable
ahead of origin/stable by 1 commit: 6ec084c0 (the revert)

Uncommitted / unrelated-to-push-check:
 M AGENTS.md                          # stockfish agent note
 M CLAUDE.md                          # stockfish agent note
 M lib/.../stockfish_singleton.dart   # guardrail comments
 M lib/.../chess_board_screen_provider_new.dart  # guardrail comment
 M lib/.../game_analysis_report.dart  # guardrail comments
 M lib/.../chess_board_screen_new.dart  # pre-existing local WIP (board frame layout work)
?? test/game_selector_board_frame_layout_test.dart  # pre-existing local WIP

Note: CLAUDE.md / AGENTS.md are tracked on origin/stable and currently carry
local assume-unchanged (git ls-files -v shows "H"). They are pushed as files;
local edits may not always surface cleanly until that bit is cleared if someone
wants to commit them.
```

---

## Intentional design (do not regress)

1. **Debug board Stockfish is intentionally inert.** Empty eval bar / MultiPV in a debug session is expected.
2. **Hot restart must keep working** for day-to-day development.
3. **Release / profile** still run real Stockfish (guards are `kDebugMode`-gated / tree-shaken).
4. **Game Review** may use `allowInDebug: true` so reports remain testable in debug.
5. Related product history / know-how may also live under `docs/HOT_RESTART_KNOW_HOW.md` — check that for broader restart context.

If a future PR claims to “make board engine work in debug” or “stabilize Stockfish for hot reload,” treat it as high-risk and reject unless it preserves the kill switch and does not start the native engine on ordinary board analysis.

---

## Suggested next steps for the reviewing senior

1. **Read the revert:**  
   `git show 6ec084c0`  
   and the original damage:  
   `git show 0888f68a`
2. **Decide push:** push `6ec084c0` to `origin/stable` when ready (or open PR if process requires).
3. **Decide whether to commit guardrails + CLAUDE/AGENTS notes** as a separate small commit after the revert (recommended so teammates / agents see the policy).
4. **Device smoke (owner/QA, not agent-driven):**
   - Debug: hot restart on board screen must complete.
   - Debug: board PVs empty/inert is OK; Game Review engine still allowed.
   - Profile/release: eval bar + MultiPV stream; PV preview freezes engine while stepping (pre-Arun behavior).
5. **Talk to Arun:** PR #276 should not be re-merged without addressing the debug kill switch and without a product decision to re-litigate PV freeze vs re-eval.
6. **Do not re-land nested PV fixes** as a bulk port of #276; if nested PV STM is still broken, fix in a tiny PR with tests.

---

## Explicit non-goals of this session

- Did **not** re-apply any portion of #276.
- Did **not** push to remote.
- Did **not** run the app / flutter build (repo agent rules).
- Did **not** change CLAUDE/AGENTS remote tracking flags beyond normal file edits.

---

## Key commit map

```
origin/stable .................. 82f5a630 (and earlier miniatures/eval work)
6ec084c0 ....................... REVERT of PR #276  ← local tip of stable (ahead 1)
4e74d49b / 0888f68a ............ Arun bad PR (still in history, undone by revert)
```

Parent of merge (good base for “before Arun” board engine behavior on that line):

```
63d2555f  feat(game-review): gate free reports to one per day server-side
```

---

## One-line summary for standup

> Reverted Arun’s PR #276 that re-enabled Stockfish on the board in debug and broke hot restart; restored intentional debug kill switch; left guardrail comments/docs uncommitted; push of revert still pending.

---

## Full Grok CLI conversation transcript

Reconstructed from this session (Grok Build / CLI, branch `stable`, 2026-07-25). Tool internals abbreviated; substance preserved for senior review.

---

### Turn 1 — User

> my teammate arunn10 taught the stockfish etc. wasnt working in the app and caused hot restarts not working again with his fucking latest commits he did today, can u check and revert that stupidity.

### Turn 1 — Agent

Investigated git history for Arun’s work today:

- Found `0888f68a` — `fix(chessboard): stabilize engine suggestions and PV previews` (Arun)
- Found merge `4e74d49b` — `Merge pull request #276 from Chessever/feat/game-analysis`
- Files: board screen, `board_eval_restart_policy.dart`, `chess_board_screen_provider_new.dart` (~359 lines), `current_eval_provider.dart`, tests
- Later miniatures commit `d84c0746` touched the same provider only for move-40 clock bonus (`applySecondaryBonusToMoveClocks`) — keep that

Actions:

1. Stashed local WIP (`chess_board_screen_new.dart` + layout test)
2. `git revert -m 1 4e74d49b` → commit **`6ec084c0`**
3. Confirmed Arun symbols gone; clock-bonus still present
4. `flutter analyze` clean on reverted paths
5. Restored stash

Reported: stable ahead of origin by 1 (revert not pushed). Suggested device smoke for eval bar, PV freeze, hot restart.

---

### Turn 2 — User

> if he did anything meaningful we could consider but we were using kDebugMode to make sure those hot restart to not become stucking . they were all intentional

### Turn 2 — Agent

Re-read Arun’s diff against intentional design in `stockfish_singleton.dart`:

- `kEnableStockfishInDebug = false` by design
- Board analysis must leave `allowInDebug` at default **false**
- Only Game Review opts in with `allowInDebug: true`
- Native FFI isolates hang hot restart if engine is alive

Arun’s smoking gun:

```dart
const bool _allowBoardStockfishInDebug = true;
// passed as allowInDebug to evaluatePosition
```

Assessment table for the reviewing senior:

| Change | Worth keeping? |
|--------|----------------|
| `_allowBoardStockfishInDebug = true` | **No** — breaks intentional hot restart |
| Full MultiPV required for usable eval / cloud skip | **No** — more restart thrash |
| Re-eval during PV preview instead of freeze | **No** — undoes deliberate freeze |
| Defer eval while review sheet open | **No** — lifecycle races |
| Post-frame game-provider sync | **No** — delayed identity/index updates |
| Nested PV prefix trim + illegal-move guard | **Maybe later**, only if nested PV STM still broken |
| PV slotCount polish / quieter logs | Cosmetic only |

Conclusion: revert stands; don’t salvage #276 wholesale; nested PV only as a tiny future PR if needed.

---

### Turn 3 — User

> put a comment for feature that no LLM touches this. careless vibecoding can cause this issues pop up in the future again

### Turn 3 — Agent

Added LLM/agent guardrails at choke points:

1. **`stockfish_singleton.dart`**
   - Large “DO NOT TOUCH — LLM / AGENT / VIBECODE GUARDRAIL” banner on `kEnableStockfishInDebug`
   - Explicit NEVER list (including `_allowBoardStockfishInDebug` footgun)
   - Shorter guards on `allowInDebug` param, debug early-return, `warmUp`
2. **`chess_board_screen_provider_new.dart`**
   - Comment on board `evaluatePosition` call: do not pass `allowInDebug: true`
3. **`game_analysis_report.dart`**
   - Comments that Game Review’s `allowInDebug: true` is the intentional exception only

`flutter analyze` clean. Left uncommitted (local WIP on top of revert).

---

### Turn 4 — User

> put this as a note in claude.md and agents.md as well we purposefully deactivate stockfish in debug mode because hot restart/reload doesnt work with it. also, can u check if claude.md and agents.md being pushed(dont change its git status, just check)

### Turn 4 — Agent

**Docs:** Added section **“Stockfish in debug (DO NOT fix)”** to both `CLAUDE.md` and `AGENTS.md` (same content as agent policy).

**Push / tracking check only (no intentional status mutation):**

| | |
|--|--|
| Tracked names | `CLAUDE.md`, `AGENTS.md` |
| On `origin/stable`? | **Yes** — both present, identical content on remote before edit |
| Ignored? | No |
| Local flag | `H` = **assume-unchanged** on both |
| After edit | Working tree modified; HEAD/origin still old content until commit+push |

Note: after writing the notes, `git status` showed `M CLAUDE.md` / `M AGENTS.md` (content edit). Did not stage/commit/push; did not clear assume-unchanged for the check.

---

### Turn 5 — User

> okay now we reverted arunn10's trashy changes correct?

### Turn 5 — Agent

**Yes.** Confirmed:

- Revert commit: `6ec084c0`
- Undid `0888f68a` / merge `4e74d49b`
- No live Arun bypass symbols
- Intentional `kEnableStockfishInDebug = false` + `allowInDebug` default false intact
- `stable` ahead of `origin/stable` by 1 (revert only)
- Uncommitted: guardrail comments, agent docs, pre-existing board layout WIP

---

### Turn 6 — User

> please turn this convo ina  handoff file i want anothe senior to observe.

### Turn 6 — Agent

Created this handoff at:

`docs/stockfish_hot_restart_arun_revert_handoff_2026-07-25.md`

Structured for senior review: TL;DR, root cause, file list, what was kept, current git state, intentional design, next steps, commit map.

---

### Turn 7 — User

> can u put this whole grok cli convo in it as well?

### Turn 7 — Agent

Appended this full conversation transcript section to the same handoff file.

---

### End of transcript

**Session outcome snapshot:**

| Item | Status |
|------|--------|
| PR #276 revert | Committed as `6ec084c0`, **not pushed** |
| Code guardrails | Working tree only |
| CLAUDE.md / AGENTS.md notes | Working tree only |
| Pre-existing board frame layout WIP | Unrelated; still local |
| Runtime/device verification | Deferred to humans (repo rule) |

---

## Senior review addendum (2026-07-25)

Second pass over the revert, plus two live bugs found and fixed.

### 1. Revert verdict: correct and complete

Mechanically verified rather than eyeballed — every file PR #276 touched, diffed
against the pre-Arun base `63d2555f`:

| File | vs pre-Arun base |
|------|------------------|
| `chess_board_screen_new.dart` | identical |
| `provider/board_eval_restart_policy.dart` | identical |
| `provider/current_eval_provider.dart` | identical |
| `test/board_eval_restart_policy_test.dart` | identical |
| `provider/chess_board_screen_provider_new.dart` | +9 / -1 — **exactly** the miniatures move-40 clock bonus (`applySecondaryBonusToMoveClocks`, Trello #1005) from `d84c0746`, intentionally preserved |

Stockfish policy confirmed intact: `kEnableStockfishInDebug = false`; the only
live `allowInDebug: true` callers are in `game_analysis_report.dart` (Game
Review — the sanctioned exception); no `_allowBoardStockfishInDebug` anywhere.

**Doc correction:** this handoff lists
`test/board_expand_provider_stability_test.dart` as "new; removed by revert".
It is neither — it predates Arun (added in `80bb88fc`), is still tracked at
HEAD, and was simply restored to its pre-Arun content. `hasCompleteUsableBoardEval`
and `cloudEvalSkipsBoardStockfish` likewise pre-date #276; Arun changed their
bodies, he did not introduce them.

### 2. The revert over-reached by one hunk (crash, now fixed)

Both "worth keeping?" tables above score
`_syncExpandedGameProvidersAfterFrame` as **No — delayed identity/index
updates**. That judgment was wrong: it was the one genuinely correct fix in
#276, and reverting it reintroduced a hard runtime error.

`ChessBoardScreenNew.didUpdateWidget` was writing
`chessBoardAllGamesProvider` / `currentlyVisiblePageIndexProvider` inline.
`didUpdateWidget` runs inside `BuildOwner.buildScope`'s element-update phase,
where Riverpod asserts `_debugCanModifyProviders`:

```
StateNotifierListenerError ... Tried to modify a provider while the widget
tree was building.
#7  _ChessBoardScreenState.didUpdateWidget (chess_board_screen_new.dart:1446)
```

Reproduces every time `_ExpandingChessBoardScreen` swaps its entry subset for
the full-event list (For You / favorites / countrymen open path).

**Fix:** restored `_syncExpandedGameProvidersAfterFrame` — post-frame, with
Arun's `identical(widget.games, games)` staleness guard *plus* a new
`_currentPageIndex == desiredIndex` guard so a concurrent `_handlePageChange`
can't be clobbered with a stale index. Matches what `initState` (line ~858) and
`didChangeDependencies` (line ~1505) already do for the same reason.

A full-repo sweep of `initState` / `didChangeDependencies` / `didUpdateWidget`
for provider mutations found **no other** unguarded site — every other one
(`chess_board_screen_new.dart` 858 / 1505 / 8245 / 9673,
`twic_contents_screen.dart` 77) is already post-frame or microtask deferred.

### 3. Unrelated: engine dead on notification / deep-link opens (fixed)

Reported separately by product: opening the board **from a notification** left
the engine inert, while opening it normally worked. Not Arun's; long-standing.

Same invariant, different violator. `ChessBoardProviderParams` identity is
**gameId-only** — `index` lives on the notifier and is corrected *only* by
`syncPageIndex`, which is called *only* from `ChessBoardScreenNew.didUpdateWidget`.

`_DeepLinkedChessBoardRoute` (`deep_link_service.dart`) opens on a 1-game list,
then hydrates the full round list via `setState`. Its key was:

```dart
key: ValueKey('deep-link-${widget.initialGameId}-${_games.length}')
```

The `_games.length` term flipped 1 → N on hydrate, so Flutter **remounted**
`ChessBoardScreenNew` instead of updating it. `didUpdateWidget` never ran →
`syncPageIndex` never ran → the surviving gameId-keyed notifier kept `index = 0`
while `currentlyVisiblePageIndexProvider` moved to the game's real round index.
Both eval gates then rejected every request:

```
🚫 EVAL:  Skipping evaluation for non-visible game (page 0, visible: 4)
🚫 PARSE: Skipping evaluation for non-visible game (page 0, visible: 4)
```

The normal open path (`_ExpandingChessBoardScreen`) carries **no key**, updates
in place, and is fine — hence the exact asymmetry product reported.

**Fix:** key is now `ValueKey('deep-link-${widget.initialGameId}')`, stable
across hydrate. Audited all 14 `ChessBoardScreenNew` call sites; the other 12
build once inside a `MaterialPageRoute.builder` with no live list mutation, so
none can remount this way.

### 4. Regression guards

`test/board_expand_provider_stability_test.dart` (structural contract test, 31
cases, green) now also asserts:

- `chess_board_screen_new.dart` contains `_syncExpandedGameProvidersAfterFrame`
  — a future blanket revert cannot silently re-inline those writes.
- the deep-link board key does not vary with the games list.

`flutter analyze` clean on all touched files. **Runtime verification is still
owner/QA** (repo rule): confirm hot restart on the board in debug, and confirm
the eval bar + MultiPV stream after opening the board from a push notification
in profile/release.
