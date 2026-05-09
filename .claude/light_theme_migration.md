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
   board square colors, last-move highlights, etc.)

The `k*Color` constants are kept as-is for backward compatibility and for
intentional cross-theme values. Migration rewrites the chrome to
`context.colors.*`.

## Per-screen status

Search command to find candidates:
`grep -l "kBackgroundColor\|kBlack2Color\|kBlack3Color\|kWhiteColor70\|kPopUpColor\|kDividerColor\|kSecondaryTextColor" lib/screens/<dir>`

### Screens

- [x] `lib/screens/chessboard/chess_board_settings_page.dart`
- [ ] lib/screens/authentication
- [ ] lib/screens/board_editor
- [ ] lib/screens/calendar
- [ ] lib/screens/chessboard (rest)
- [ ] lib/screens/countrymen
- [ ] lib/screens/countryman_games_screen.dart
- [ ] lib/screens/favorites
- [ ] lib/screens/gamebase
- [ ] lib/screens/group_event
- [ ] lib/screens/home
- [ ] lib/screens/library
- [ ] lib/screens/onboarding
- [ ] lib/screens/player_profile
- [ ] lib/screens/players
- [ ] lib/screens/premium
- [ ] lib/screens/premium_games
- [ ] lib/screens/splash
- [ ] lib/screens/standings
- [ ] lib/screens/tour_detail

### Widgets

- [x] lib/widgets/divider_widget.dart
- [x] lib/widgets/app_bar_with_title.dart
- [x] lib/widgets/generic_loading_widget.dart
- [ ] lib/widgets/hamburger_menu/hamburger_menu.dart (42 refs — heavy)
- [ ] lib/widgets/paywall/premium_paywall_sheet.dart (38 refs)
- [ ] lib/widgets/review_prompt/review_prompt_dialogs.dart (32 refs)
- [ ] lib/widgets/game_filter/eco_filter_dropdown.dart (29 refs)
- [ ] lib/widgets/* (~80 more)

## Notes

- `kPrimaryColor` (#0FB4E5) is a brand asset and stays identical across
  themes. Don't replace it with `context.colors.brand` at every site;
  reserve that helper for new code that explicitly wants a theme hook.
- Chess board square colors (`kBoardColor*`) are user-customizable through
  Board Theme picker and are NOT theme-dependent — they're chess-board
  aesthetics, not app chrome.
- Move-stat segment colors (`kMoveStatWhite/Draw/Black`) are chess-semantic
  and identical across themes.
- Last-move highlight (`kLastMoveHighlight*`) is chess-semantic.
