import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Provider for fetching all games for a specific player
final playerGamesProvider = FutureProvider.family<GamesScreenModel, String>((ref, playerName) async {
  final gameRepository = ref.read(gameRepositoryProvider);

  try {
    // Fetch all games for this player
    final games = await gameRepository.getGamesByPlayerName(playerName, limit: 100);

    // Convert to GamesTourModel format
    final gamesTourModels = games.map((game) => GamesTourModel.fromGame(game)).toList();

    return GamesScreenModel(
      gamesTourModels: gamesTourModels,
      pinnedGamedIs: [], // No pinning functionality for player games
      isSearchMode: false,
    );
  } catch (e) {
    throw Exception('Failed to load player games: $e');
  }
});

