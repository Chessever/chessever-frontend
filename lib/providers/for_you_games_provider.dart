import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider for the "For You" games feed
///
/// Games must match one of these criteria to appear:
/// 1. Favorited players' games (highest priority)
/// 2. Favorited events' games
/// 3. Countryman games (ELO > 2300 only)
/// 4. High ELO games (fallback)
///
/// Within EACH category, live games (status = '*') are shown first,
/// then sorted by recency (last_move_time desc).
///
/// Auto-disposes when the user navigates away from the For You tab.
final forYouGamesProvider =
    StateNotifierProvider.autoDispose<ForYouGamesNotifier, AsyncValue<List<Games>>>(
  (ref) => ForYouGamesNotifier(ref),
);

/// Cached converted games to avoid repeated conversions
/// This converts Games to GamesTourModel once and caches the result
final convertedForYouGamesProvider = Provider.autoDispose<List<GamesTourModel>>((ref) {
  final gamesAsync = ref.watch(forYouGamesProvider);

  return gamesAsync.maybeWhen(
    data: (games) => games.map(_convertToGamesTourModel).toList(),
    orElse: () => [],
  );
});

/// Provides grouped games by tournament for display
final groupedForYouGamesProvider = Provider.autoDispose<List<ForYouGameGroup>>((ref) {
  final gamesAsync = ref.watch(forYouGamesProvider);

  return gamesAsync.maybeWhen(
    data: (games) => _groupGamesByTournament(games),
    orElse: () => [],
  );
});

/// Group games by tournament for better organization
List<ForYouGameGroup> _groupGamesByTournament(List<Games> games) {
  final Map<String, List<Games>> grouped = {};

  for (final game in games) {
    final tourId = game.tourId.isEmpty ? 'unknown' : game.tourId;
    grouped.putIfAbsent(tourId, () => []).add(game);
  }

  // Convert to list and sort groups by most recent game in each group
  final groups = grouped.entries.map((entry) {
    final sortedGames = entry.value..sort((a, b) {
      // Live games first within group
      final aIsLive = a.status == '*';
      final bIsLive = b.status == '*';
      if (aIsLive && !bIsLive) return -1;
      if (!aIsLive && bIsLive) return 1;
      // Then by last_move_time
      if (a.lastMoveTime == null && b.lastMoveTime == null) return 0;
      if (a.lastMoveTime == null) return 1;
      if (b.lastMoveTime == null) return -1;
      return b.lastMoveTime!.compareTo(a.lastMoveTime!);
    });

    return ForYouGameGroup(
      tourId: entry.key,
      tourName: sortedGames.first.name ?? 'Unknown Tournament',
      games: sortedGames,
      hasLiveGames: sortedGames.any((g) => g.status == '*'),
    );
  }).toList();

  // Sort groups: live games first, then by most recent game
  groups.sort((a, b) {
    if (a.hasLiveGames && !b.hasLiveGames) return -1;
    if (!a.hasLiveGames && b.hasLiveGames) return 1;
    final aLatest = a.games.first.lastMoveTime;
    final bLatest = b.games.first.lastMoveTime;
    if (aLatest == null && bLatest == null) return 0;
    if (aLatest == null) return 1;
    if (bLatest == null) return -1;
    return bLatest.compareTo(aLatest);
  });

  return groups;
}

/// Model for a group of games from the same tournament
class ForYouGameGroup {
  final String tourId;
  final String tourName;
  final List<Games> games;
  final bool hasLiveGames;

  const ForYouGameGroup({
    required this.tourId,
    required this.tourName,
    required this.games,
    required this.hasLiveGames,
  });
}

class ForYouGamesNotifier extends StateNotifier<AsyncValue<List<Games>>> {
  ForYouGamesNotifier(this.ref) : super(const AsyncValue.loading()) {
    _initialize();
  }

  final Ref ref;
  static const int _pageSize = 50;
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isFetchingMore = false;

  List<Games> _allGames = [];

  void _initialize() {
    // Watch for changes in favorites, country selection, or favorited events
    ref.listen(favoritePlayersProviderNew, (_, __) {
      refresh();
    });

    ref.listen(countryDropdownProvider, (_, __) {
      refresh();
    });

    ref.listen(favoriteEventsProvider, (_, __) {
      refresh();
    });

    // Initial load
    loadGames();
  }

  /// Load initial games or refresh
  Future<void> loadGames() async {
    try {
      state = const AsyncValue.loading();
      _currentPage = 0;
      _hasMore = true;
      _allGames = [];

      await _fetchAndMergeGames();

      state = AsyncValue.data(_allGames);
    } catch (e, st) {
      debugPrint('[ForYouGames] Error loading games: $e');
      debugPrint('[ForYouGames] Stack: $st');
      state = AsyncValue.error(e, st);
    }
  }

  /// Load more games for infinite scroll
  Future<void> loadMore() async {
    if (_isFetchingMore || !_hasMore) {
      debugPrint('[ForYouGames] Skip loadMore: fetching=$_isFetchingMore, hasMore=$_hasMore');
      return;
    }

    try {
      _isFetchingMore = true;
      _currentPage++;

      debugPrint('[ForYouGames] Loading page $_currentPage');

      await _fetchAndMergeGames();

      state = AsyncValue.data(_allGames);
    } catch (e, st) {
      debugPrint('[ForYouGames] Error loading more: $e');
      debugPrint('[ForYouGames] Stack: $st');
      // Don't update state on pagination errors, keep showing existing games
    } finally {
      _isFetchingMore = false;
    }
  }

  /// Fetch games from all sources and merge with priority sorting
  /// Priority: Favorited Players > Favorited Events > Countryman (ELO>2300) > High ELO
  /// Within each category, live games appear first, then by recency
  Future<void> _fetchAndMergeGames() async {
    final repository = ref.read(gameRepositoryProvider);

    // Get favorited players
    final favoritesAsync = ref.read(favoritePlayersProviderNew);
    final favorites = favoritesAsync.valueOrNull ?? [];

    // Get selected country
    final countryAsync = ref.read(countryDropdownProvider);
    final selectedCountry = countryAsync.valueOrNull;

    // Get favorited events
    final favoriteEventsAsync = ref.read(favoriteEventsProvider);
    final favoriteEvents = favoriteEventsAsync.valueOrNull ?? [];

    final offset = _currentPage * _pageSize;

    debugPrint('[ForYouGames] Fetching page $_currentPage (offset: $offset)');
    debugPrint('[ForYouGames] Favorites: ${favorites.length}, Country: ${selectedCountry?.countryCode}, Events: ${favoriteEvents.length}');

    List<Games> newGames = [];

    // Get FIDE IDs from favorites
    final fideIds = favorites
        .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
        .map((f) => f.fideId!)
        .toList();

    // Get event IDs from favorites
    final eventIds = favoriteEvents
        .map((e) => e.eventId)
        .where((id) => id.isNotEmpty)
        .toList();

    // === PRIORITY 1: Favorited players' games ===
    // (Live games within this category are prioritized in sorting)
    if (fideIds.isNotEmpty) {
      debugPrint('[ForYouGames] Fetching games for ${fideIds.length} favorited players');
      try {
        final favGames = await repository.getGamesByMultipleFideIds(
          fideIds: fideIds,
          limit: _pageSize,
          offset: offset,
        );
        newGames.addAll(favGames);
        debugPrint('[ForYouGames] Fetched ${favGames.length} games from favorited players');
      } catch (e) {
        debugPrint('[ForYouGames] Error fetching favorited games: $e');
      }
    }

    // === PRIORITY 2: Favorited events' games ===
    // (Live games within this category are prioritized in sorting)
    if (eventIds.isNotEmpty) {
      debugPrint('[ForYouGames] Fetching games for ${eventIds.length} favorited events');
      for (final eventId in eventIds) {
        try {
          final eventGames = await repository.getGamesByTourId(
            eventId,
            limit: _pageSize ~/ eventIds.length.clamp(1, 10),
          );
          newGames.addAll(eventGames);
          debugPrint('[ForYouGames] Fetched ${eventGames.length} games from event $eventId');
        } catch (e) {
          debugPrint('[ForYouGames] Error fetching games for event $eventId: $e');
        }
      }
    }

    // === PRIORITY 3: Countryman games (ELO > 2300 only) ===
    // (Live games within this category are prioritized in sorting)
    if (selectedCountry != null) {
      debugPrint('[ForYouGames] Fetching countryman games (ELO > 2300) for ${selectedCountry.countryCode}');
      try {
        final countryGames = await repository.getCountrymanGamesWithMinElo(
          countryCode: selectedCountry.countryCode,
          minElo: 2300, // Only show countryman games with ELO > 2300
          limit: _pageSize,
          offset: offset,
        );
        newGames.addAll(countryGames);
        debugPrint('[ForYouGames] Fetched ${countryGames.length} countryman games (ELO > 2300)');
      } catch (e) {
        debugPrint('[ForYouGames] Error fetching countryman games: $e');
      }
    }

    // === PRIORITY 4: High ELO games (fallback) ===
    // (Live games within this category are prioritized in sorting)
    try {
      final highEloGames = await repository.getHighEloGames(
        limit: _pageSize ~/ 2, // Smaller batch since this is lower priority
        offset: offset,
      );
      newGames.addAll(highEloGames);
      debugPrint('[ForYouGames] Fetched ${highEloGames.length} high ELO games');
    } catch (e) {
      debugPrint('[ForYouGames] Error fetching high ELO games: $e');
    }

    // Remove duplicates by game ID
    final gameIds = _allGames.map((g) => g.id).toSet();
    final uniqueNewGames = newGames.where((g) => !gameIds.contains(g.id)).toList();

    debugPrint('[ForYouGames] Adding ${uniqueNewGames.length} unique games (${newGames.length} total fetched)');

    // Add to all games
    _allGames.addAll(uniqueNewGames);

    // Apply smart sorting
    _sortGames(favorites, selectedCountry?.countryCode, favoriteEvents.map((e) => e.eventId).toSet());

    // Check if we have more
    _hasMore = uniqueNewGames.isNotEmpty;
    debugPrint('[ForYouGames] Has more: $_hasMore, Total games: ${_allGames.length}');
  }

  /// Sort games according to priority:
  /// 1. Favorited players' games (live first, then datetime desc)
  /// 2. Favorited events' games (live first, then datetime desc)
  /// 3. Countryman games (live first, then by highest ELO, then datetime)
  /// 4. Fallback high-ELO games (live first, then by ELO, then datetime)
  ///
  /// Within EACH category, live games always appear first.
  void _sortGames(List favorites, String? countryCode, Set<String> favoriteEventIds) {
    final Set<String> favoritedFideIds = favorites
        .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
        .map((f) => f.fideId as String)
        .toSet();

    final Set<String> favoritedNames = favorites
        .map((f) => f.playerName as String)
        .map((name) => name.toLowerCase())
        .toSet();

    _allGames.sort((a, b) {
      // Determine category for each game
      final aHasFavorite = _hasFavoritedPlayer(a, favoritedFideIds, favoritedNames);
      final bHasFavorite = _hasFavoritedPlayer(b, favoritedFideIds, favoritedNames);
      final aHasFavoriteEvent = favoriteEventIds.contains(a.tourId);
      final bHasFavoriteEvent = favoriteEventIds.contains(b.tourId);
      final aHasCountry = countryCode != null && _hasPlayerFromCountry(a, countryCode);
      final bHasCountry = countryCode != null && _hasPlayerFromCountry(b, countryCode);

      // Priority 1: Favorited players' games
      if (aHasFavorite && !bHasFavorite) return -1;
      if (!aHasFavorite && bHasFavorite) return 1;
      if (aHasFavorite && bHasFavorite) {
        // Within favorites: live first, then by datetime
        return _compareWithLivePriority(a, b);
      }

      // Priority 2: Favorited events' games
      if (aHasFavoriteEvent && !bHasFavoriteEvent) return -1;
      if (!aHasFavoriteEvent && bHasFavoriteEvent) return 1;
      if (aHasFavoriteEvent && bHasFavoriteEvent) {
        // Within favorite events: live first, then by datetime
        return _compareWithLivePriority(a, b);
      }

      // Priority 3: Countryman games (ELO > 2300 already filtered in fetch)
      if (aHasCountry && !bHasCountry) return -1;
      if (!aHasCountry && bHasCountry) return 1;
      if (aHasCountry && bHasCountry) {
        // Within countrymen: live first, then by ELO, then by datetime
        final aIsLive = _isLiveGame(a);
        final bIsLive = _isLiveGame(b);
        if (aIsLive && !bIsLive) return -1;
        if (!aIsLive && bIsLive) return 1;
        final eloCompare = _compareByMaxElo(a, b);
        if (eloCompare != 0) return eloCompare;
        return _compareByLastMoveTime(a, b);
      }

      // Priority 4: High ELO games (fallback)
      // Within high ELO: live first, then by ELO, then by datetime
      final aIsLive = _isLiveGame(a);
      final bIsLive = _isLiveGame(b);
      if (aIsLive && !bIsLive) return -1;
      if (!aIsLive && bIsLive) return 1;
      final eloCompare = _compareByMaxElo(a, b);
      if (eloCompare != 0) return eloCompare;
      return _compareByLastMoveTime(a, b);
    });
  }

  /// Compare two games with live games first, then by recency
  int _compareWithLivePriority(Games a, Games b) {
    final aIsLive = _isLiveGame(a);
    final bIsLive = _isLiveGame(b);
    if (aIsLive && !bIsLive) return -1;
    if (!aIsLive && bIsLive) return 1;
    return _compareByLastMoveTime(a, b);
  }

  bool _isLiveGame(Games game) {
    // A game is live if it has status "*" (ongoing) or recent activity
    return game.status == '*' || game.status == 'ongoing';
  }

  bool _hasFavoritedPlayer(
    Games game,
    Set<String> favoritedFideIds,
    Set<String> favoritedNames,
  ) {
    if (game.players == null) return false;

    for (final player in game.players!) {
      // Check FIDE ID
      if (player.fideId > 0 && favoritedFideIds.contains(player.fideId.toString())) {
        return true;
      }

      // Check name (case insensitive)
      if (favoritedNames.contains(player.name.toLowerCase())) {
        return true;
      }
    }

    return false;
  }

  bool _hasPlayerFromCountry(Games game, String countryCode) {
    if (game.players == null) return false;

    return game.players!.any((p) => p.fed.toUpperCase() == countryCode.toUpperCase());
  }

  int _compareByMaxElo(Games a, Games b) {
    final aMaxElo = _getMaxElo(a);
    final bMaxElo = _getMaxElo(b);

    // Higher ELO first
    return bMaxElo.compareTo(aMaxElo);
  }

  int _getMaxElo(Games game) {
    if (game.players == null || game.players!.isEmpty) return 0;

    return game.players!
        .map((p) => p.rating)
        .reduce((a, b) => a > b ? a : b);
  }

  int _compareByLastMoveTime(Games a, Games b) {
    // Most recent first
    if (a.lastMoveTime == null && b.lastMoveTime == null) return 0;
    if (a.lastMoveTime == null) return 1;
    if (b.lastMoveTime == null) return -1;

    return b.lastMoveTime!.compareTo(a.lastMoveTime!);
  }

  /// Refresh the feed
  Future<void> refresh() async {
    await loadGames();
  }

  bool get isFetchingMore => _isFetchingMore;
  bool get hasMore => _hasMore;
}

/// Convert Games model to GamesTourModel for display
/// This is extracted as a top-level function so it can be used by the cached provider
GamesTourModel _convertToGamesTourModel(Games game) {
  // Extract player data
  final players = game.players ?? [];
  final whitePlayer = players.isNotEmpty ? players[0] : null;
  final blackPlayer = players.length > 1 ? players[1] : null;

  // Determine game status
  GameStatus gameStatus = GameStatus.unknown;
  if (game.status == '*' || game.status == 'ongoing') {
    gameStatus = GameStatus.ongoing;
  } else if (game.status == '1-0') {
    gameStatus = GameStatus.whiteWins;
  } else if (game.status == '0-1') {
    gameStatus = GameStatus.blackWins;
  } else if (game.status == '½-½' || game.status == '1/2-1/2') {
    gameStatus = GameStatus.draw;
  }

  return GamesTourModel(
    gameId: game.id,
    whitePlayer: PlayerCard(
      name: whitePlayer?.name ?? 'Unknown',
      federation: whitePlayer?.fed ?? '',
      title: whitePlayer?.title ?? '',
      rating: whitePlayer?.rating ?? 0,
      countryCode: whitePlayer?.fed ?? '',
      fideId: whitePlayer?.fideId,
      team: whitePlayer?.team,
    ),
    blackPlayer: PlayerCard(
      name: blackPlayer?.name ?? 'Unknown',
      federation: blackPlayer?.fed ?? '',
      title: blackPlayer?.title ?? '',
      rating: blackPlayer?.rating ?? 0,
      countryCode: blackPlayer?.fed ?? '',
      fideId: blackPlayer?.fideId,
      team: blackPlayer?.team,
    ),
    whiteTimeDisplay: _formatTime(game.lastClockWhite),
    blackTimeDisplay: _formatTime(game.lastClockBlack),
    whiteClockCentiseconds: game.lastClockWhite ?? 0,
    blackClockCentiseconds: game.lastClockBlack ?? 0,
    whiteClockSeconds: game.lastClockWhite != null ? (game.lastClockWhite! / 100).round() : null,
    blackClockSeconds: game.lastClockBlack != null ? (game.lastClockBlack! / 100).round() : null,
    gameStatus: gameStatus,
    fen: game.fen,
    pgn: game.pgn,
    lastMove: game.lastMove,
    boardNr: game.boardNr,
    roundId: game.roundId,
    tourId: game.tourId,
    lastMoveTime: game.lastMoveTime,
  );
}

String _formatTime(int? centiseconds) {
  if (centiseconds == null) return '--:--';

  final totalSeconds = (centiseconds / 100).floor();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
