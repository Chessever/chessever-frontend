import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- State ---

class GamebasePlayerGamesState {
  final List<GamesTourModel> games;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  const GamebasePlayerGamesState({
    this.games = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
  });

  GamebasePlayerGamesState copyWith({
    List<GamesTourModel>? games,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return GamebasePlayerGamesState(
      games: games ?? this.games,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }
}

// --- Provider ---

final gamebasePlayerGamesProvider = StateNotifierProvider.autoDispose.family<
  GamebasePlayerGamesNotifier,
  GamebasePlayerGamesState,
  GamebasePlayer
>((ref, player) => GamebasePlayerGamesNotifier(ref, player));

class GamebasePlayerGamesNotifier
    extends StateNotifier<GamebasePlayerGamesState> {
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

      state = state.copyWith(
        games: games,
        isLoading: false,
        hasMore: games.length >= _pageSize,
        currentPage: 1,
        error: null,
      );
    } catch (e) {
      debugPrint('[GamebasePlayerGames] Initial load error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMoreGames() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final nextPage = state.currentPage + 1;
      final newGames = await _fetchGames(page: nextPage);
      if (!mounted) return;

      final allGames = [...state.games, ...newGames];

      state = state.copyWith(
        games: allGames,
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

      state = GamebasePlayerGamesState(
        games: games,
        isLoading: false,
        hasMore: games.length >= _pageSize,
        currentPage: 1,
      );
    } catch (e) {
      debugPrint('[GamebasePlayerGames] Refresh error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<List<GamesTourModel>> _fetchGames({required int page}) async {
    final repo = _ref.read(gamebaseRepositoryProvider);

    // `/api/search/query` for games is currently unreliable in production.
    // Use global search and narrow down to games that reference this player's
    // UUID in the preview payload.
    final query =
        (_player.fideId.trim().isNotEmpty)
            ? _player.fideId.trim()
            : _player.name.trim();

    debugPrint(
      '[GamebasePlayerGames] Searching games for player ${_player.id} (${_player.name}), page $page',
    );

    final response = await repo.globalSearch(
      query: query,
      pageNumber: page,
      // Fetch extra to account for mixed results.
      pageSize: (_pageSize * 3).clamp(20, 120),
    );

    final rows = response.results
        .where((r) => r.resource == 'game')
        .map((r) {
          final preview = r.preview ?? const <String, dynamic>{};
          final id = preview['id']?.toString() ?? r.id;
          return <String, dynamic>{'id': id, ...preview};
        })
        .where((row) {
          final w = row['whitePlayerId']?.toString();
          final b = row['blackPlayerId']?.toString();
          return w == _player.id || b == _player.id;
        })
        .take(_pageSize)
        .toList(growable: false);

    // Enrich players (titles/ratings/federations).
    final playerIds = <String>{};
    for (final row in rows) {
      final w = row['whitePlayerId']?.toString().trim();
      final b = row['blackPlayerId']?.toString().trim();
      if (w != null && w.isNotEmpty) playerIds.add(w);
      if (b != null && b.isNotEmpty) playerIds.add(b);
    }

    final byId = <String, GamebasePlayer>{};
    if (playerIds.isNotEmpty) {
      final fetched = await Future.wait(
        playerIds.map(repo.getPlayerById),
        eagerError: false,
      );
      for (final p in fetched.whereType<GamebasePlayer>()) {
        byId[p.id] = GamebasePlayer(
          id: p.id,
          fideId: p.fideId,
          name: p.name,
          gender: p.gender,
          fed: p.fed,
          title: ChessTitleUtils.normalize(p.title),
          ratingClassical: p.ratingClassical,
          ratingRapid: p.ratingRapid,
          ratingBlitz: p.ratingBlitz,
        );
      }
    }

    int ratingFor(GamebasePlayer? p, String? timeControl) {
      if (p == null) return 0;
      final tc = (timeControl ?? '').toUpperCase();
      switch (tc) {
        case 'RAPID':
          return p.ratingRapid ?? p.highestRating ?? 0;
        case 'BLITZ':
          return p.ratingBlitz ?? p.highestRating ?? 0;
        case 'CLASSICAL':
        default:
          return p.ratingClassical ?? p.highestRating ?? 0;
      }
    }

    DateTime? parseDate(Object? raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    return rows
        .map((row) {
          final id = row['id']?.toString() ?? 'unknown';
          final result = row['result']?.toString() ?? '*';
          final timeControl = row['timeControl']?.toString();
          final date = parseDate(row['date']);

          final whiteName =
              (row['white']?.toString() ??
                      row['whiteName']?.toString() ??
                      'White')
                  .trim();
          final blackName =
              (row['black']?.toString() ??
                      row['blackName']?.toString() ??
                      'Black')
                  .trim();
          final event = (row['event']?.toString() ?? 'Gamebase').trim();
          final site = row['site']?.toString();
          final eco = row['eco']?.toString();
          final opening = row['opening']?.toString();
          final variation = row['variation']?.toString();

          final w = byId[row['whitePlayerId']?.toString() ?? ''];
          final b = byId[row['blackPlayerId']?.toString() ?? ''];

          final pgn = buildHeaderOnlyPgn(
            whiteName: whiteName,
            blackName: blackName,
            result: result,
            event: event,
            site: site,
            date: date,
            eco: eco,
            opening: opening,
            variation: variation,
          );

          final whiteCard = PlayerCard(
            name: whiteName,
            federation: '',
            title: ChessTitleUtils.normalize(w?.title),
            rating: ratingFor(w, timeControl),
            countryCode: w?.fed ?? '',
            team: null,
            fideId: int.tryParse(w?.fideId ?? ''),
          );
          final blackCard = PlayerCard(
            name: blackName,
            federation: '',
            title: ChessTitleUtils.normalize(b?.title),
            rating: ratingFor(b, timeControl),
            countryCode: b?.fed ?? '',
            team: null,
            fideId: int.tryParse(b?.fideId ?? ''),
          );

          final formatCode =
              (eco != null && eco.trim().isNotEmpty)
                  ? eco.trim()
                  : (timeControl ?? '');

          final tourId =
              (row['tour_id']?.toString() ??
                      row['tournament_id']?.toString() ??
                      event)
                  .trim();

          return GamesTourModel(
            gameId: id,
            source: GameSource.gamebase,
            whitePlayer: whiteCard,
            blackPlayer: blackCard,
            whiteTimeDisplay: '--:--',
            blackTimeDisplay: '--:--',
            whiteClockCentiseconds: 0,
            blackClockCentiseconds: 0,
            gameStatus: GameStatus.fromString(result),
            roundId: 'gamebase_player',
            roundSlug: formatCode.isNotEmpty ? formatCode : null,
            tourId: tourId.isNotEmpty ? tourId : 'Gamebase',
            pgn: pgn,
            lastMoveTime: date,
          );
        })
        .toList(growable: false);
  }

  // NOTE: No longer uses `/api/search/query` + `/api/game/{id}`.
}
