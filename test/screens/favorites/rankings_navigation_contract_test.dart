import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drawer Rankings opens the Rankings tab', () {
    final drawer =
        File(
          'lib/widgets/hamburger_menu/hamburger_menu.dart',
        ).readAsStringSync();
    final home = File('lib/screens/home/home_screen.dart').readAsStringSync();

    expect(drawer, contains("title: 'Rankings'"));
    expect(drawer, contains('icon: Icons.leaderboard_outlined'));
    expect(home, contains('initialMode: FavoritesScreenMode.players'));
  });

  test('For You Favorites keeps its existing Games entry path', () {
    final modeProvider =
        File(
          'lib/screens/favorites/provider/favorites_mode_provider.dart',
        ).readAsStringSync();
    final forYouCard =
        File(
          'lib/screens/group_event/widget/premium_collection_cards.dart',
        ).readAsStringSync();

    expect(modeProvider, contains('(ref) => FavoritesScreenMode.games'));
    expect(forYouCard, contains('builder: (_) => const FavoritesTabScreen()'));
    expect(
      forYouCard,
      isNot(contains('initialMode: FavoritesScreenMode.players')),
    );
  });
}
