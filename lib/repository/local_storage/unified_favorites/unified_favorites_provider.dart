import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'unified_favorites_service.dart';

// Provider for favorite events
final favoriteEventsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.read(unifiedFavoritesService);
  return await service.getFavoriteEvents();
});

// Provider for favorite players
final favoritePlayersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.read(unifiedFavoritesService);
  return await service.getFavoritePlayers();
});

// Provider for favorite tournament players (using existing model)
final favoriteTournamentPlayersProvider = FutureProvider<List<PlayerStandingModel>>((ref) async {
  final service = ref.read(unifiedFavoritesService);
  return await service.getFavoriteTournamentPlayers();
});

// Provider to check if an event is favorite
final isEventFavoriteProvider = FutureProvider.family<bool, String>((ref, eventId) async {
  final service = ref.read(unifiedFavoritesService);
  return await service.isEventFavorite(eventId);
});

// Provider to check if a player is favorite
final isPlayerFavoriteProvider = FutureProvider.family<bool, String>((ref, fideId) async {
  final service = ref.read(unifiedFavoritesService);
  return await service.isPlayerFavorite(fideId);
});

// Provider to check if a tournament player is favorite
final isTournamentPlayerFavoriteProvider = FutureProvider.family<bool, String>((ref, playerName) async {
  final service = ref.read(unifiedFavoritesService);
  return await service.isTournamentPlayerFavorite(playerName);
});

// Search query provider for favorites
final favoritesSearchQueryProvider = StateProvider<String>((ref) => '');

// Selected tab provider for favorites screen
enum FavoriteTab { events, players, tournamentPlayers }

final selectedFavoriteTabProvider = StateProvider<FavoriteTab>((ref) => FavoriteTab.events);

// Filtered favorite events provider
final filteredFavoriteEventsProvider = Provider<AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final searchQuery = ref.watch(favoritesSearchQueryProvider);
  final favoriteEventsAsync = ref.watch(favoriteEventsProvider);

  return favoriteEventsAsync.when(
    data: (events) {
      if (searchQuery.isEmpty) {
        return AsyncValue.data(events);
      }

      final filtered = events.where((event) {
        final query = searchQuery.toLowerCase();
        final title = (event['title'] as String? ?? '').toLowerCase();
        final timeControl = (event['timeControl'] as String? ?? '').toLowerCase();
        return title.contains(query) || timeControl.contains(query);
      }).toList();

      return AsyncValue.data(filtered);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
  );
});

// Filtered favorite players provider
final filteredFavoritePlayersProvider = Provider<AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final searchQuery = ref.watch(favoritesSearchQueryProvider);
  final favoritePlayersAsync = ref.watch(favoritePlayersProvider);

  return favoritePlayersAsync.when(
    data: (players) {
      if (searchQuery.isEmpty) {
        return AsyncValue.data(players);
      }

      final filtered = players.where((player) {
        final query = searchQuery.toLowerCase();
        final name = (player['name'] as String? ?? '').toLowerCase();
        final title = (player['title'] as String? ?? '').toLowerCase();
        return name.contains(query) || title.contains(query);
      }).toList();

      return AsyncValue.data(filtered);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
  );
});

// Filtered favorite tournament players provider
final filteredFavoriteTournamentPlayersProvider = Provider<AsyncValue<List<PlayerStandingModel>>>((ref) {
  final searchQuery = ref.watch(favoritesSearchQueryProvider);
  final favoriteTournamentPlayersAsync = ref.watch(favoriteTournamentPlayersProvider);

  return favoriteTournamentPlayersAsync.when(
    data: (players) {
      if (searchQuery.isEmpty) {
        return AsyncValue.data(players);
      }

      final filtered = players.where((player) {
        final query = searchQuery.toLowerCase();
        return player.name.toLowerCase().contains(query) ||
            (player.title?.toLowerCase().contains(query) ?? false);
      }).toList();

      return AsyncValue.data(filtered);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
  );
});

// Helper extension for easy access
extension UnifiedFavoritesRef on WidgetRef {
  Future<void> toggleEventFavorite(GroupEventCardModel event) async {
    final service = read(unifiedFavoritesService);
    await service.toggleEventFavorite(event);
    invalidate(favoriteEventsProvider);
    invalidate(isEventFavoriteProvider(event.id));
  }

  Future<void> togglePlayerFavorite({
    required String fideId,
    required String playerName,
    required String? countryCode,
    required int? rating,
    required String? title,
  }) async {
    final service = read(unifiedFavoritesService);
    await service.togglePlayerFavorite(
      fideId: fideId,
      playerName: playerName,
      countryCode: countryCode,
      rating: rating,
      title: title,
    );
    invalidate(favoritePlayersProvider);
    invalidate(isPlayerFavoriteProvider(fideId));
  }

  Future<void> toggleTournamentPlayerFavorite(PlayerStandingModel player) async {
    final service = read(unifiedFavoritesService);
    await service.toggleTournamentPlayerFavorite(player);
    invalidate(favoriteTournamentPlayersProvider);
    invalidate(isTournamentPlayerFavoriteProvider(player.name));
  }

  Future<void> removeFavoriteEvent(String eventId) async {
    final service = read(unifiedFavoritesService);
    await service.removeFavoriteEvent(eventId);
    invalidate(favoriteEventsProvider);
    invalidate(isEventFavoriteProvider(eventId));
  }

  Future<void> removeFavoritePlayer(String fideId) async {
    final service = read(unifiedFavoritesService);
    await service.removeFavoritePlayer(fideId);
    invalidate(favoritePlayersProvider);
    invalidate(isPlayerFavoriteProvider(fideId));
  }

  Future<void> removeFavoriteTournamentPlayer(String playerName) async {
    final service = read(unifiedFavoritesService);
    await service.removeFavoriteTournamentPlayer(playerName);
    invalidate(favoriteTournamentPlayersProvider);
    invalidate(isTournamentPlayerFavoriteProvider(playerName));
  }
}