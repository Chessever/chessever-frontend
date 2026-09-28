# Report game types: discussion draft

Status: proposed, awaiting the user's choice of types. This document does not
enable classifications, alter reports, add database columns, or authorize a
deployment. The requested end state remains: classify existing reported games
once, classify future Cloudflare reports, persist the result additively, and
show it in Reports while preserving the Miniatures card design.

## Product model

A game has a story and an independent length label. It may match several story
types, but the card shows one main story. Filtering can match its other types.
Examples: `Comeback · 22 moves`, `Upside Down · 94 moves`. Miniature and Marathon
can be filter choices without filling every card with additional badges.

### Proposed core stories

| Type | Meaning | Important distinction |
| --- | --- | --- |
| Domination | The winner takes control early and maintains a substantial advantage. | A balanced game settled by one late mistake is not domination. |
| Upside Down | Substantial advantages pass from one player to the other repeatedly. | Require at least two genuine reversals; tiny changes around equality do not count. |
| Comeback | The eventual winner had a clearly losing position and recovered. | One sustained reversal can be enough. An ordinary small disadvantage is not a comeback. |
| One Blunder | A major mistake changes a competitive position into a lasting loss. | Count the decisive mistake, not the game's total number of blunder annotations. Later harmless errors in an already lost position should not disqualify it. |
| Great Escape | A player who was clearly losing saves a draw. | A recovered win is a Comeback. A drawn result alone proves no escape. |

### Optional additions

| Type | Meaning | Reason to calibrate carefully |
| --- | --- | --- |
| Squeeze | The winner develops a small edge gradually and converts it. | A jagged curve is not automatically sustained pressure; this needs sustained evidence across a meaningful part of the game. |
| Deadlock | A drawn game stays broadly balanced without a sustained winning advantage. | This says nothing about whether the game was exciting, accurate, or easy to play. |

Unclassified games remain available in All Reports. Every game does not need a
dramatic story. Missing analysis is different from a complete report with no
distinctive story.

## Overlap and presentation

Illustrative courses, not real game measurements:

- White winning → Black winning → White winning: Upside Down; also a Comeback
  if White wins after a genuinely losing stretch.
- Black winning → White winning → White wins: Comeback.
- Balanced → Black blunders → White winning through the finish: One Blunder.
- Black winning → balanced → draw: Great Escape for White.
- White's small edge → increasing control → White wins: Squeeze, if included.

Proposed display precedence when multiple types apply:

1. Upside Down, for repeated changes of control.
2. Comeback or Great Escape, according to the result.
3. One Blunder, for the defining mistake.
4. Squeeze or Domination, with Squeeze using the more specific gradual pattern.
5. Deadlock, only for drawn games that meet its balanced-course rule.

This precedence controls only the card's main label. Other supported types stay
available for filters. Store the relevant move numbers with each finding so a
label can be explained using an actual moment in the game.

## Length labels

- Miniature: decisive and short. The user's new wording is **under 25 moves**.
  The existing Miniatures screen says **25 moves or fewer**, so the boundary
  needs an explicit decision before implementation. Do not silently alter the
  existing Miniatures feature.
- Marathon: **80 moves or more** is a proposed starting threshold, not an
  accepted requirement.
- Ordinary lengths need no extra label; their move count is enough.
- Count complete mainline games. A seven-move excerpt beginning from a custom
  position at move 40 must not become a Miniature. A short draw is not a
  Miniature either.

## What current evidence supports

The Cloudflare runner evaluates the initial position and every played position.
Its report JSON contains the result PGN, per-move verdicts, centipawn/mate
evaluations, and an evaluation sequence from White's perspective. The PGN
writeback carries per-move evaluations and ChessEver NAGs. These are inputs for
game-story classification without another engine run when coverage is complete.

Relevant current sources:

- `../chessever_cloudflare/apps/analysis/container/dart/lib/report_runner.dart`
- `../chessever_cloudflare/apps/analysis/container/dart/lib/report_json.dart`
- `../chessever_cloudflare/apps/analysis/src/report-writeback.ts`
- `lib/screens/for_you/discovery/data/discovery_repository.dart`

The existing captured engine response in
`test/fixtures/server_game_report.json` supplies a concrete reference:

- Seven half-moves and eight evaluated positions, including the initial board.
- After `3.Qh5`, the evaluation is -0.34 from White's perspective.
- `3...Nf6` is classified as a blunder and changes the evaluation to mate for
  White; `4.Qxf7#` ends the game.
- The proposed outcome is **One Blunder + Miniature**, with `3...Nf6` as the
  decisive move. A blanket requirement for many moves of advantage after the
  blunder would incorrectly exclude this clear short-game example.

This is a captured report, inspected locally. It is not a newly run engine
analysis or evidence that all proposed types have been calibrated on real games.

## Reliability requirements for the eventual classifier

- Use the existing evaluation convention, including mate handling. Its
  `winPercentage` is the report's transformed evaluation scale, not a measured
  probability that this particular player will win.
- Require substantial and sustained advantages. Use separate enter/exit
  thresholds so minor oscillations do not become reversals.
- Distinguish a brief evaluation spike from an established losing stretch.
  Preserve sharp decisive events; indiscriminate smoothing could erase the
  very blunder being classified.
- Evaluate the actual mainline and result. Side variations and evaluations
  quoted in prose are not played events.
- Preserve missing evaluations as missing. The current Reports reader accepts
  even one annotated move, which is enough to discover a report but not enough
  to classify the whole course. PGN-only reports also lack an initial-position
  evaluation. Never bridge missing samples into an invented turning point.
- Result-only ending facts do not prove a blunder, comeback, or clock loss.
  Do not infer Time Trouble, Sacrifice, Attack, or tactical motifs from the
  evaluation curve alone.
- Do not base the core types on accuracy or estimated rating: hydrated PGN
  reports explicitly lack those values, whereas full engine reports have them.
- Test opposite colors, mates, near-threshold noise, temporary recoveries,
  missing samples, custom starts, and length boundaries before backfilling.
- Calibrate on more completed games before describing thresholds as reliable.
  The one local captured response verifies an input and one concrete case,
  not the distribution or accuracy of the proposed classification system.

## Additive implementation contract after the types are settled

The intended extension is optional classification metadata in an extra nullable
column, as requested. Existing readers and writers must continue to work when
that field is absent or null. No database triggers are part of this proposal.

Keep game-story rules separately versioned from move-quality verdicts. Compute
them from an existing completed report without changing the engine, its move
classifier, saved PGN, or report-generation success conditions. If an eventual
implementation changes report bytes, the Cloudflare repository's report-version
guard and version-bump rules still apply.

The one-time backfill and future generation must use the same rules and inputs.
Backfill should be resumable in small batches, skip unchanged classified inputs,
and write only the new metadata. Bind metadata to the analyzed input so an old
label cannot silently describe a changed game or different evaluation sequence.
Classification failure must not discard a successfully generated report.

Reports keeps its current infinite pagination and Miniatures card layout.
Classification filters must page through matching results rather than filtering
only whatever happens to be loaded in the app. Unclassified reports remain
browsable. Exact persistence/query design and deployment target remain to be
reviewed after the user settles the types.
