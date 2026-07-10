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

  test('Settings exposes appearance switch and root watches themeModeProvider', () {
    final settings = read('lib/screens/settings/settings_page.dart');
    final main = read('lib/main.dart');
    expect(settings, contains('GlassSwitch'));
    expect(settings, contains('themeModeProvider'));
    expect(settings, contains('Appearance'));
    expect(main, contains('ref.watch(themeModeProvider)'));
    expect(main, isNot(contains('const themeMode = ThemeMode.dark')));
  });
}
