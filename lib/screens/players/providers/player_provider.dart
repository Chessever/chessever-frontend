import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../controllers/player_controller.dart';

part 'player_provider.g.dart';

@riverpod
class PlayerNotifier extends _$PlayerNotifier {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    // Initial data load
    final controller = ref.read(playerControllerProvider);
    await controller.fetchPlayers();

    return controller.getPlayers();
  }

  // Get filtered players based on search query
  List<Map<String, dynamic>> getFilteredPlayers(String query) {
    final controller = ref.read(playerControllerProvider);
    return controller.searchPlayers(query);
  }

  // Toggle starred_repository status for a player
  Future<void> toggleFavorite(String playerName) async {
    final controller = ref.read(playerControllerProvider);
    await controller.toggleFavorite(playerName);
    ref.invalidateSelf(); // Refresh the provider after toggling starred_repository
  }
}

@riverpod
PlayerController playerController(PlayerControllerRef ref) {
  return PlayerController();
}
