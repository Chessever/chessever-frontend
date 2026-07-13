# Default-Collapsed Library Annotations

## Goal

When a user opens a freshly imported PGN or a saved game from the Library, every notation comment starts collapsed. The user can expand and collapse individual annotations normally after opening the game.

## Scope

The collapsed default applies to board games whose source is `GameSource.boardEditor` (fresh PGN imports) or `GameSource.savedAnalysis` (games opened from the Library). Live broadcasts, Gamebase games, opening-explorer games, and other board sources retain the existing comment presentation.

## Design

The moves display derives the behavior directly from the current game's source and reuses its existing set of expanded comment IDs.

For affected sources, each comment initially renders as a compact `Annotation` row with a chevron. Existing interaction rules remain unchanged except where needed for the collapse control:

- A tap expands that annotation and reveals its full text.
- Tapping the expanded annotation collapses it again.
- Long-pressing continues to open the comment editor.
- When the notation game changes, expanded annotation state resets so the new game starts collapsed.
- PGN variation collapsing remains unchanged.

## Validation

Run `flutter analyze --no-pub` against the touched Dart file. Do not run or build the app; on-device verification remains with the user.
