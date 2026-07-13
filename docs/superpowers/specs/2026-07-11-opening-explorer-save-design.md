# Opening Explorer Save Action Design

## Goal

Replace the Opening Explorer app bar's ambiguous **Done** action with a save
icon that starts the existing analysis-save flow for the complete explorer PGN,
including its variations.

## Interaction

- Show a standard `Icons.save_outlined` app-bar action in place of the current
  **Done** pill.
- Use **Save analysis** as the tooltip and semantic label.
- On tap, export the explorer game with `exportGameToPgn`, open that generated
  game in the analysis board at its last move, and immediately present the
  existing Save Analysis sheet once the board state is ready.
- Leave the analysis board open when the sheet is dismissed or saving
  completes so the user can continue reviewing or editing the generated PGN.

## Architecture and Data Flow

The explorer remains responsible for generating the PGN-backed
`GamesTourModel`. It passes a one-shot `showSaveAnalysisOnLoad` intent to
`ChessBoardScreenNew`. The board consumes that intent after its provider state
has loaded and invokes the same `showSaveAnalysisSheet` entry point as its
normal app-bar save action.

The Save Analysis sheet remains the single owner of authentication, database
selection, persistence, free-tier limits, and subscription paywall behavior.
No parallel save implementation is added to the explorer.

## Failure and Re-entry Behavior

- If the explorer game is unavailable, tapping Save remains a no-op, matching
  the existing Done behavior.
- If board state is still loading, the one-shot intent waits for a usable state
  rather than showing an empty or invalid sheet.
- The automatic sheet is presented at most once for each pushed analysis-board
  route. Dismissing it does not reopen it on rebuild.
- Authentication cancellation or paywall cancellation leaves the analysis
  board available and does not persist an analysis.

## Test and Automation Contract

- Rename `E2eIds.openingExplorerDoneButton` to
  `E2eIds.openingExplorerSaveButton` and update Patrol usage.
- Add focused coverage for the one-shot automatic-save intent where practical.
- Validate touched Dart files with `flutter analyze --no-pub`; do not build or
  run the application.

## Out of Scope

- Redesigning or duplicating the Save Analysis sheet.
- Changing free-tier limits or paywall policy.
- Changing the Board Editor's separate Done action.
