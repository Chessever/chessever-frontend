import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural gate: success-path outer chrome must use package glass islands
/// and correct composition (GlassPage / useOwnLayer), not Material IconButton
/// slabs or plain Scaffold hosts for glass controls.
void main() {
  final root = Directory.current.path;

  String read(String relative) => File('$root/$relative').readAsStringSync();

  void expectNoMaterialIconButton(String source) {
    expect(RegExp(r'(^|[^A-Za-z])IconButton\(').hasMatch(source), isFalse);
  }

  test(
    'tournament success-path app bars use GlassBackButton, not IconButton',
    () {
      final gamesAppBar = read(
        'lib/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart',
      );
      final tourDetail = read(
        'lib/screens/tour_detail/tournament_detail_screen.dart',
      );

      expect(gamesAppBar, contains('GlassBackButton'));
      expectNoMaterialIconButton(gamesAppBar);

      // Success-path dropdown app bar + loading bar.
      expect(tourDetail, contains('const GlassBackButton()'));
      expect(tourDetail, contains('GlassBackButton('));
      // No Material IconButton remaining in this file's chrome rows.
      expectNoMaterialIconButton(tourDetail);
    },
  );

  test('favorites + countrymen use full-screen overlay composition', () {
    final favorites = read('lib/screens/favorites/favorites_tab_screen.dart');
    final countrymen = read(
      'lib/screens/countrymen/countrymen_tab_screen.dart',
    );

    for (final source in [favorites, countrymen]) {
      expect(source, contains('GlassFullScreenPage('));
      expect(source, contains('topOverlay:'));
      expect(source, contains('content:'));
      expect(source, contains('PageView.builder('));
      expect(source, contains('includeContentSafeArea: false'));
      expect(source, contains('.clamp(48.0, 72.0)'));
      expect(source, contains('top: contentTopInset'));
      expect(source, contains('ResponsiveHelper.contentMaxWidth'));
      expect(source, contains('backgroundColor: context.colors.background'));
      expect(source, contains('GlassMotion.reduceMotion(context)'));
      expect(source, contains('Semantics('));
      expect(source, contains('GlassBackButton'));
      expect(source, isNot(contains('ScreenWrapper(')));
      expect(
        source,
        isNot(contains('child: Column(\n              children:')),
      );
      expectNoMaterialIconButton(source);
    }

    expect(favorites, contains('E2eIds.favoritesRoot'));
    expect(favorites, contains("'favorites-floating-controls'"));
    expect(favorites, contains("'favorites-segments'"));
    expect(favorites, contains("'favorites-page-view'"));
    expect(countrymen, contains('E2eIds.countrymenRoot'));
    expect(countrymen, contains("'countrymen-floating-controls'"));
    expect(countrymen, contains("'countrymen-segments'"));
    expect(countrymen, contains("'countrymen-page-view'"));
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

  test('full-screen page keeps opaque content behind overlay islands', () {
    final page = read('lib/widgets/liquid_glass/glass_full_screen_page.dart');
    final search = read('lib/screens/search/global_search_screen.dart');

    expect(page, contains('Positioned.fill('));
    expect(page, contains('topOverlay'));
    expect(page, contains('bottomOverlay'));
    expect(search, contains('GlassFullScreenPage('));
    expect(search, isNot(contains('body: Column(')));
  });

  test('home phone shell uses GlassScaffold + GlassTabBar.searchable', () {
    final home = read('lib/screens/home/home_screen.dart');
    final nav = read('lib/screens/home/widget/bottom_nav_bar.dart');
    expect(home, contains('GlassScaffold('));
    expect(home, contains('extendBody: true'));
    expect(home, contains('HomeDestinationStack('));
    expect(nav, contains('GlassTabBar.searchable('));
  });

  test('shared AppBarWithTitle uses GlassBackButton island', () {
    final appBar = read('lib/widgets/app_bar_with_title.dart');
    expect(appBar, contains('GlassBackButton'));
    expectNoMaterialIconButton(appBar);
  });
}
