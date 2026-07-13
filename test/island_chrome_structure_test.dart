import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural gates for the canonical liquid-glass chrome: cohesive package
/// surfaces (GlassTabBar.searchable, GlassSegmentedControl) instead of rows of
/// disconnected chip/button islands.
void main() {
  final root = Directory.current.path;
  String read(String rel) => File('$root/$rel').readAsStringSync();

  test('Events tabs glue at top, separate into icon chips on scroll', () {
    final events = read('lib/screens/group_event/group_event_screen.dart');
    // LiquidTabBar animates glued <-> separated; scroll drives it.
    expect(events, contains('LiquidTabBar('));
    expect(events, contains('ChromeScrollCollapse'));
    expect(events, contains('separated: tabsSeparated.value'));
    expect(events, contains('_categoryIcon'));
    expect(events, isNot(contains('EnhancedRoundedSearchBar')));
    // Search still driven from the home bottom morph.
    expect(events, contains('homeBottomSearchTextProvider'));
    expect(events, contains('homeBottomSearchFilterRequestProvider'));
  });

  test('Home bottom nav is the canonical GlassTabBar.searchable pill', () {
    final nav = read('lib/screens/home/widget/bottom_nav_bar.dart');
    expect(nav, contains('GlassTabBar.searchable('));
    expect(nav, contains('GlassSearchBarConfig('));
    // No hand-rolled island stack or bespoke motion tower.
    expect(nav, isNot(contains('GlassButton.custom')));
    expect(nav, isNot(contains('package:cue/cue.dart')));
    expect(nav, isNot(contains('package:motor/motor.dart')));

    final home = read('lib/screens/home/home_screen.dart');
    expect(home, contains('extendBody: true'));
    // Nav lives in the canonical scaffold slot, not a bodyOverlays hack.
    expect(home, contains('bottomBar: const BottomNavBar()'));
    expect(home, isNot(contains('bodyOverlays: [')));
  });

  test('Calendar + Library: bottom-nav search + floating controls over content', () {
    final cal = read('lib/screens/calendar/calendar_screen.dart');
    final lib = read('lib/screens/library/library_screen.dart');
    for (final src in [cal, lib]) {
      // No per-page search bar — search comes from the single bottom-nav field.
      expect(src, isNot(contains('GlassIslandSearch')));
      expect(src, contains('homeBottomSearchTextProvider'));
      expect(src, contains('Positioned.fill('));
    }
    // Calendar controls: mode pills + a glass filter button that opens a
    // liquid-glass dropdown (format + year).
    expect(cal, contains('_openCalendarFilter'));
    expect(cal, contains('GlassIconButton('));
    expect(cal, contains('CalendarFilterMode.'));
    // Library actions: morphing icon+text chips.
    expect(lib, contains('LiquidActionBar('));
    expect(lib, contains('ChromeScrollCollapse'));
  });

  test('Player profile uses glass island top chrome (not IconButton slab)', () {
    final profile = read(
      'lib/screens/player_profile/player_profile_screen.dart',
    );
    expect(profile, contains('GlassBackButton'));
    expect(profile, contains('GlassIslandTopBar'));
    expect(profile, contains('GlassIconButton'));
    // Material IconButton (not GlassIconButton) should be gone from chrome.
    expect(RegExp(r'(?<![A-Za-z])IconButton\(').hasMatch(profile), isFalse);
  });

  test(
    'Tournament EventSearchBar + calendar detail are expand-on-tap islands',
    () {
      final eventSearch = read(
        'lib/screens/tour_detail/widgets/event_search_bar.dart',
      );
      final calDetail = read(
        'lib/screens/calendar/calendar_detail_screen.dart',
      );
      expect(eventSearch, contains('GlassIslandSearch'));
      expect(eventSearch, isNot(contains('SimpleSearchBar')));
      expect(calDetail, contains('GlassIslandSearch'));
      expect(calDetail, contains('GlassBackButton'));
      expect(calDetail, isNot(contains('SimpleSearchBar')));
    },
  );

  test(
    'Settings exposes appearance switch and root watches themeModeProvider',
    () {
      final settings = read('lib/screens/settings/settings_page.dart');
      final main = read('lib/main.dart');
      expect(settings, contains('GlassSwitch'));
      expect(settings, contains('themeModeProvider'));
      expect(settings, contains('Appearance'));
      expect(main, contains('ref.watch(themeModeProvider)'));
      expect(main, isNot(contains('const themeMode = ThemeMode.dark')));
    },
  );

  test('mode tabs glue/separate via the shared LiquidTabBar', () {
    final floating = read(
      'lib/widgets/liquid_glass/glass_floating_segments.dart',
    );
    final liquid = read('lib/widgets/liquid_glass/liquid_tab_bar.dart');
    final favorites = read('lib/screens/favorites/favorites_tab_screen.dart');
    final countrymen = read(
      'lib/screens/countrymen/countrymen_tab_screen.dart',
    );
    final profile = read(
      'lib/screens/player_profile/player_profile_screen.dart',
    );
    final tour = read('lib/screens/tour_detail/tournament_detail_screen.dart');

    expect(floating, contains('class GlassFloatingSegments'));
    expect(floating, contains('LiquidTabBar('));
    expect(floating, contains('separated: !expanded'));
    // The single continuous morph (gaps + icon reveal), not a widget swap.
    expect(liquid, contains('class LiquidTabBar'));
    expect(liquid, contains('SingleMotionBuilder'));

    for (final src in [favorites, countrymen, profile, tour]) {
      expect(src, contains('GlassFloatingSegments'));
    }
  });

  test(
    'page titles are compact GlassTitleChip beside back (not full-line)',
    () {
      final favorites = read('lib/screens/favorites/favorites_tab_screen.dart');
      final countrymen = read(
        'lib/screens/countrymen/countrymen_tab_screen.dart',
      );
      final settings = read('lib/screens/settings/settings_page.dart');
      final profile = read(
        'lib/screens/player_profile/player_profile_screen.dart',
      );
      final titleChip = read('lib/widgets/liquid_glass/glass_title_chip.dart');
      final islandBar = read(
        'lib/widgets/liquid_glass/glass_island_top_bar.dart',
      );

      expect(titleChip, contains('class GlassTitleChip'));
      expect(titleChip, contains('useOwnLayer: true'));

      // Title slot is flexible/loose — not Expanded full-bleed title.
      expect(islandBar, contains('this.title'));
      expect(islandBar, contains('FlexFit.loose'));

      for (final src in [favorites, countrymen, settings, profile]) {
        expect(src, contains('GlassTitleChip'));
        expect(src, contains('GlassIslandTopBar'));
        expect(src, contains('GlassBackButton'));
      }
    },
  );
}
