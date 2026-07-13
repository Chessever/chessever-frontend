import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  String read(String rel) => File('$root/$rel').readAsStringSync();

  test('global search page is liquid glass with Players | Events tabs', () {
    final screen = read('lib/screens/search/global_search_screen.dart');
    expect(screen, contains('class GlobalSearchScreen'));
    expect(screen, contains('GlassSearchBar'));
    expect(screen, contains('GlassFloatingSegments'));
    expect(screen, contains("'Players'"));
    expect(screen, contains("'Events'"));
    expect(screen, contains('Recently Searched'));
    expect(screen, contains('supabaseCombinedSearchProvider'));
    expect(screen, contains('ScreenWrapper'));
    // Smooth enter: fade + soft lift, then keyboard focus.
    expect(screen, contains('PageRouteBuilder'));
    expect(screen, contains('FadeTransition'));
    expect(screen, contains('requestFocus'));
  });

  test('bottom nav search filters the active page in place (no dedicated screen)', () {
    final nav = read('lib/screens/home/widget/bottom_nav_bar.dart');
    // Typing drives the shared query provider; the active tab filters itself.
    expect(nav, contains('homeBottomSearchTextProvider'));
    expect(nav, contains('autoFocusOnExpand: true'));
    // No hand-off to a separate full-screen search.
    expect(nav, isNot(contains('GlobalSearchScreen')));
    expect(nav, isNot(contains('_openDedicatedSearch')));
  });

  test('recent searches provider persists queries', () {
    final recent = read(
      'lib/screens/search/providers/recent_search_provider.dart',
    );
    expect(recent, contains('recentSearchesProvider'));
    expect(recent, contains('SharedPreferencesService'));
    expect(recent, contains('clear()'));
  });
}
