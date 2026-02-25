import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tab mode for Favorites screen
enum FavoritesScreenMode {
  favorites, // List of favorite players
  games, // Games from favorites with date tabs
  players, // World players search
}

final selectedFavoritesModeProvider =
    AutoDisposeStateProvider<FavoritesScreenMode>(
      (ref) => FavoritesScreenMode.games,
    );

const favoritesModeNames = {
  FavoritesScreenMode.favorites: 'Favorites',
  FavoritesScreenMode.games: 'Games',
  FavoritesScreenMode.players: 'Players',
};
