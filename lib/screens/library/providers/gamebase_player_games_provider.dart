import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- State ---

class GamebasePlayerGamesState {
  final List<TournamentGamesGroup> groupedGames;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  const GamebasePlayerGamesState({
    this.groupedGames = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
  });

  GamebasePlayerGamesState copyWith({
    List<TournamentGamesGroup>? groupedGames,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return GamebasePlayerGamesState(
      groupedGames: groupedGames ?? this.groupedGames,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }

  List<GamesTourModel> get allGames =>
      groupedGames.expand((g) => g.games).toList();
}

class TournamentGamesGroup {
  final String tourId;
  final String tourName;
  final List<GamesTourModel> games;

  const TournamentGamesGroup({
    required this.tourId,
    required this.tourName,
    required this.games,
  });
}

// --- Provider ---

final gamebasePlayerGamesProvider = StateNotifierProvider.autoDispose
    .family<GamebasePlayerGamesNotifier, GamebasePlayerGamesState, GamebasePlayer>(
  (ref, player) => GamebasePlayerGamesNotifier(ref, player),
);

class GamebasePlayerGamesNotifier extends StateNotifier<GamebasePlayerGamesState> {
  final Ref _ref;
  final GamebasePlayer _player;
  static const int _pageSize = 30;

  GamebasePlayerGamesNotifier(this._ref, this._player)
      : super(const GamebasePlayerGamesState(isLoading: true)) {
    _loadInitialGames();
  }

  Future<void> _loadInitialGames() async {
    try {
      final games = await _fetchGames(page: 1);
      if (!mounted) return;

      final grouped = _groupGamesByEvent(games);
      state = state.copyWith(
        groupedGames: grouped,
        isLoading: false,
        hasMore: games.length >= _pageSize,
        currentPage: 1,
        error: null,
      );
    } catch (e) {
      debugPrint('[GamebasePlayerGames] Initial load error: $e');
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadMoreGames() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final nextPage = state.currentPage + 1;
      final newGames = await _fetchGames(page: nextPage);
      if (!mounted) return;

      final allGames = [...state.allGames, ...newGames];
      final grouped = _groupGamesByEvent(allGames);

      state = state.copyWith(
        groupedGames: grouped,
        isLoading: false,
        hasMore: newGames.length >= _pageSize,
        currentPage: nextPage,
      );
    } catch (e) {
      debugPrint('[GamebasePlayerGames] Load more error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refreshGames() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final games = await _fetchGames(page: 1);
      if (!mounted) return;

      final grouped = _groupGamesByEvent(games);
      state = GamebasePlayerGamesState(
        groupedGames: grouped,
        isLoading: false,
        hasMore: games.length >= _pageSize,
        currentPage: 1,
      );
    } catch (e) {
      debugPrint('[GamebasePlayerGames] Refresh error: $e');
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<List<GamesTourModel>> _fetchGames({required int page}) async {
    final repo = _ref.read(gamebaseRepositoryProvider);

    // Query games where this player is white OR black.
    // The search/query endpoint returns IDs; we fetch full game details per row
    // to render player names/event/eco.
    final body = {
      'resource': 'game',
      'where': {
        'or': [
          {'field': 'whitePlayerId', 'op': 'eq', 'value': _player.id},
          {'field': 'blackPlayerId', 'op': 'eq', 'value': _player.id},
        ],
      },
      'orderBy': [
        {'field': 'date', 'direction': 'desc'},
      ],
      'pageNumber': page,
      'pageSize': _pageSize,
    };

    debugPrint('[GamebasePlayerGames] Fetching games for player ${_player.id} (${_player.name}), page $page');

    final response = await repo.queryResource(body: body);
    debugPrint('[GamebasePlayerGames] Got ${response.data.length} game rows');

    final rows = response.data;
    final ids =
        rows
            .map((row) => (row['id']?.toString() ?? '').trim())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList();

    final details = await Future.wait(
      ids.map(repo.getGameById),
      eagerError: false,
    );

    final byId = <String, GamebaseGame?>{
      for (var i = 0; i < ids.length; i++) ids[i]: details[i],
    };

    return rows.map((row) {
      final id = row['id']?.toString() ?? 'unknown';
      return _mapToGameModel(row: row, game: byId[id]);
    }).toList();
  }

  GamesTourModel _mapToGameModel({
    required Map<String, dynamic> row,
    required GamebaseGame? game,
  }) {
    if (game != null) {
      return mapGamebaseGameToGamesTourModel(game);
    }

    final id = row['id']?.toString() ?? 'unknown';
    final result = row['result']?.toString() ?? '*';

    final unknownPlayer = PlayerCard(
      name: 'Unknown',
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    );

    return GamesTourModel(
      gameId: id,
      whitePlayer: unknownPlayer,
      blackPlayer: unknownPlayer,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.fromString(result),
      roundId: 'gamebase',
      tourId: 'Gamebase',
    );
  }

  List<TournamentGamesGroup> _groupGamesByEvent(List<GamesTourModel> games) {
    final Map<String, List<GamesTourModel>> grouped = {};

    for (final game in games) {
      final eventName = game.tourId;
      grouped.putIfAbsent(eventName, () => []).add(game);
    }

    return grouped.entries
        .map((e) => TournamentGamesGroup(
              tourId: e.key,
              tourName: e.key,
              games: e.value,
            ))
        .toList();
  }
}
