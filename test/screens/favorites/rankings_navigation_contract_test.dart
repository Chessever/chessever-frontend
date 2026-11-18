import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Profile Rankings opens the Rankings tab', () {
    // The sidebar's rows moved to the Profile tab (2026-11-18).
    final profile = File(
      'lib/screens/my_profile/profile_hub_screen.dart',
    ).readAsStringSync();

    expect(profile, contains("title: 'Rankings'"));
    expect(profile, contains('Icons.leaderboard_outlined'));
    expect(profile, contains('initialMode: FavoritesScreenMode.players'));
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
