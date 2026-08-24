import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final favoritesSource =
      File(
        'lib/screens/favorites/tabs/favorites_list_tab.dart',
      ).readAsStringSync();
  final gamesSource =
      File(
        'lib/screens/favorites/tabs/favorites_games_tab.dart',
      ).readAsStringSync();

  test('Favorites empty search is wired to global player suggestions', () {
    expect(favoritesSource, contains('FavoritePlayerSearchSuggestion('));
    expect(
      favoritesSource,
      contains('surface: FavoritePlayerSearchSurface.favorites'),
    );
    expect(favoritesSource, contains('onAdd: _addFavoritePlayer'));
  });

  test('Games empty search is wired to the same player-add flow', () {
    expect(gamesSource, contains('FavoritePlayerSearchSuggestion('));
    expect(gamesSource, contains('surface: FavoritePlayerSearchSurface.games'));
    expect(gamesSource, contains('onAdd: _addFavoritePlayer'));
  });

  test(
    'both add handlers preserve authentication and favorite-limit guards',
    () {
      for (final source in [favoritesSource, gamesSource]) {
        expect(source, contains('requireFullAuthGuard(context)'));
        expect(source, contains('canAddMoreFavorites(context, ref)'));
        expect(source, contains('favoritePlayersProviderNew.notifier'));
        expect(source, contains('FavoriteLimitExceededException'));
      }
    },
  );
}
