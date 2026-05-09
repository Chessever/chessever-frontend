# Light Theme Migration Status

This file tracks the multi-iteration migration from a fully-dark UI to a
dark + light theming system. The Ralph loop iterates through screens; this
doc is the authoritative checklist of what's done and what remains.

## Foundation (iteration 1)

- [x] `lib/theme/app_colors.dart` — `AppColors` ThemeExtension with semantic
      tokens for both dark and light palettes
- [x] `lib/theme/app_theme.dart` — proper `lightTheme` / `darkTheme` with the
      extension wired in via `extensions: [...]`
- [x] `lib/theme/theme_provider.dart` — `ThemeModeNotifier` persisted via
      SharedPreferences (`app.theme_mode.v1`)
- [x] `MaterialApp` already wired with `themeMode: themeMode` (lib/main.dart)
- [x] Theme switcher UI in `chess_board_settings_page.dart`

## Migration approach

Every file currently using the hardcoded dark constants
(`kBackgroundColor`, `kBlack2Color`, `kWhiteColor`, etc.) needs to either:

1. Resolve colors at build time via `context.colors.X` (preferred for app
   chrome — backgrounds, surfaces, dividers, text colors), OR
2. Keep using the constant when it represents a *semantic* value that should
   remain identical in both themes (brand colors, success/danger, chess
   board square colors, last-move highlights, etc.), OR
3. Keep using the constant when context is genuinely not available (a
   CustomPainter, a StateNotifier, a const declaration).

The `k*Color` constants are kept as-is in `app_theme.dart` for backward
compatibility and for intentional cross-theme values.

## Progress

- **kWhiteColor call sites**: down from ~1131 to ~407
- **kBlack* / dark constants**: down from ~250 to ~81
- **flutter analyze**: 0 errors
- **Major chrome migrated**: nav bars, drawer, hamburger menu, calendar,
  library, group_event, tour_detail, player profile, standings, countrymen,
  gamebase, favorites, premium, onboarding, auth, splash, paywall, dialogs,
  filters, search

## Top remaining files

These still have the most call sites to migrate:

- lib/screens/chessboard/chess_board_screen_new.dart (32)
- lib/screens/player_profile/tabs/player_about_tab.dart (21)
- lib/screens/gamebase/widgets/gamebase_filter_panel.dart (17)
- lib/screens/gamebase/gamebase_explorer_screen.dart (17)
- lib/screens/library/folder_contents_screen.dart (16)
- lib/screens/library/widgets/folder_card.dart (13)
- lib/screens/player_profile/tabs/player_games_tab.dart (12)
- lib/screens/player_profile/tabs/player_events_tab.dart (10)
- lib/screens/onboarding/onboarding_flow_screen.dart (9)
- lib/screens/group_event/widget/filter_popup/filter_popup.dart (9)

## Notes

- `kPrimaryColor` (#0FB4E5) is a brand asset and stays identical across
  themes. Don't replace it with `context.colors.brand` at every site.
- Chess board square colors (`kBoardColor*`) are user-customizable through
  Board Theme picker and are NOT theme-dependent.
- Move-stat segment colors (`kMoveStatWhite/Draw/Black`) are chess-semantic
  and identical across themes.
- Last-move highlight (`kLastMoveHighlight*`) is chess-semantic.
- The ChessBoard provider's `getMoveColor()` and similar State notifiers
  intentionally use `kWhiteColor` since they return colors before reaching
  a Widget with BuildContext — the Widget callers can rewrap if needed.
