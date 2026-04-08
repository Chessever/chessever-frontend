import 'dart:async';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum BookGamesResultFilter { all, whiteWins, blackWins, draw }

extension BookGamesResultFilterX on BookGamesResultFilter {
  String get displayText {
    switch (this) {
      case BookGamesResultFilter.all:
        return 'All Results';
      case BookGamesResultFilter.whiteWins:
        return '1-0';
      case BookGamesResultFilter.blackWins:
        return '0-1';
      case BookGamesResultFilter.draw:
        return '½-½';
    }
  }

  String? get statusValue {
    switch (this) {
      case BookGamesResultFilter.all:
        return null;
      case BookGamesResultFilter.whiteWins:
        return '1-0';
      case BookGamesResultFilter.blackWins:
        return '0-1';
      case BookGamesResultFilter.draw:
        return '1/2-1/2';
    }
  }

  bool matches(GameStatus status) {
    switch (this) {
      case BookGamesResultFilter.all:
        return true;
      case BookGamesResultFilter.whiteWins:
        return status == GameStatus.whiteWins;
      case BookGamesResultFilter.blackWins:
        return status == GameStatus.blackWins;
      case BookGamesResultFilter.draw:
        return status == GameStatus.draw;
    }
  }
}

enum BookGamesColorFilter { all, white, black }

extension BookGamesColorFilterX on BookGamesColorFilter {
  String get displayText {
    switch (this) {
      case BookGamesColorFilter.all:
        return 'All Colors';
      case BookGamesColorFilter.white:
        return 'White';
      case BookGamesColorFilter.black:
        return 'Black';
    }
  }
}

enum BookGamesTimeControlFilter { all, classical, rapid, blitz }

extension BookGamesTimeControlFilterX on BookGamesTimeControlFilter {
  String get displayText {
    switch (this) {
      case BookGamesTimeControlFilter.all:
        return 'All Time Controls';
      case BookGamesTimeControlFilter.classical:
        return 'Classical';
      case BookGamesTimeControlFilter.rapid:
        return 'Rapid';
      case BookGamesTimeControlFilter.blitz:
        return 'Blitz';
    }
  }
}

class BookGamesFilter {
  const BookGamesFilter({
    this.result = BookGamesResultFilter.all,
    this.color = BookGamesColorFilter.all,
    this.timeControl = BookGamesTimeControlFilter.all,
    this.minYear = GameFilter.defaultMinYear,
    this.maxYear = 2100,
    this.minRating = GameFilter.defaultMinRating,
    this.maxRating = GameFilter.absoluteMaxRating,
    this.opening = '',
    this.eco = '',
    this.event = '',
    this.player = '',
    this.federation = '',
  });

  final BookGamesResultFilter result;
  final BookGamesColorFilter color;
  final BookGamesTimeControlFilter timeControl;
  final int minYear;
  final int maxYear;
  final int minRating;
  final int maxRating;
  final String opening;
  final String eco;
  final String event;
  final String player;
  final String federation;

  bool get hasActiveFilters =>
      result != BookGamesResultFilter.all ||
      color != BookGamesColorFilter.all ||
      timeControl != BookGamesTimeControlFilter.all ||
      minYear != GameFilter.defaultMinYear ||
      maxYear != DateTime.now().year ||
      minRating != GameFilter.defaultMinRating ||
      maxRating != GameFilter.absoluteMaxRating ||
      opening.trim().isNotEmpty ||
      eco.trim().isNotEmpty ||
      event.trim().isNotEmpty ||
      player.trim().isNotEmpty ||
      federation.trim().isNotEmpty;

  BookGamesFilter copyWith({
    BookGamesResultFilter? result,
    BookGamesColorFilter? color,
    BookGamesTimeControlFilter? timeControl,
    int? minYear,
    int? maxYear,
    int? minRating,
    int? maxRating,
    String? opening,
    String? eco,
    String? event,
    String? player,
    String? federation,
  }) {
    return BookGamesFilter(
      result: result ?? this.result,
      color: color ?? this.color,
      timeControl: timeControl ?? this.timeControl,
      minYear: minYear ?? this.minYear,
      maxYear: maxYear ?? this.maxYear,
      minRating: minRating ?? this.minRating,
      maxRating: maxRating ?? this.maxRating,
      opening: opening ?? this.opening,
      eco: eco ?? this.eco,
      event: event ?? this.event,
      player: player ?? this.player,
      federation: federation ?? this.federation,
    );
  }

  static BookGamesFilter defaultFilter() =>
      BookGamesFilter(maxYear: DateTime.now().year);
}

class BookGamesSearchState {
  const BookGamesSearchState({
    required this.query,
    required this.games,
    required this.filter,
    required this.isLoadingMore,
    required this.hasMore,
  });

  final String query;
  final List<GamesTourModel> games;
  final BookGamesFilter filter;
  final bool isLoadingMore;
  final bool hasMore;

  static BookGamesSearchState initial() => BookGamesSearchState(
    query: '',
    games: const [],
    filter: BookGamesFilter.defaultFilter(),
    isLoadingMore: false,
    hasMore: true,
  );

  BookGamesSearchState copyWith({
    String? query,
    List<GamesTourModel>? games,
    BookGamesFilter? filter,
    bool? isLoadingMore,
    bool? hasMore,
  }) {
    return BookGamesSearchState(
      query: query ?? this.query,
      games: games ?? this.games,
      filter: filter ?? this.filter,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

final bookGamesSearchProvider = StateNotifierProvider.autoDispose<
  BookGamesSearchNotifier,
  AsyncValue<BookGamesSearchState>
>((ref) {
  ref.keepAlive();
  return BookGamesSearchNotifier(ref);
});

class BookGamesSearchNotifier
    extends StateNotifier<AsyncValue<BookGamesSearchState>> {
  BookGamesSearchNotifier(this._ref)
    : super(AsyncValue.data(BookGamesSearchState.initial()));

  final Ref _ref;

  final List<GamesTourModel> _rawGames = [];
  Timer? _debounceTimer;
  bool _isFetching = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 30;

  void setQuery(String query) {
    final trimmed = query.trim();
    final current = state.valueOrNull;

    if (trimmed.isEmpty) {
      _debounceTimer?.cancel();
      _rawGames.clear();
      _offset = 0;
      _hasMore = true;
      if (current != null) {
        state = AsyncValue.data(
          current.copyWith(query: '', games: const [], hasMore: true),
        );
      }
      return;
    }

    if (current != null &&
        trimmed == current.query &&
        _rawGames.isNotEmpty &&
        !_isFetching) {
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 380), () {
      _performSearch(trimmed, reset: true);
    });

    if (!state.isLoading) {
      state = const AsyncValue.loading();
    }
  }

  Future<void> applyFilter(BookGamesFilter filter) async {
    final current = state.valueOrNull ?? BookGamesSearchState.initial();
    state = AsyncValue.data(
      current.copyWith(
        filter: filter,
        games: _applyClientFilters(_rawGames, filter, current.query),
      ),
    );
  }

  Future<void> refresh() async {
    final current = state.valueOrNull;
    if (current == null || current.query.isEmpty) return;
    await _performSearch(current.query, reset: true);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.query.isEmpty) return;
    if (_isFetching || !_hasMore) return;

    _isFetching = true;
    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      await _performSearch(current.query, reset: false);
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _performSearch(String query, {required bool reset}) async {
    if (_isFetching && reset) return;
    _isFetching = true;

    try {
      final existingFilter =
          state.valueOrNull?.filter ?? BookGamesFilter.defaultFilter();
      if (reset) {
        _rawGames.clear();
        _offset = 0;
        _hasMore = true;
        state = const AsyncValue.loading();
      }

      final filter = existingFilter;
      final termsSet = <String>{
        ..._tokenizeQuery(query),
        ..._tokenizeQuery(filter.opening),
        ..._tokenizeQuery(filter.eco),
        ..._tokenizeQuery(filter.event),
        ..._tokenizeQuery(filter.player),
        ..._tokenizeQuery(filter.federation),
      };
      final terms = termsSet.toList();
      final repository = _ref.read(gameRepositoryProvider);
      final status = filter.result.statusValue;

      final response = await repository.searchGamesBySearchTermsPaginated(
        terms: terms,
        limit: _pageSize,
        offset: _offset,
        status: status,
      );

      if (response.isEmpty) {
        _hasMore = false;
      } else {
        final models =
            response
                .map((g) {
                  try {
                    return GamesTourModel.fromGame(g);
                  } catch (_) {
                    return null;
                  }
                })
                .whereType<GamesTourModel>()
                .toList();
        _rawGames.addAll(models);
        _offset += response.length;
      }

      final filtered = _applyClientFilters(_rawGames, filter, query);

      state = AsyncValue.data(
        BookGamesSearchState(
          query: query,
          games: filtered,
          filter: filter,
          isLoadingMore: false,
          hasMore: _hasMore,
        ),
      );
    } catch (e, stack) {
      debugPrint('[BookGamesSearch] error: $e');
      state = AsyncValue.error(e, stack);
    } finally {
      _isFetching = false;
    }
  }

  List<String> _tokenizeQuery(String query) {
    final normalized = query.toLowerCase().trim();
    if (normalized.isEmpty) return const [];
    final cleaned = normalized
        // normalize curly quotes/apostrophes etc.
        .replaceAll(RegExp(r'''[’'"`]+'''), '')
        // treat hyphens/underscores as word separators
        .replaceAll(RegExp(r'[_-]+'), ' ');
    return cleaned
        .split(RegExp(r'[\s,;:/()\[\]{}]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  List<GamesTourModel> _applyClientFilters(
    List<GamesTourModel> input,
    BookGamesFilter filter,
    String query,
  ) {
    final qLower = query.toLowerCase().trim();
    return input.where((game) {
      if (!filter.result.matches(game.gameStatus)) return false;

      if (filter.timeControl != BookGamesTimeControlFilter.all) {
        final inferred = _inferTimeControl(game);
        if (inferred != filter.timeControl) return false;
      }

      final year = game.lastMoveTime?.year;
      if (year != null) {
        if (year < filter.minYear || year > filter.maxYear) return false;
      }

      final avgRating = (game.whitePlayer.rating + game.blackPlayer.rating) / 2;
      if (avgRating < filter.minRating || avgRating > filter.maxRating) {
        return false;
      }

      if (filter.color != BookGamesColorFilter.all && qLower.isNotEmpty) {
        final whiteName = game.whitePlayer.name.toLowerCase();
        final blackName = game.blackPlayer.name.toLowerCase();
        if (filter.color == BookGamesColorFilter.white &&
            !whiteName.contains(qLower)) {
          return false;
        }
        if (filter.color == BookGamesColorFilter.black &&
            !blackName.contains(qLower)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  BookGamesTimeControlFilter _inferTimeControl(GamesTourModel game) {
    // Use the actual time_control from group_broadcasts (via tours join)
    // Do NOT use remaining clock time - it's unreliable (a classical game
    // with 5 minutes left would be wrongly classified as blitz)
    if (game.timeControl != null && game.timeControl!.isNotEmpty) {
      switch (game.timeControl!.toLowerCase()) {
        case 'standard':
        case 'classical':
          return BookGamesTimeControlFilter.classical;
        case 'rapid':
          return BookGamesTimeControlFilter.rapid;
        case 'blitz':
        case 'bullet':
          return BookGamesTimeControlFilter.blitz;
      }
    }
    // If time control is not set in the database, return 'all' (unknown)
    return BookGamesTimeControlFilter.all;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
