import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ============================================================================
// ENUMS & MODELS
// ============================================================================

/// Type of premium games collection to display.
enum PremiumGamesType {
  /// Games featuring the user's favorite players.
  favorites,

  /// Games featuring players from the user's country.
  countrymen,
}

/// Date range filter for premium games.
enum PremiumGamesDateRange { last7Days, last30Days, last90Days, allTime }

extension PremiumGamesDateRangeExtension on PremiumGamesDateRange {
  String get displayText {
    switch (this) {
      case PremiumGamesDateRange.last7Days:
        return 'Last 7 days';
      case PremiumGamesDateRange.last30Days:
        return 'Last 30 days';
      case PremiumGamesDateRange.last90Days:
        return 'Last 90 days';
      case PremiumGamesDateRange.allTime:
        return 'All time';
    }
  }

  DateTime? get startDate {
    final now = DateTime.now();
    switch (this) {
      case PremiumGamesDateRange.last7Days:
        return now.subtract(const Duration(days: 7));
      case PremiumGamesDateRange.last30Days:
        return now.subtract(const Duration(days: 30));
      case PremiumGamesDateRange.last90Days:
        return now.subtract(const Duration(days: 90));
      case PremiumGamesDateRange.allTime:
        return null;
    }
  }
}

/// Result filter for premium games.
enum PremiumGamesResult { all, whiteWins, blackWins, draw }

extension PremiumGamesResultExtension on PremiumGamesResult {
  String get displayText {
    switch (this) {
      case PremiumGamesResult.all:
        return 'All';
      case PremiumGamesResult.whiteWins:
        return 'White wins';
      case PremiumGamesResult.blackWins:
        return 'Black wins';
      case PremiumGamesResult.draw:
        return 'Draws';
    }
  }

  bool matches(GameStatus status) {
    switch (this) {
      case PremiumGamesResult.all:
        return true;
      case PremiumGamesResult.whiteWins:
        return status == GameStatus.whiteWins;
      case PremiumGamesResult.blackWins:
        return status == GameStatus.blackWins;
      case PremiumGamesResult.draw:
        return status == GameStatus.draw;
    }
  }
}

/// Filter settings for premium games.
class PremiumGamesFilter {
  const PremiumGamesFilter({
    this.dateRange = PremiumGamesDateRange.allTime,
    this.result = PremiumGamesResult.all,
    this.timeControl = GameTimeControlFilter.all,
    this.eco = GameEcoFilter.all,
    this.finish = GameFinishFilter.all,
    this.minElo,
    this.maxElo,
  });

  final PremiumGamesDateRange dateRange;
  final PremiumGamesResult result;
  final GameTimeControlFilter timeControl;
  final GameEcoFilter eco;
  final GameFinishFilter finish;
  final int? minElo;
  final int? maxElo;

  bool get hasActiveFilters {
    return dateRange != PremiumGamesDateRange.allTime ||
        result != PremiumGamesResult.all ||
        timeControl != GameTimeControlFilter.all ||
        !eco.isAll ||
        finish != GameFinishFilter.all ||
        minElo != null ||
        maxElo != null;
  }

  PremiumGamesFilter copyWith({
    PremiumGamesDateRange? dateRange,
    PremiumGamesResult? result,
    GameTimeControlFilter? timeControl,
    GameEcoFilter? eco,
    GameFinishFilter? finish,
    int? minElo,
    int? maxElo,
    bool clearElo = false,
  }) {
    return PremiumGamesFilter(
      dateRange: dateRange ?? this.dateRange,
      result: result ?? this.result,
      timeControl: timeControl ?? this.timeControl,
      eco: eco ?? this.eco,
      finish: finish ?? this.finish,
      minElo: clearElo ? null : (minElo ?? this.minElo),
      maxElo: clearElo ? null : (maxElo ?? this.maxElo),
    );
  }

  static const PremiumGamesFilter defaultFilter = PremiumGamesFilter();
}

/// State for premium games screen.
class PremiumGamesState {
  const PremiumGamesState({
    required this.games,
    required this.filter,
    required this.isLoadingMore,
    required this.hasMore,
  });

  final List<GamesTourModel> games;
  final PremiumGamesFilter filter;
  final bool isLoadingMore;
  final bool hasMore;

  static const initial = PremiumGamesState(
    games: [],
    filter: PremiumGamesFilter.defaultFilter,
    isLoadingMore: false,
    hasMore: true,
  );

  PremiumGamesState copyWith({
    List<GamesTourModel>? games,
    PremiumGamesFilter? filter,
    bool? isLoadingMore,
    bool? hasMore,
  }) {
    return PremiumGamesState(
      games: games ?? this.games,
      filter: filter ?? this.filter,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

/// Provider for premium games filter state (persists across rebuilds).
final premiumGamesFilterProvider =
    StateProvider.family<PremiumGamesFilter, PremiumGamesType>(
      (ref, type) => PremiumGamesFilter.defaultFilter,
    );

/// Provider for premium games based on type.
final premiumGamesProvider = StateNotifierProvider.autoDispose
    .family<
      PremiumGamesNotifier,
      AsyncValue<PremiumGamesState>,
      PremiumGamesType
    >((ref, type) {
      ref.keepAlive();
      return PremiumGamesNotifier(ref, type);
    });

/// Notifier for managing premium games state.
class PremiumGamesNotifier
    extends StateNotifier<AsyncValue<PremiumGamesState>> {
  PremiumGamesNotifier(this._ref, this._type)
    : super(const AsyncValue.loading()) {
    _initialize();
  }

  final Ref _ref;
  final PremiumGamesType _type;

  final List<GamesTourModel> _allGames = [];
  bool _hasMore = true;
  bool _isFetching = false;
  int _offset = 0;
  static const int _pageSize = 30;

  Future<void> _initialize() async {
    await loadGames();
  }

  /// Load initial games with current filter.
  Future<void> loadGames({bool showLoading = true}) async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      if (showLoading) {
        state = const AsyncValue.loading();
      }

      _allGames.clear();
      _offset = 0;
      _hasMore = true;

      await _fetchGames();

      final filter = _ref.read(premiumGamesFilterProvider(_type));
      state = AsyncValue.data(
        PremiumGamesState(
          games: _getFilteredGames(),
          filter: filter,
          isLoadingMore: false,
          hasMore: _hasMore,
        ),
      );
    } catch (e, stack) {
      debugPrint('[PremiumGames] Error loading games: $e');
      state = AsyncValue.error(e, stack);
    } finally {
      _isFetching = false;
    }
  }

  /// Load more games for pagination.
  Future<void> loadMore() async {
    if (_isFetching || !_hasMore) return;

    final currentState = state.valueOrNull;
    if (currentState == null) return;

    _isFetching = true;
    state = AsyncValue.data(currentState.copyWith(isLoadingMore: true));

    try {
      await _fetchGames();

      final filter = _ref.read(premiumGamesFilterProvider(_type));
      state = AsyncValue.data(
        PremiumGamesState(
          games: _getFilteredGames(),
          filter: filter,
          isLoadingMore: false,
          hasMore: _hasMore,
        ),
      );
    } catch (e) {
      debugPrint('[PremiumGames] Error loading more: $e');
      state = AsyncValue.data(currentState.copyWith(isLoadingMore: false));
    } finally {
      _isFetching = false;
    }
  }

  /// Fetch games from repository based on type.
  Future<void> _fetchGames() async {
    final repository = _ref.read(gameRepositoryProvider);
    List<GamesTourModel> newGames = [];

    switch (_type) {
      case PremiumGamesType.favorites:
        newGames = await _fetchFavoriteGames(repository);
        break;
      case PremiumGamesType.countrymen:
        newGames = await _fetchCountrymenGames(repository);
        break;
    }

    if (newGames.isEmpty) {
      _hasMore = false;
    } else {
      _allGames.addAll(newGames);
      _offset += newGames.length;

      // Sort all games by datetime DESC, then avgElo DESC
      _sortGames();
    }

    debugPrint(
      '[PremiumGames] Fetched ${newGames.length} games, total: ${_allGames.length}',
    );
  }

  /// Fetch games for favorite players.
  Future<List<GamesTourModel>> _fetchFavoriteGames(
    GameRepository repository,
  ) async {
    final favoritesAsync = _ref.read(favoritePlayersProviderNew);
    final favorites = favoritesAsync.valueOrNull ?? [];

    if (favorites.isEmpty) {
      debugPrint('[PremiumGames] No favorite players');
      return [];
    }

    // Get FIDE IDs from favorites
    final fideIds = favorites
        .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
        .map((f) => f.fideId!)
        .toList();

    if (fideIds.isEmpty) {
      debugPrint('[PremiumGames] No FIDE IDs for favorites');
      return [];
    }

    debugPrint(
      '[PremiumGames] Fetching games for ${fideIds.length} favorite players',
    );

    try {
      final games = await repository.getGamesByMultipleFideIds(
        fideIds: fideIds,
        limit: _pageSize,
        offset: _offset,
      );

      return games.map((g) => GamesTourModel.fromGame(g)).toList();
    } catch (e) {
      debugPrint('[PremiumGames] Error fetching favorite games: $e');
      return [];
    }
  }

  /// Fetch games for countrymen.
  Future<List<GamesTourModel>> _fetchCountrymenGames(
    GameRepository repository,
  ) async {
    final countryState = _ref.read(countryDropdownProvider);
    final country = countryState.value;

    if (country == null || country.countryCode.isEmpty) {
      debugPrint('[PremiumGames] No country selected');
      return [];
    }

    debugPrint(
      '[PremiumGames] Fetching games for country ${country.countryCode}',
    );

    try {
      final games = await repository.getGamesByCountryCodePaginated(
        countryCode: country.countryCode,
        limit: _pageSize,
        offset: _offset,
      );

      return games.map((g) => GamesTourModel.fromGame(g)).toList();
    } catch (e) {
      debugPrint('[PremiumGames] Error fetching countryman games: $e');
      return [];
    }
  }

  void _sortGames() {
    _allGames.sort((a, b) {
      if (_type == PremiumGamesType.countrymen) {
        // For Countrymen: Primary is avgElo DESC, Secondary is lastMoveTime DESC
        final aElo = _avgElo(a);
        final bElo = _avgElo(b);
        final eloCompare = bElo.compareTo(aElo);
        if (eloCompare != 0) return eloCompare;

        return (b.lastMoveTime ?? DateTime(0)).compareTo(
          a.lastMoveTime ?? DateTime(0),
        );
      } else {
        // For Favorites: Primary is lastMoveTime DESC, Secondary is avgElo DESC
        final timeCompare = (b.lastMoveTime ?? DateTime(0)).compareTo(
          a.lastMoveTime ?? DateTime(0),
        );
        if (timeCompare != 0) return timeCompare;

        final aElo = _avgElo(a);
        final bElo = _avgElo(b);
        return bElo.compareTo(aElo);
      }
    });
  }

  /// Calculate average ELO for a game.
  int _avgElo(GamesTourModel game) {
    final white = game.whitePlayer.rating;
    final black = game.blackPlayer.rating;
    if (white == 0 && black == 0) return 0;
    if (white == 0) return black;
    if (black == 0) return white;
    return (white + black) ~/ 2;
  }

  /// Get filtered games based on current filter.
  List<GamesTourModel> _getFilteredGames() {
    final filter = _ref.read(premiumGamesFilterProvider(_type));

    return _allGames.where((game) {
      // Date filter
      if (filter.dateRange.startDate != null) {
        final gameDate = game.lastMoveTime;
        if (gameDate == null ||
            gameDate.isBefore(filter.dateRange.startDate!)) {
          return false;
        }
      }

      // Result filter
      if (!filter.result.matches(game.effectiveGameStatus)) {
        return false;
      }

      final gameFilter = GameFilter(
        result: GameResultFilter.all,
        timeControl: filter.timeControl,
        eco: filter.eco,
        finish: filter.finish,
      );
      if (!GameFilterHelper.applyFilter([game], gameFilter).contains(game)) {
        return false;
      }

      // ELO filter
      final avgElo = _avgElo(game);
      if (filter.minElo != null && avgElo < filter.minElo!) {
        return false;
      }
      if (filter.maxElo != null && avgElo > filter.maxElo!) {
        return false;
      }

      return true;
    }).toList();
  }

  /// Apply new filter and update games.
  void applyFilter(PremiumGamesFilter filter) {
    _ref.read(premiumGamesFilterProvider(_type).notifier).state = filter;

    final currentState = state.valueOrNull;
    if (currentState == null) return;

    state = AsyncValue.data(
      PremiumGamesState(
        games: _getFilteredGames(),
        filter: filter,
        isLoadingMore: false,
        hasMore: _hasMore,
      ),
    );
  }

  /// Reset filter to defaults.
  void resetFilter() {
    applyFilter(PremiumGamesFilter.defaultFilter);
  }

  /// Refresh games (pull-to-refresh).
  Future<void> refresh() async {
    await loadGames(showLoading: false);
  }
}
