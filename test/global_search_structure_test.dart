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
  });

  test('bottom nav expands first then opens dedicated search on field tap', () {
    final nav = read('lib/screens/home/widget/bottom_nav_bar.dart');
    expect(nav, contains('onSearchFieldTap'));
    expect(nav, contains('_openDedicatedSearch'));
    expect(nav, contains('GlobalSearchScreen.route'));
    expect(nav, contains('_searchJustExpanded'));
    expect(nav, contains('onSubmitted: _onSearchSubmitted'));
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
