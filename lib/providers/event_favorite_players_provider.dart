import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Model representing favorite player information for an event
class EventFavoritePlayers {
  final int count;
  final List<int> fideIds;

  const EventFavoritePlayers({required this.count, required this.fideIds});

  const EventFavoritePlayers.empty() : count = 0, fideIds = const [];

  bool get hasFavorites => count > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventFavoritePlayers &&
          runtimeType == other.runtimeType &&
          count == other.count;

  @override
  int get hashCode => count.hashCode;
}

/// Provider that checks if an event contains favorite players
/// This is a family provider that takes an event ID
/// This provider is REACTIVE - it automatically updates when favorite players change
final eventFavoritePlayersProvider = FutureProvider.autoDispose.family<
  EventFavoritePlayers,
  String
>((ref, eventId) async {
  try {
    // Read the favorite players (not watch) to avoid infinite rebuild loops
    // Reactivity is handled by the parent provider (forYouEventsProvider)
    final favoritePlayersState = await ref.read(
      favoritePlayersNotifierProvider.future,
    );
    final favoritePlayers = favoritePlayersState.players;

    // If no favorites, return empty
    if (favoritePlayers.isEmpty) {
      return const EventFavoritePlayers.empty();
    }

    // Get favorite player FIDE IDs (filter out nulls)
    final favoriteFideIds =
        favoritePlayers
            .where((p) => p.fideId != null)
            .map((p) => p.fideId!)
            .toSet();

    if (favoriteFideIds.isEmpty) {
      return const EventFavoritePlayers.empty();
    }

    // Get tours for this event
    final tourLocalStorage = ref.read(tourLocalStorageProvider);
    final tours = await tourLocalStorage.getTours(eventId);

    if (tours.isEmpty) {
      return const EventFavoritePlayers.empty();
    }

    // Collect all unique players from all tours in this event
    final eventPlayerFideIds = <int>{};
    for (final tour in tours) {
      for (final player in tour.players) {
        if (player.fideId != null && player.fideId! > 0) {
          eventPlayerFideIds.add(player.fideId!);
        }
      }
    }

    // Fallback: if tours have no players (stale or missing), derive from games
    if (eventPlayerFideIds.isEmpty) {
      final groupBroadcastRepo = ref.read(groupBroadcastRepositoryProvider);
      final gameRepo = ref.read(gameRepositoryProvider);

      List<String> tourIds;
      try {
        tourIds = await groupBroadcastRepo.getTourIdsForGroupBroadcast(eventId);
      } catch (_) {
        tourIds = <String>[];
      }

      if (tourIds.isEmpty) {
        tourIds = [eventId];
      }

      final games = await gameRepo.getGamesFromTourIds(
        tourIds: tourIds,
        limit: 200,
        offset: 0,
      );

      for (final game in games) {
        final players = game.players;
        if (players == null || players.isEmpty) continue;
        for (final player in players) {
          if (player.fideId > 0) {
            eventPlayerFideIds.add(player.fideId);
          }
        }
      }
    }

    // Find matching favorite players
    final matchingFideIds =
        eventPlayerFideIds.intersection(favoriteFideIds).toList();

    return EventFavoritePlayers(
      count: matchingFideIds.length,
      fideIds: matchingFideIds,
    );
  } catch (e) {
    // On error, return empty (fail gracefully)
    return const EventFavoritePlayers.empty();
  }
});

/// Cached provider that maintains event favorite player counts
/// This helps avoid repeated expensive lookups
class EventFavoritePlayersCache
    extends StateNotifier<Map<String, EventFavoritePlayers>> {
  EventFavoritePlayersCache() : super({});

  void updateCache(String eventId, EventFavoritePlayers data) {
    state = {...state, eventId: data};
  }

  /// Batch update cache with multiple entries at once (single state notification)
  void updateCacheBatch(Map<String, EventFavoritePlayers> data) {
    state = {...state, ...data};
  }

  EventFavoritePlayers? getCached(String eventId) {
    return state[eventId];
  }

  void clear() {
    state = {};
  }
}

final eventFavoritePlayersCacheProvider = StateNotifierProvider<
  EventFavoritePlayersCache,
  Map<String, EventFavoritePlayers>
>((ref) => EventFavoritePlayersCache());
