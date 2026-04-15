import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models_extra.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/gamebase_filter_provider.dart';
import 'package:chessever2/screens/library/providers/twic_event_aggregates_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/twic_player_enrichment.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider for the library search query.
/// Updated from library screen when search text changes.
final librarySearchQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

/// Pagination state for database games
class DatabaseGamesPaginationState {
  final List<GamesTourModel> games;
  final int currentPage;
  final int totalCount;
  final bool totalCountIsEstimate;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  const DatabaseGamesPaginationState({
    this.games = const [],
    this.currentPage = 1,
    this.totalCount = 0,
    this.totalCountIsEstimate = false,
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  DatabaseGamesPaginationState copyWith({
    List<GamesTourModel>? games,
    int? currentPage,
    int? totalCount,
    bool? totalCountIsEstimate,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return DatabaseGamesPaginationState(
      games: games ?? this.games,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      totalCountIsEstimate: totalCountIsEstimate ?? this.totalCountIsEstimate,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// Notifier for paginated database games
bool _hasYearFilter(GamebaseFilter filter) =>
    filter.minYear != GameFilter.absoluteMinYear || filter.maxYear != DateTime.now().year;

List<String> _libraryExactGameSelectColumns() => const [
  'id',
  'date',
  'result',
  'timeControl',
  'whiteName',
  'blackName',
  'white',
  'black',
  'whitePlayerId',
  'blackPlayerId',
  'whiteFideId',
  'blackFideId',
  'whiteTitle',
  'blackTitle',
  'whiteFed',
  'blackFed',
  'whiteElo',
  'blackElo',
  'eco',
  'opening',
  'variation',
  'event',
  'tour_id',
  'tournament_id',
  'site',
  'fen',
  'finalFen',
  'positionFen',
  'lastMove',
];

Map<String, dynamic>? _buildLibraryExactWhere(
  GamebaseFilter filter, {
  String? selectedEvent,
}) {
  final expressions = <Map<String, dynamic>>[];

  if (selectedEvent != null && selectedEvent.isNotEmpty) {
    expressions.add({'field': 'event', 'op': 'eq', 'value': selectedEvent});
  }
  if (filter.resultApiValue != null) {
    expressions.add({
      'field': 'result',
      'op': 'eq',
      'value': filter.resultApiValue,
    });
  }
  if (filter.timeControlApiValue != null) {
    expressions.add({
      'field': 'timeControl',
      'op': 'eq',
      'value': filter.timeControlApiValue,
    });
  }
  if (filter.isOnlineApiValue != null) {
    expressions.add({
      'field': 'isOnline',
      'op': 'eq',
      'value': filter.isOnlineApiValue,
    });
  }
  if (!filter.eco.isAll) {
    expressions.add({
      'field': 'eco',
      'op': 'ilike',
      'value': '${filter.eco.code}%',
    });
  }
  if (_hasYearFilter(filter)) {
    expressions.add({
      'field': 'date',
      'op': 'between',
      'values': [
        '${filter.minYear.toString().padLeft(4, '0')}-01-01T00:00:00.000Z',
        '${filter.maxYear.toString().padLeft(4, '0')}-12-31T23:59:59.999Z',
      ],
    });
  }

  // Structured Elo filtering using the averageRating calculated field
  if (filter.minRating > GameFilter.absoluteMinRating ||
      filter.maxRating < GameFilter.absoluteMaxRating) {
    expressions.add({
      'field': 'averageRating',
      'op': 'between',
      'values': [filter.minRating, filter.maxRating],
    });
  }

  if (expressions.isEmpty) return null;
  if (expressions.length == 1) return expressions.first;
  return {'and': expressions};
}

@visibleForTesting
bool shouldUseExactLibraryGameQuery(String query, GamebaseFilter filter) {
  // If there's a free-text query, use globalSearch (indexed tsvector).
  if (query.trim().isNotEmpty) return false;

  // Use exact query only if we have selective structured filters (year or rating).
  final hasYear = _hasYearFilter(filter);
  final hasRating = filter.minRating > GameFilter.absoluteMinRating ||
      filter.maxRating < GameFilter.absoluteMaxRating;

  if (!hasYear && !hasRating) return false;

  // Exact query currently doesn't handle color filter as easily as globalSearch.
  if (filter.colorApiValue != null) return false;

  return true;
}

@visibleForTesting
bool shouldUseClientSideYearFiltering(String query, GamebaseFilter filter) {
  return query.trim().isNotEmpty && _hasYearFilter(filter);
}

List<Map<String, dynamic>> _rowsFromGlobalSearchResponse(
  GamebaseGlobalSearchResponse response,
) {
  return response.results
      .where((r) => r.resource == 'game')
      .map((r) {
        final preview = Map<String, dynamic>.from(r.preview ?? const {});
        final resultId = r.id.toString().trim();
        final previewId = (preview['id']?.toString() ?? '').trim();
        final id = resultId.isNotEmpty ? resultId : previewId;
        return <String, dynamic>{...preview, 'id': id};
      })
      .toList(growable: false);
}

class DatabaseGamesPaginationNotifier
    extends StateNotifier<DatabaseGamesPaginationState> {
  final Ref _ref;
  final String _query;
  final GamebaseFilter _filter;
  final String? _selectedEvent;

  static const int _pageSize = 20;

  DatabaseGamesPaginationNotifier(
    this._ref,
    this._query,
    this._filter,
    this._selectedEvent,
  ) : super(const DatabaseGamesPaginationState()) {
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
        totalCountIsEstimate: result.totalCountIsEstimate,
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
        totalCountIsEstimate: result.totalCountIsEstimate,
        isLoading: false,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    state = const DatabaseGamesPaginationState(isLoading: true);
    await _loadInitialPage();
  }

  Future<_PageResult> _fetchPage(int pageNumber) async {
    final repo = _ref.read(gamebaseRepositoryProvider);
    final baseQuery = _query.trim().isEmpty ? '*' : _query.trim();
    final selectedEvent = _selectedEvent?.trim();
    final escapedEvent = selectedEvent?.replaceAll('"', r'\"');
    final composedQuery =
        (escapedEvent == null || escapedEvent.isEmpty)
            ? baseQuery
            : '$baseQuery event:"$escapedEvent"';
    late final List<Map<String, dynamic>> rawRows;
    late final int totalCount;
    late final bool totalCountIsEstimate;
    late final bool hasMore;

    if (shouldUseExactLibraryGameQuery(_query, _filter)) {
      final where = _buildLibraryExactWhere(
        _filter,
        selectedEvent: selectedEvent,
      );
      final response = await repo.queryResource(
        body: {
          'resource': 'game',
          'pageNumber': pageNumber,
          'pageSize': _pageSize,
          'includeTotal': true,
          'countMode': 'auto',
          if (_query.trim().isNotEmpty) 'q': _query.trim(),
          'select': _libraryExactGameSelectColumns(),
          if (where != null) 'where': where,
        },
      );
      rawRows = response.data;
      totalCount = response.metadata.totalCount ?? rawRows.length;
      totalCountIsEstimate = response.metadata.totalCountIsEstimate;
      hasMore = response.metadata.hasMore;
    } else {
      // Use GET /api/search (token-based + FTS) because it is indexed and fast.
      // POST /api/search/query currently can be very slow for free-text search.
      String finalQuery = composedQuery;
      if (!_filter.eco.isAll) {
        finalQuery = 'eco:${_filter.eco.code} $finalQuery';
      }

      final response = await repo.globalSearch(
        query: finalQuery,
        resources: const ['game'],
        pageNumber: pageNumber,
        pageSize: _pageSize,
        result: _filter.resultApiValue,
        color: _filter.colorApiValue,
        timeControl: _filter.timeControlApiValue,
        isOnline: _filter.isOnlineApiValue,
        yearFrom: _filter.minYear != GameFilter.absoluteMinYear ? _filter.minYear : null,
        yearTo: _filter.maxYear != DateTime.now().year ? _filter.maxYear : null,
        ratingFrom: _filter.minRating > GameFilter.absoluteMinRating ? _filter.minRating : null,
        ratingTo: _filter.maxRating < GameFilter.absoluteMaxRating ? _filter.maxRating : null,
      );
      rawRows = _rowsFromGlobalSearchResponse(response);
      totalCount = response.metadata.totalCount ?? 0;
      totalCountIsEstimate = response.metadata.totalCountIsEstimate;
      hasMore = response.metadata.hasMore;
    }

    if (rawRows.isEmpty) {
      return _PageResult(
        games: const [],
        totalCount: totalCount,
        totalCountIsEstimate: totalCountIsEstimate,
        hasMore: hasMore,
      );
    }

    final playerIdsForEnrichment = <String>{};
    final fideIdsForEnrichment = <int>{};
    for (final row in rawRows) {
      final whitePlayerId = row['whitePlayerId']?.toString().trim();
      final blackPlayerId = row['blackPlayerId']?.toString().trim();
      if (whitePlayerId != null && whitePlayerId.isNotEmpty) {
        playerIdsForEnrichment.add(whitePlayerId);
      }
      if (blackPlayerId != null && blackPlayerId.isNotEmpty) {
        playerIdsForEnrichment.add(blackPlayerId);
      }
      final whiteFideId = parseFideIdFromRaw(row['whiteFideId']);
      final blackFideId = parseFideIdFromRaw(row['blackFideId']);
      if (whiteFideId != null) fideIdsForEnrichment.add(whiteFideId);
      if (blackFideId != null) fideIdsForEnrichment.add(blackFideId);
    }
    final gamebasePlayersById = <String, GamebasePlayer>{};
    if (playerIdsForEnrichment.isNotEmpty) {
      final players = await Future.wait(
        playerIdsForEnrichment.map(repo.getPlayerById),
        eagerError: false,
      );
      for (final player in players.whereType<GamebasePlayer>()) {
        gamebasePlayersById[player.id] = player;
        final parsedFide = int.tryParse(player.fideId);
        if (parsedFide != null && parsedFide > 0) {
          fideIdsForEnrichment.add(parsedFide);
        }
      }
    }
    final chessPlayersByFideId =
        fideIdsForEnrichment.isEmpty
            ? const <int, ChessPlayer>{}
            : await _ref
                .read(chessPlayerRepositoryProvider)
                .getPlayersByFideIds(fideIdsForEnrichment);

    int ratingFor(GamebasePlayer? player, String? timeControl) {
      if (player == null) return 0;
      final tc = (timeControl ?? '').toUpperCase();
      switch (tc) {
        case 'RAPID':
          return player.ratingRapid ?? player.highestRating ?? 0;
        case 'BLITZ':
          return player.ratingBlitz ?? player.highestRating ?? 0;
        case 'CLASSICAL':
        default:
          return player.ratingClassical ?? player.highestRating ?? 0;
      }
    }

    final games = rawRows
        .map((preview) {
          final id = (preview['id']?.toString() ?? '').trim();
          final safeId = id.isNotEmpty ? id : 'unknown';

          final timeControl = preview['timeControl']?.toString();
          final date = _parseDate(preview['date']);
          final resultStr = preview['result']?.toString() ?? '*';

          final whiteName = coalesceName(preview, 'white', 'whiteName');
          final blackName = coalesceName(preview, 'black', 'blackName');

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

          final whitePlayerId = preview['whitePlayerId']?.toString().trim();
          final blackPlayerId = preview['blackPlayerId']?.toString().trim();
          final whitePlayer =
              (whitePlayerId != null && whitePlayerId.isNotEmpty)
                  ? gamebasePlayersById[whitePlayerId]
                  : null;
          final blackPlayer =
              (blackPlayerId != null && blackPlayerId.isNotEmpty)
                  ? gamebasePlayersById[blackPlayerId]
                  : null;
          final whiteEloRaw = (preview['whiteElo'] as num?)?.toInt() ?? 0;
          final blackEloRaw = (preview['blackElo'] as num?)?.toInt() ?? 0;
          final whiteElo =
              whiteEloRaw > 0
                  ? whiteEloRaw
                  : ratingFor(whitePlayer, timeControl);
          final blackElo =
              blackEloRaw > 0
                  ? blackEloRaw
                  : ratingFor(blackPlayer, timeControl);
          final whiteFed =
              (preview['whiteFed']?.toString().trim().isNotEmpty ?? false)
                  ? preview['whiteFed'].toString().trim()
                  : (whitePlayer?.fed ?? '');
          final blackFed =
              (preview['blackFed']?.toString().trim().isNotEmpty ?? false)
                  ? preview['blackFed'].toString().trim()
                  : (blackPlayer?.fed ?? '');
          final whiteTitle = ChessTitleUtils.normalize(
            preview['whiteTitle']?.toString() ?? whitePlayer?.title,
          );
          final blackTitle = ChessTitleUtils.normalize(
            preview['blackTitle']?.toString() ?? blackPlayer?.title,
          );
          final whiteFideId =
              int.tryParse(preview['whiteFideId']?.toString() ?? '') ??
              int.tryParse(whitePlayer?.fideId ?? '');
          final blackFideId =
              int.tryParse(preview['blackFideId']?.toString() ?? '') ??
              int.tryParse(blackPlayer?.fideId ?? '');
          final rowFen =
              preview['fen']?.toString() ??
              preview['finalFen']?.toString() ??
              preview['positionFen']?.toString();
          final rowLastMove = preview['lastMove']?.toString();

          final whiteCard = enrichPlayerCardFromChessPlayers(
            PlayerCard(
              name: whiteName.isNotEmpty ? whiteName : 'White',
              federation: whiteFed,
              title: whiteTitle,
              rating: whiteElo,
              countryCode: whiteFed,
              team: null,
              fideId: whiteFideId,
              gamebasePlayerId:
                  (whitePlayerId != null && whitePlayerId.isNotEmpty)
                      ? whitePlayerId
                      : whitePlayer?.id,
            ),
            chessPlayersByFideId,
          );

          final blackCard = enrichPlayerCardFromChessPlayers(
            PlayerCard(
              name: blackName.isNotEmpty ? blackName : 'Black',
              federation: blackFed,
              title: blackTitle,
              rating: blackElo,
              countryCode: blackFed,
              team: null,
              fideId: blackFideId,
              gamebasePlayerId:
                  (blackPlayerId != null && blackPlayerId.isNotEmpty)
                      ? blackPlayerId
                      : blackPlayer?.id,
            ),
            chessPlayersByFideId,
          );

          final formatCode =
              (eco.trim().isNotEmpty) ? eco.trim() : (timeControl ?? '');

          final tourId = (preview['tour_id']?.toString() ??
                  preview['tournament_id']?.toString() ??
                  event.trim())
              .trim();

          return GamesTourModel(
            gameId: safeId,
            source: GameSource.gamebase,
            whitePlayer: whiteCard,
            blackPlayer: blackCard,
            whiteTimeDisplay: '--:--',
            blackTimeDisplay: '--:--',
            whiteClockCentiseconds: 0,
            blackClockCentiseconds: 0,
            gameStatus: GameStatus.fromString(resultStr),
            roundId: 'gamebase_search',
            roundSlug: formatCode.isNotEmpty ? formatCode : null,
            tourId: tourId.isNotEmpty ? tourId : 'Gamebase',
            timeControl: timeControl,
            isOnline: preview['isOnline'] == true,
            lastMove: rowLastMove,
            fen: rowFen,
            pgn: pgn,
            lastMoveTime: date,
            eco: eco.trim().isNotEmpty ? eco.trim() : null,
            openingName: (preview['opening']?.toString() ?? '').trim().isNotEmpty
                ? preview['opening'].toString().trim()
                : null,
          );
        })
        .toList(growable: false);

    return _PageResult(
      games: games,
      totalCount: totalCount,
      totalCountIsEstimate: totalCountIsEstimate,
      hasMore: hasMore,
    );
  }

  String coalesceName(Map<String, dynamic> row, String keyA, String keyB) {
    final a = (row[keyA]?.toString() ?? '').trim();
    if (a.isNotEmpty) return a;
    final b = (row[keyB]?.toString() ?? '').trim();
    return b.isNotEmpty ? b : (keyA.startsWith('white') ? 'White' : 'Black');
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}

class _PageResult {
  final List<GamesTourModel> games;
  final int totalCount;
  final bool totalCountIsEstimate;
  final bool hasMore;

  const _PageResult({
    required this.games,
    required this.totalCount,
    required this.totalCountIsEstimate,
    required this.hasMore,
  });
}

/// Exact unfiltered TWIC game count from opening-root aggregates.
///
/// Search metadata count is currently estimate-only and can be far below the
/// actual gamebase size, so the TWIC landing view uses this for correctness.
final twicDatabaseTotalGamesProvider = FutureProvider<int>((ref) async {
  final repo = ref.read(gamebaseRepositoryProvider);
  final response = await repo.getMoveAggregates(
    fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  );

  return response.data.moves.fold<int>(0, (sum, move) => sum + move.total);
});

/// Provider for paginated database games with filter support
final gamebaseDatabaseGamesPaginatedProvider =
    StateNotifierProvider.autoDispose<
      DatabaseGamesPaginationNotifier,
      DatabaseGamesPaginationState
    >((ref) {
      final query = ref.watch(librarySearchQueryProvider);
      final filter = ref.watch(gamebaseFilterProvider);
      final selectedEvent = ref.watch(twicSelectedEventProvider);
      return DatabaseGamesPaginationNotifier(ref, query, filter, selectedEvent);
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
    late final List<Map<String, dynamic>> rawRows;
    if (shouldUseExactLibraryGameQuery(query, filter)) {
      final where = _buildLibraryExactWhere(filter);
      final response = await repo.queryResource(
        body: {
          'resource': 'game',
          'pageNumber': 1,
          'pageSize': 50,
          'includeTotal': true,
          'countMode': 'auto',
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'select': _libraryExactGameSelectColumns(),
          if (where != null) 'where': where,
        },
      );
      rawRows = response.data;
    } else {
      String finalQuery = query.trim().isEmpty ? '*' : query.trim();
      if (!filter.eco.isAll) {
        finalQuery = 'eco:${filter.eco.code} $finalQuery';
      }

      final response = await repo.globalSearch(
        query: finalQuery,
        resources: const ['game'],
        pageNumber: 1,
        pageSize: 50,
        result: filter.resultApiValue,
        color: filter.colorApiValue,
        timeControl: filter.timeControlApiValue,
        isOnline: filter.isOnlineApiValue,
        yearFrom: filter.minYear != GameFilter.absoluteMinYear ? filter.minYear : null,
        yearTo: filter.maxYear != DateTime.now().year ? filter.maxYear : null,
        ratingFrom: filter.minRating > GameFilter.absoluteMinRating ? filter.minRating : null,
        ratingTo: filter.maxRating < GameFilter.absoluteMaxRating ? filter.maxRating : null,
      );
      rawRows = _rowsFromGlobalSearchResponse(response);
    }

    if (rawRows.isEmpty) {
      return const <GamesTourModel>[];
    }

    // Collect player IDs for enrichment
    final playerIds = <String>{};
    for (final preview in rawRows) {
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

    final playerFideIds = <int>{};
    for (final row in rawRows) {
      final whiteFideId = parseFideIdFromRaw(row['whiteFideId']);
      final blackFideId = parseFideIdFromRaw(row['blackFideId']);
      if (whiteFideId != null) playerFideIds.add(whiteFideId);
      if (blackFideId != null) playerFideIds.add(blackFideId);
    }
    for (final p in playerDetails.values) {
      final fideId = int.tryParse(p.fideId);
      if (fideId != null && fideId > 0) {
        playerFideIds.add(fideId);
      }
    }
    final chessPlayersByFideId =
        playerFideIds.isEmpty
            ? const <int, ChessPlayer>{}
            : await ref
                .read(chessPlayerRepositoryProvider)
                .getPlayersByFideIds(playerFideIds);

    return rawRows
        .map((row) {
          final id = (row['id']?.toString() ?? '').trim();
          final safeId = id.isNotEmpty ? id : 'unknown';
          final timeControl = row['timeControl']?.toString();
          final date = parseDate(row['date']);
          final resultStr = row['result']?.toString() ?? '*';

          final whiteName = coalesceName(row, 'white', 'whiteName');
          final blackName = coalesceName(row, 'black', 'blackName');

          final whitePlayerId = row['whitePlayerId']?.toString().trim();
          final blackPlayerId = row['blackPlayerId']?.toString().trim();
          final whitePlayer =
              (whitePlayerId != null) ? playerDetails[whitePlayerId] : null;
          final blackPlayer =
              (blackPlayerId != null) ? playerDetails[blackPlayerId] : null;

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
          final rowFen =
              row['fen']?.toString() ??
              row['finalFen']?.toString() ??
              row['positionFen']?.toString();
          final rowLastMove = row['lastMove']?.toString();
          final whiteFideId =
              parseFideIdFromRaw(row['whiteFideId']) ??
              int.tryParse(whitePlayer?.fideId ?? '');
          final blackFideId =
              parseFideIdFromRaw(row['blackFideId']) ??
              int.tryParse(blackPlayer?.fideId ?? '');
          final whiteEloFromRow = (row['whiteElo'] as num?)?.toInt() ?? 0;
          final blackEloFromRow = (row['blackElo'] as num?)?.toInt() ?? 0;
          final whiteFed =
              (row['whiteFed']?.toString().trim().isNotEmpty ?? false)
                  ? row['whiteFed'].toString().trim()
                  : (whitePlayer?.fed ?? '');
          final blackFed =
              (row['blackFed']?.toString().trim().isNotEmpty ?? false)
                  ? row['blackFed'].toString().trim()
                  : (blackPlayer?.fed ?? '');

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
            fen: rowFen,
          );

          final whiteCard = enrichPlayerCardFromChessPlayers(
            PlayerCard(
              name: whiteName,
              federation: whiteFed,
              title: whiteTitle,
              rating:
                  whiteEloFromRow > 0
                      ? whiteEloFromRow
                      : ratingFor(whitePlayer, timeControl),
              countryCode: whiteFed,
              team: null,
              fideId: whiteFideId,
              gamebasePlayerId:
                  (whitePlayerId != null && whitePlayerId.isNotEmpty)
                      ? whitePlayerId
                      : whitePlayer?.id,
            ),
            chessPlayersByFideId,
          );

          final blackCard = enrichPlayerCardFromChessPlayers(
            PlayerCard(
              name: blackName,
              federation: blackFed,
              title: blackTitle,
              rating:
                  blackEloFromRow > 0
                      ? blackEloFromRow
                      : ratingFor(blackPlayer, timeControl),
              countryCode: blackFed,
              team: null,
              fideId: blackFideId,
              gamebasePlayerId:
                  (blackPlayerId != null && blackPlayerId.isNotEmpty)
                      ? blackPlayerId
                      : blackPlayer?.id,
            ),
            chessPlayersByFideId,
          );

          final formatCode =
              (eco.trim().isNotEmpty) ? eco.trim() : (timeControl ?? '');

          final tourId = (row['tour_id']?.toString() ??
                  row['tournament_id']?.toString() ??
                  event.trim())
              .trim();

          return GamesTourModel(
            gameId: safeId,
            source: GameSource.gamebase,
            whitePlayer: whiteCard,
            blackPlayer: blackCard,
            whiteTimeDisplay: '--:--',
            blackTimeDisplay: '--:--',
            whiteClockCentiseconds: 0,
            blackClockCentiseconds: 0,
            gameStatus: GameStatus.fromString(resultStr),
            roundId: 'gamebase_search',
            roundSlug: formatCode.isNotEmpty ? formatCode : null,
            tourId: tourId.isNotEmpty ? tourId : 'Gamebase',
            timeControl: timeControl,
            isOnline: row['isOnline'] == true,
            lastMove: rowLastMove,
            fen: rowFen,
            pgn: pgn,
            lastMoveTime: date,
            eco: eco.trim().isNotEmpty ? eco.trim() : null,
            openingName: (row['opening']?.toString() ?? '').trim().isNotEmpty
                ? row['opening'].toString().trim()
                : null,
          );
        })
        .toList(growable: false);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[GamebaseDatabaseGames] Error: $e');
      debugPrintStack(stackTrace: st);
    }
    return const <GamesTourModel>[];
  }
});
