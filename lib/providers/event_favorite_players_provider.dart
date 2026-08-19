import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/utils/favorite_player_identity.dart';
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

/// Counts event players that match the user's favourites.
///
/// FIDE ids are authoritative. When a board/roster row has no id — common
/// for live Russian/FID players — the same name+neutral-federation rules as
/// auto-pin apply so the event still shows that a favourite is playing.
EventFavoritePlayers matchingEventFavoritePlayers({
  required Iterable<({String name, int? fideId, String federation})>
  eventPlayers,
  required Iterable<FavoritePlayer> favorites,
}) {
  final favoriteList = favorites.toList(growable: false);
  if (favoriteList.isEmpty) return const EventFavoritePlayers.empty();

  final matchingFideIds = <int>{};
  final matchingNameless = <String>{};

  for (final player in eventPlayers) {
    final matches = favoriteList.any(
      (favorite) => favoriteMatchesPlayer(
        favorite: favorite,
        playerName: player.name,
        playerFideId: player.fideId,
        playerCountry: player.federation,
      ),
    );
    if (!matches) continue;
    final fideId = player.fideId;
    if (fideId != null && fideId > 0) {
      matchingFideIds.add(fideId);
    } else if (player.name.trim().isNotEmpty) {
      matchingNameless.add(player.name.trim().toLowerCase());
    }
  }

  return EventFavoritePlayers(
    count: matchingFideIds.length + matchingNameless.length,
    fideIds: matchingFideIds.toList(),
  );
}

/// Provider that checks if an event contains favorite players
/// This is a family provider that takes an event ID
/// This provider is REACTIVE - it automatically updates when favorite players change
final eventFavoritePlayersProvider = FutureProvider.autoDispose.family<
  EventFavoritePlayers,
  String
>((ref, eventId) async {
  try {
    // Read from the new provider (in-memory, no Supabase call).
    // Data is already synced by the auth flow — avoids a redundant round-trip.
    final favoritePlayers =
        ref.read(favoritePlayersProviderNew).valueOrNull ?? [];

    // If no favorites, return empty
    if (favoritePlayers.isEmpty) {
      return const EventFavoritePlayers.empty();
    }

    // Get tours for this event
    final tourLocalStorage = ref.read(tourLocalStorageProvider);
    final tours = await tourLocalStorage.getTours(eventId);

    if (tours.isEmpty) {
      return const EventFavoritePlayers.empty();
    }

    final eventPlayers = <({String name, int? fideId, String federation})>[];
    for (final tour in tours) {
      for (final player in tour.players) {
        eventPlayers.add((
          name: player.name,
          fideId: player.fideId,
          federation: player.federation ?? '',
        ));
      }
    }

    // Fallback: if tours have no players (stale or missing), derive from games
    if (eventPlayers.isEmpty) {
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
          eventPlayers.add((
            name: player.name,
            fideId: player.fideId > 0 ? player.fideId : null,
            federation: player.fed,
          ));
        }
      }
    }

    return matchingEventFavoritePlayers(
      eventPlayers: eventPlayers,
      favorites: favoritePlayers,
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
