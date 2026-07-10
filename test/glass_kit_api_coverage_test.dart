import 'dart:io';

import 'package:chessever2/widgets/liquid_glass/glass_loading.dart';
import 'package:chessever2/widgets/liquid_glass/search_expand_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Proves shipped adapters exist and bind real package entry points.
void main() {
  final root = Directory.current.path;
  String read(String rel) => File('$root/$rel').readAsStringSync();

  test('glass_kit re-exports package + app adapters', () {
    final kit = read('lib/widgets/liquid_glass/glass_kit.dart');
    expect(kit, contains("export 'package:liquid_glass_widgets/liquid_glass_widgets.dart'"));
    expect(kit, contains('glass_feedback.dart'));
    expect(kit, contains('glass_loading.dart'));
    expect(kit, contains('glass_island_search.dart'));
  });

  test('expanded island search uses package GlassSearchBar', () {
    final search = read('lib/widgets/liquid_glass/glass_island_search.dart');
    expect(search, contains('GlassSearchBar('));
    expect(search, contains('showsCancelButton: true'));
    expect(search, contains('useOwnLayer: true'));
  });

  test('home uses contentAwareBrightness + GlassTabBar.searchable + GlassBadge', () {
    final home = read('lib/screens/home/home_screen.dart');
    final events = read('lib/screens/group_event/group_event_screen.dart');
    final nav = read('lib/screens/home/widget/bottom_nav_bar.dart');
    expect(home, contains('contentAwareBrightness: true'));
    expect(home, contains('showGlassConfirmDialog'));
    expect(nav, contains('GlassTabBar.searchable'));
    expect(events, contains('GlassBadge('));
  });

  test('settings appearance uses GlassListTile.standalone + GlassSwitch sibling', () {
    final settings = read('lib/screens/settings/settings_page.dart');
    expect(settings, contains('GlassListTile.standalone'));
    expect(settings, contains('GlassSwitch('));
    // Must not nest switch inside GroupedSection children.
    expect(settings, isNot(contains('trailing: GlassSwitch')));
  });

  test('GlassLoading and feedback adapters compile against package types', () {
    // Type-level smoke: constructors are real package entry points.
    const loading = GlassLoading.circular(size: 24);
    expect(loading, isA<GlassLoading>());
    expect(GlassToastType.success, isNotNull);
    expect(GlassDialogAction, isNotNull);
    expect(searchExpandTargetWidth(available: 100, expanded: true), 100);
  });

  test('PACKAGE_SURFACE catalog documents full public categories', () {
    final doc = read('lib/widgets/liquid_glass/PACKAGE_SURFACE.md');
    for (final name in [
      'GlassScaffold',
      'GlassTabBar.searchable',
      'GlassSearchBar',
      'GlassSegmentedControl',
      'GlassDialog',
      'GlassToast',
      'GlassSheet',
      'GlassProgressIndicator',
      'GlassListTile',
      'GlassSwitch',
      'GlassBadge',
      'GlassToolbar',
      'GlassMenu',
      'GlassModalSheet',
      'GlassPopover',
      'GlassTextField',
      'GlassSlider',
    ]) {
      expect(doc, contains(name), reason: 'catalog missing $name');
    }
  });
}
