// filepath: /Users/p1/Desktop/chessever/lib/screens/favorites/providers/favorite_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../controllers/favorite_controller.dart';

part 'favorite_provider.g.dart';

@riverpod
class FavoriteNotifier extends _$FavoriteNotifier {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    // Initial data load
    final controller = ref.read(favoriteControllerProvider);
    await controller.fetchFavoritePlayers();

    return controller.getFavoritePlayers();
  }

  // Get filtered starred_repository players based on search query
  List<Map<String, dynamic>> getFilteredFavoritePlayers(String query) {
    final controller = ref.read(favoriteControllerProvider);
    return controller.searchFavoritePlayers(query);
  }

  // Remove player from favorites
  Future<void> removeFromFavorites(String playerName) async {
    final controller = ref.read(favoriteControllerProvider);
    await controller.removeFromFavorites(playerName);
    ref.invalidateSelf(); // Refresh the provider after removing from favorites
  }
}

@riverpod
FavoriteController favoriteController(FavoriteControllerRef ref) {
  return FavoriteController();
}
