# Default-Collapsed Library Variations

## Goal

When a user opens a freshly imported PGN or a saved game from the Library, every PGN variation starts collapsed. The user can expand and collapse individual variations normally after opening the game.

## Scope

The collapsed default applies to board games whose source is `GameSource.boardEditor` (fresh PGN imports) or `GameSource.savedAnalysis` (games opened from the Library). Live broadcasts, Gamebase games, opening-explorer games, and other board sources retain the existing depth-and-length collapse heuristic.

## Design

Add an explicit `collapseAllVariationsByDefault` input to the notation token builder. The moves display derives this input from the current game's source and passes it through every recursive token-building call.

For affected sources, each variation's default state is collapsed regardless of its depth or move count. Existing interaction rules remain unchanged:

- A manual expansion overrides the collapsed default.
- A second toggle returns the variation to its collapsed default.
- If the selected move is inside a variation, the existing forced-open behavior keeps its ancestor path visible.
- When the notation tree changes, manual collapse and expansion overrides continue to reset as they do today.

## Validation

Unit tests for the notation token builder will verify that:

- A short, shallow variation collapses when the new input is enabled.
- The same variation remains expanded under the existing default behavior.
- A manual expansion overrides the new collapsed default.
- Recursive/nested variations receive the same collapsed default.

Run `flutter analyze --no-pub` against the touched Dart files. Do not run or build the app; on-device verification remains with the user.
