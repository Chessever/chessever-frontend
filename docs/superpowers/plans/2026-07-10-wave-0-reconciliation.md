# ChessEver V2 — Wave 0 reconciliation record

Date: 2026-07-10
Status: Wave 0 audits in progress

Authority:

- [`docs/CHESSEVER_V2_MASTER_HANDOFF.md`](../../CHESSEVER_V2_MASTER_HANDOFF.md)
- [`docs/superpowers/specs/2026-07-10-my-space-design.md`](../specs/2026-07-10-my-space-design.md)
- [`docs/superpowers/plans/2026-07-10-chessever-v2-implementation-plan.md`](2026-07-10-chessever-v2-implementation-plan.md)

This record captures the immutable starting point and will receive the reconciled ownership
and contract decisions from the parallel Wave 0 audits before production workers begin.

## Repository baselines

| Repository | Starting commit | Starting worktree |
| --- | --- | --- |
| `chessever-frontend` | `363bf9f932f51a62f253465604253a5ab9616b67` | 18 pre-existing modified screen files, all reserved in the execution plan |
| `chessever_frontend_desktop` | `0cabd1e438b525b161de9617ed424169b13a1a23` | clean |
| `chessever_data_hub_monorepo` | `866d8cc197f3cb5f568496452d61488457a784ef` | clean |
| `chessever_gamebase` | `77138641140f34a131edbafbb1c19351eff57be6` | clean |

The 18 mobile files are fingerprinted by their starting Git blob IDs and line deltas in
the coordinator session. No worker may edit them until the coordinator assigns an exact
file after reviewing its existing diff.

## Static-analysis baseline

The untouched mobile repository reports 389 findings under whole-repository
`flutter analyze --no-pub`. The failures include pre-existing patrol/library test API drift
and vendored `third_party/chessground` example/test dependency failures. Whole-repository
analysis is therefore not a useful pass/fail signal for V2 slices.

The 18 reserved modified screens report no analyzer errors and eight warnings:

- one unused import in `countryman_games_screen.dart`;
- two unused private declarations and one unused optional parameter across the Gamebase
  explorer and smart-event screen;
- one unused local in `book_preview_screen.dart`;
- one unused theme import in `pgn_import_preview_screen.dart`;
- one unused private declaration and one unused local in `score_card_screen.dart`.

Workers must use scoped `flutter analyze --no-pub <touched paths>` plus relevant tests and
must not absorb unrelated baseline cleanup into their feature slices.

## Active audit assignments

The first fleet consists of six independent read-only audits:

1. mobile V2 shell and My Space composition;
2. Studies service and Flutter contract;
3. Miniatures desktop-to-mobile parity;
4. Supabase user state and premium authorization;
5. Liquid Glass and independent light/dark coverage;
6. desktop Players preparation workspace.

No audit agent has permission to edit, stage, commit, push, deploy, migrate, restart, run a
Flutter app, or run a Flutter build. Production worker scopes will be issued only after
their evidence is reconciled into this record.
