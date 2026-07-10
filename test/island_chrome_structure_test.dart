import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural gates for island chrome + searchable bottom bar + theme.
void main() {
  final root = Directory.current.path;
  String read(String rel) => File('$root/$rel').readAsStringSync();

  test('Events top is island-only (no permanent EnhancedRoundedSearchBar slab)', () {
    final events = read('lib/screens/group_event/group_event_screen.dart');
    expect(events, contains('GlassIslandTopBar'));
    expect(events, contains('GlassAvatarIsland'));
    expect(events, isNot(contains('EnhancedRoundedSearchBar')));
    // Search driven from home bottom morph.
    expect(events, contains('homeBottomSearchTextProvider'));
  });

  test('Home bottom bar uses GlassTabBar.searchable morph', () {
    final nav = read('lib/screens/home/widget/bottom_nav_bar.dart');
    expect(nav, contains('GlassTabBar.searchable'));
    expect(nav, contains('GlassSearchBarConfig'));
    expect(nav, contains('isSearchActive'));
    // Avoid full-bleed left slab: fixed tabWidth + blend off.
    expect(nav, contains('tabWidth:'));
    expect(nav, contains('enableBlend: false'));
  });

  test('Calendar/Library/Players use expanding island search', () {
    final cal = read('lib/screens/calendar/calendar_screen.dart');
    final lib = read('lib/screens/library/library_screen.dart');
    final players = read('lib/screens/players/player_screen.dart');
    for (final src in [cal, lib, players]) {
      expect(src, contains('GlassIslandSearch'));
      expect(src, contains('GlassIslandTopBar'));
    }
  });

  test('Player profile uses glass island top chrome (not IconButton slab)', () {
    final profile = read(
      'lib/screens/player_profile/player_profile_screen.dart',
    );
    expect(profile, contains('GlassBackButton'));
    expect(profile, contains('GlassIslandTopBar'));
    expect(profile, contains('GlassIconButton'));
    // Material IconButton (not GlassIconButton) should be gone from chrome.
    expect(
      RegExp(r'(?<![A-Za-z])IconButton\(').hasMatch(profile),
      isFalse,
    );
  });

  test('Tournament EventSearchBar + calendar detail are expand-on-tap islands', () {
    final eventSearch = read(
      'lib/screens/tour_detail/widgets/event_search_bar.dart',
    );
    final calDetail = read('lib/screens/calendar/calendar_detail_screen.dart');
    expect(eventSearch, contains('GlassIslandSearch'));
    expect(eventSearch, isNot(contains('SimpleSearchBar')));
    expect(eventSearch, isNot(contains('color: context.colors.surfaceRecessed')));
    expect(calDetail, contains('GlassIslandSearch'));
    expect(calDetail, contains('GlassBackButton'));
    expect(calDetail, isNot(contains('SimpleSearchBar')));
  });

  test('bottom nav tabWidth is compact per-tab slot (~72, not 210)', () {
    final nav = read('lib/screens/home/widget/bottom_nav_bar.dart');
    expect(nav, contains('static const double tabWidth = 72'));
    expect(nav, contains('tabWidth: BottomNavBar.tabWidth'));
    expect(nav, isNot(contains('tabWidth: 210')));
    // E2e overlay sized to pill, not full-bleed right: pad+64.
    expect(nav, contains('width: pillW'));
    expect(nav, contains('pillWidthFor'));
    expect(nav, isNot(contains('right: BottomNavBar.horizontalPadding + 64')));
  });

  test('Settings exposes appearance switch and root watches themeModeProvider', () {
    final settings = read('lib/screens/settings/settings_page.dart');
    final main = read('lib/main.dart');
    expect(settings, contains('GlassSwitch'));
    expect(settings, contains('themeModeProvider'));
    expect(settings, contains('Appearance'));
    expect(main, contains('ref.watch(themeModeProvider)'));
    expect(main, isNot(contains('const themeMode = ThemeMode.dark')));
  });

  test('page titles are compact GlassTitleChip beside back (not full-line)', () {
    final favorites = read('lib/screens/favorites/favorites_tab_screen.dart');
    final countrymen = read('lib/screens/countrymen/countrymen_tab_screen.dart');
    final settings = read('lib/screens/settings/settings_page.dart');
    final profile = read(
      'lib/screens/player_profile/player_profile_screen.dart',
    );
    final titleChip = read('lib/widgets/liquid_glass/glass_title_chip.dart');
    final islandBar = read('lib/widgets/liquid_glass/glass_island_top_bar.dart');

    expect(titleChip, contains('class GlassTitleChip'));
    expect(titleChip, contains('GlassContainer'));
    expect(titleChip, contains('useOwnLayer: true'));
    expect(titleChip, contains('maxWidth'));

    // Title slot is flexible/loose — not Expanded full-bleed title.
    expect(islandBar, contains('this.title'));
    expect(islandBar, contains('FlexFit.loose'));

    for (final src in [favorites, countrymen, settings, profile]) {
      expect(src, contains('GlassTitleChip'));
      expect(src, contains('GlassIslandTopBar'));
      expect(src, contains('GlassBackButton'));
    }

    // Favorites no longer centers a full-line title between back and spacer.
    expect(favorites, isNot(contains('Expanded(\n              child: Center')));
    expect(favorites, contains("label: 'Favorites'"));
  });
}
