import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../view_models/player_view_model.dart';

// Provider for the PlayerViewModel
final playerViewModelProvider = Provider<PlayerViewModel>((ref) {
  return PlayerViewModel();
});

// Provider for player state
final playerProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final viewModel = ref.read(playerViewModelProvider);
  await viewModel.initialize();
  return viewModel.getPlayers();
});

// Provider for search query
final playerSearchQueryProvider = StateProvider<String>((ref) => '');

// Provider for filtered players based on search
final filteredPlayersProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final searchQuery = ref.watch(playerSearchQueryProvider);
  final viewModel = ref.read(playerViewModelProvider);
  return viewModel.searchPlayers(searchQuery);
});

// Provider for favorite players
final favoritePlayersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final viewModel = ref.read(playerViewModelProvider);
  await viewModel.initialize();
  return viewModel.getFavoritePlayers();
});

// Provider for filtered favorite players based on search
final filteredFavoritePlayersProvider = Provider<List<Map<String, dynamic>>>((
  ref,
) {
  final searchQuery = ref.watch(playerSearchQueryProvider);
  final favoritePlayers = ref.watch(favoritePlayersProvider).valueOrNull ?? [];

  if (searchQuery.isEmpty) {
    return favoritePlayers;
  }

  final lowercaseQuery = searchQuery.toLowerCase();
  return favoritePlayers
      .where(
        (player) =>
            player['name'].toString().toLowerCase().contains(lowercaseQuery),
      )
      .toList();
});
