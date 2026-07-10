import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural gate: success-path outer chrome must use package glass islands
/// and correct composition (GlassPage / useOwnLayer), not Material IconButton
/// slabs or plain Scaffold hosts for glass controls.
void main() {
  final root = Directory.current.path;

  String read(String relative) =>
      File('$root/$relative').readAsStringSync();

  test('tournament success-path app bars use GlassBackButton, not IconButton', () {
    final gamesAppBar = read(
      'lib/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart',
    );
    final tourDetail = read(
      'lib/screens/tour_detail/tournament_detail_screen.dart',
    );

    expect(gamesAppBar, contains('GlassBackButton'));
    expect(gamesAppBar, isNot(contains('IconButton(')));

    // Success-path dropdown app bar + loading bar.
    expect(tourDetail, contains('const GlassBackButton()'));
    expect(tourDetail, contains('GlassBackButton('));
    // No Material IconButton remaining in this file's chrome rows.
    expect(tourDetail, isNot(contains('IconButton(')));
  });

  test('favorites + countrymen use GlassPage composition via ScreenWrapper', () {
    final favorites = read('lib/screens/favorites/favorites_tab_screen.dart');
    final countrymen = read(
      'lib/screens/countrymen/countrymen_tab_screen.dart',
    );

    expect(favorites, contains('ScreenWrapper('));
    expect(favorites, contains('GlassBackButton'));
    expect(favorites, isNot(contains('IconButton(')));

    expect(countrymen, contains('ScreenWrapper('));
    expect(countrymen, contains('GlassBackButton'));
    expect(countrymen, isNot(contains('IconButton(')));
  });

  test('GlassBackButton always sets useOwnLayer: true (package contract)', () {
    final back = read('lib/widgets/liquid_glass/glass_back_button.dart');
    expect(back, contains('useOwnLayer: true'));
    expect(back, contains('GlassIconButton('));
  });

  test('ScreenWrapper wraps with GlassPage background isolation', () {
    final wrapper = read('lib/widgets/screen_wrapper.dart');
    expect(wrapper, contains('GlassPage('));
    expect(wrapper, contains('background:'));
  });

  test('home phone shell uses GlassScaffold + GlassTabBar.searchable', () {
    final home = read('lib/screens/home/home_screen.dart');
    final nav = read('lib/screens/home/widget/bottom_nav_bar.dart');
    expect(home, contains('GlassScaffold('));
    expect(home, contains('extendBody: true'));
    expect(nav, contains('GlassTabBar.searchable('));
  });

  test('shared AppBarWithTitle uses GlassBackButton island', () {
    final appBar = read('lib/widgets/app_bar_with_title.dart');
    expect(appBar, contains('GlassBackButton'));
    expect(appBar, isNot(contains('IconButton(')));
  });
}
