import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/gamebase_filter_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider for the library search query.
/// Updated from library screen when search text changes.
final librarySearchQueryProvider = StateProvider<String>((ref) => '');

/// Pagination state for database games
class DatabaseGamesPaginationState {
  final List<GamesTourModel> games;
  final int currentPage;
  final int totalCount;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  const DatabaseGamesPaginationState({
    this.games = const [],
    this.currentPage = 1,
    this.totalCount = 0,
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  DatabaseGamesPaginationState copyWith({
    List<GamesTourModel>? games,
    int? currentPage,
    int? totalCount,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return DatabaseGamesPaginationState(
      games: games ?? this.games,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// Notifier for paginated database games
class DatabaseGamesPaginationNotifier extends StateNotifier<DatabaseGamesPaginationState> {
  final Ref _ref;
  final String _query;
  final GamebaseFilter _filter;

  static const int _pageSize = 20;

  DatabaseGamesPaginationNotifier(this._ref, this._query, this._filter)
      : super(const DatabaseGamesPaginationState()) {
    _loadInitialPage();
  }

  Future<void> _loadInitialPage() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _fetchPage(1);
      state = DatabaseGamesPaginationState(
        games: result.games,
        currentPage: 1,
        totalCount: result.totalCount,
        isLoading: false,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        hasMore: false,
      );
    }
  }

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final nextPage = state.currentPage + 1;
      final result = await _fetchPage(nextPage);

      state = state.copyWith(
        games: [...state.games, ...result.games],
        currentPage: nextPage,
        totalCount: result.totalCount,
        isLoading: false,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    state = const DatabaseGamesPaginationState(isLoading: true);
    await _loadInitialPage();
  }

  Future<_PageResult> _fetchPage(int pageNumber) async {
    final repo = _ref.read(gamebaseRepositoryProvider);

    // Use GET /api/search (token-based + FTS) because it is indexed and fast.
    // POST /api/search/query currently can be very slow for free-text search.
    final response = await repo.globalSearch(
      query: _query.trim().isEmpty ? '*' : _query.trim(),
      resources: const ['game'],
      pageNumber: pageNumber,
      pageSize: _pageSize,
      result: _filter.resultApiValue,
      color: _filter.colorApiValue,
      timeControl: _filter.timeControlApiValue,
      yearFrom: _filter.minYear != 1800 ? _filter.minYear : null,
      yearTo: _filter.maxYear != DateTime.now().year ? _filter.maxYear : null,
      ratingFrom: _filter.minRating > 0 ? _filter.minRating : null,
      ratingTo: _filter.maxRating < 3500 ? _filter.maxRating : null,
    );

    final gameResults = response.results
        .where((r) => r.resource == 'game')
        .toList(growable: false);

    if (gameResults.isEmpty) {
      return _PageResult(
        games: const [],
        totalCount: response.metadata.totalCount ?? 0,
        hasMore: false,
      );
    }

    final games = gameResults.map((result) {
      final preview = result.preview ?? const <String, dynamic>{};

      final id = (preview['id']?.toString() ?? result.id).trim();
      final safeId = id.isNotEmpty ? id : 'unknown';

      final timeControl = preview['timeControl']?.toString();
      final date = _parseDate(preview['date']);
      final resultStr = preview['result']?.toString() ?? '*';

      final whiteName = (preview['white']?.toString() ?? '').trim();
      final blackName = (preview['black']?.toString() ?? '').trim();

      final eco = preview['eco']?.toString() ?? '';
      final opening = preview['opening']?.toString() ?? '';
      final variation = preview['variation']?.toString() ?? '';
      final event = preview['event']?.toString() ?? 'Gamebase';
      final site = preview['site']?.toString();

      final pgn = buildHeaderOnlyPgn(
        whiteName: whiteName.isNotEmpty ? whiteName : 'White',
        blackName: blackName.isNotEmpty ? blackName : 'Black',
        result: resultStr,
        event: event,
        site: site,
        date: date,
        eco: eco,
        opening: opening,
        variation: variation,
      );

      final whiteElo = (preview['whiteElo'] as num?)?.toInt() ?? 0;
      final blackElo = (preview['blackElo'] as num?)?.toInt() ?? 0;
      final whiteFed = preview['whiteFed']?.toString() ?? '';
      final blackFed = preview['blackFed']?.toString() ?? '';

      final whiteCard = PlayerCard(
        name: whiteName.isNotEmpty ? whiteName : 'White',
        federation: '',
        title: '',
        rating: whiteElo,
        countryCode: whiteFed,
        team: null,
        fideId: null,
      );

      final blackCard = PlayerCard(
        name: blackName.isNotEmpty ? blackName : 'Black',
        federation: '',
        title: '',
        rating: blackElo,
        countryCode: blackFed,
        team: null,
        fideId: null,
      );

      final formatCode =
          (eco.trim().isNotEmpty) ? eco.trim() : (timeControl ?? '');

      return GamesTourModel(
        gameId: safeId,
        whitePlayer: whiteCard,
        blackPlayer: blackCard,
        whiteTimeDisplay: '--:--',
        blackTimeDisplay: '--:--',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: GameStatus.fromString(resultStr),
        roundId: 'gamebase_search',
        roundSlug: formatCode.isNotEmpty ? formatCode : null,
        tourId: event.trim().isNotEmpty ? event.trim() : 'Gamebase',
        pgn: pgn,
        lastMoveTime: date,
      );
    }).toList(growable: false);

    final totalCount = response.metadata.totalCount ?? 0;
    final hasMore = response.metadata.hasMore;

    return _PageResult(
      games: games,
      totalCount: totalCount,
      hasMore: hasMore,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}

class _PageResult {
  final List<GamesTourModel> games;
  final int totalCount;
  final bool hasMore;

  const _PageResult({
    required this.games,
    required this.totalCount,
    required this.hasMore,
  });
}

/// Provider for paginated database games with filter support
final gamebaseDatabaseGamesPaginatedProvider = StateNotifierProvider.autoDispose<
    DatabaseGamesPaginationNotifier, DatabaseGamesPaginationState>((ref) {
  final query = ref.watch(librarySearchQueryProvider);
  final filter = ref.watch(gamebaseFilterProvider);
  return DatabaseGamesPaginationNotifier(ref, query, filter);
});

/// Maps Gamebase search results into `GamesTourModel`s.
///
/// Uses the new simplified filter system via `gamebaseFilterProvider` and
/// passes filter parameters directly to the Gamebase API.
///
/// NOTE: This is the legacy non-paginated provider. Use
/// `gamebaseDatabaseGamesPaginatedProvider` for pagination support.
final gamebaseDatabaseGamesProvider = FutureProvider.autoDispose<
  List<GamesTourModel>
>((ref) async {
  final query = ref.watch(librarySearchQueryProvider);
  final filter = ref.watch(gamebaseFilterProvider);

  // If no query and no active filters, return empty
  if (query.trim().isEmpty && !filter.hasActiveFilters) {
    return const <GamesTourModel>[];
  }

  final repo = ref.read(gamebaseRepositoryProvider);

  try {
    // Call globalSearch with filter parameters
    // Use resources: ['game'] to limit search to games only (faster)
    final response = await repo.globalSearch(
      query: query.trim().isEmpty ? '*' : query.trim(),
      resources: const ['game'],
      pageNumber: 1,
      pageSize: 50,
      result: filter.resultApiValue,
      color: filter.colorApiValue,
      timeControl: filter.timeControlApiValue,
      yearFrom: filter.minYear != 1800 ? filter.minYear : null,
      yearTo: filter.maxYear != DateTime.now().year ? filter.maxYear : null,
      ratingFrom: filter.minRating > 0 ? filter.minRating : null,
      ratingTo: filter.maxRating < 3500 ? filter.maxRating : null,
    );

    // Extract game results
    final gameResults = response.results
        .where((r) => r.resource == 'game')
        .toList();

    if (gameResults.isEmpty) {
      return const <GamesTourModel>[];
    }

    // Collect player IDs for enrichment
    final playerIds = <String>{};
    for (final result in gameResults) {
      final preview = result.preview ?? const <String, dynamic>{};
      final w = preview['whitePlayerId']?.toString().trim();
      final b = preview['blackPlayerId']?.toString().trim();
      if (w != null && w.isNotEmpty) playerIds.add(w);
      if (b != null && b.isNotEmpty) playerIds.add(b);
    }

    // Fetch player details for enrichment
    final playerDetails = <String, GamebasePlayer>{};
    if (playerIds.isNotEmpty) {
      final fetched = await Future.wait(
        playerIds.map(repo.getPlayerById),
        eagerError: false,
      );
      for (final p in fetched.whereType<GamebasePlayer>()) {
        playerDetails[p.id] = GamebasePlayer(
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

    String coalesceName(Map<String, dynamic> row, String keyA, String keyB) {
      final a = (row[keyA]?.toString() ?? '').trim();
      if (a.isNotEmpty) return a;
      final b = (row[keyB]?.toString() ?? '').trim();
      return b.isNotEmpty ? b : (keyA.startsWith('white') ? 'White' : 'Black');
    }

    return gameResults.map((result) {
      final row = <String, dynamic>{
        'id': result.id,
        'label': result.label,
        'snippet': result.snippet,
        ...?result.preview,
      };

      final id = (row['id']?.toString() ?? '').trim();
      final safeId = id.isNotEmpty ? id : 'unknown';
      final timeControl = row['timeControl']?.toString();
      final date = parseDate(row['date']);
      final resultStr = row['result']?.toString() ?? '*';

      final whiteName = coalesceName(row, 'white', 'whiteName');
      final blackName = coalesceName(row, 'black', 'blackName');

      final whitePlayerId = row['whitePlayerId']?.toString().trim();
      final blackPlayerId = row['blackPlayerId']?.toString().trim();
      final whitePlayer = (whitePlayerId != null) ? playerDetails[whitePlayerId] : null;
      final blackPlayer = (blackPlayerId != null) ? playerDetails[blackPlayerId] : null;

      final whiteTitle = ChessTitleUtils.normalize(
        row['whiteTitle']?.toString() ?? whitePlayer?.title,
      );
      final blackTitle = ChessTitleUtils.normalize(
        row['blackTitle']?.toString() ?? blackPlayer?.title,
      );

      final eco = row['eco']?.toString() ?? '';
      final opening = row['opening']?.toString() ?? '';
      final variation = row['variation']?.toString() ?? '';
      final event = row['event']?.toString() ?? 'Gamebase';
      final site = row['site']?.toString();

      final pgn = buildHeaderOnlyPgn(
        whiteName: whiteName,
        blackName: blackName,
        result: resultStr,
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
        title: whiteTitle,
        rating: ratingFor(whitePlayer, timeControl),
        countryCode: whitePlayer?.fed ?? '',
        team: null,
        fideId: int.tryParse(whitePlayer?.fideId ?? ''),
      );

      final blackCard = PlayerCard(
        name: blackName,
        federation: '',
        title: blackTitle,
        rating: ratingFor(blackPlayer, timeControl),
        countryCode: blackPlayer?.fed ?? '',
        team: null,
        fideId: int.tryParse(blackPlayer?.fideId ?? ''),
      );

      final formatCode = (eco.trim().isNotEmpty) ? eco.trim() : (timeControl ?? '');

      return GamesTourModel(
        gameId: safeId,
        whitePlayer: whiteCard,
        blackPlayer: blackCard,
        whiteTimeDisplay: '--:--',
        blackTimeDisplay: '--:--',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: GameStatus.fromString(resultStr),
        roundId: 'gamebase_search',
        roundSlug: formatCode.isNotEmpty ? formatCode : null,
        tourId: event.trim().isNotEmpty ? event.trim() : 'Gamebase',
        pgn: pgn,
        lastMoveTime: date,
      );
    }).toList(growable: false);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[GamebaseDatabaseGames] Error: $e');
      debugPrintStack(stackTrace: st);
    }
    return const <GamesTourModel>[];
  }
});
