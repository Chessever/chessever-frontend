import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- Models ---

class LibrarySearchResult {
  final List<LibraryFolder> folders;
  final List<SavedAnalysis> analyses;
  final List<GamebasePlayer> players;
  final List<Map<String, dynamic>> games; // Gamebase games (raw rows)

  /// Pagination metadata for players
  final int playerPageNumber;
  final int playerTotalCount;
  final bool hasMorePlayers;

  /// Pagination metadata for games
  final int gamePageNumber;
  final int gameTotalCount;
  final bool hasMoreGames;

  const LibrarySearchResult({
    this.folders = const [],
    this.analyses = const [],
    this.players = const [],
    this.games = const [],
    this.playerPageNumber = 1,
    this.playerTotalCount = 0,
    this.hasMorePlayers = false,
    this.gamePageNumber = 1,
    this.gameTotalCount = 0,
    this.hasMoreGames = false,
  });

  bool get isEmpty =>
      folders.isEmpty && analyses.isEmpty && players.isEmpty && games.isEmpty;

  /// Creates a copy with additional players appended
  LibrarySearchResult appendPlayers(List<GamebasePlayer> morePlayers, {
    required int newPageNumber,
    required int totalCount,
    required bool hasMore,
  }) {
    return LibrarySearchResult(
      folders: folders,
      analyses: analyses,
      players: [...players, ...morePlayers],
      games: games,
      playerPageNumber: newPageNumber,
      playerTotalCount: totalCount,
      hasMorePlayers: hasMore,
      gamePageNumber: gamePageNumber,
      gameTotalCount: gameTotalCount,
      hasMoreGames: hasMoreGames,
    );
  }

  /// Creates a copy with additional games appended
  LibrarySearchResult appendGames(List<Map<String, dynamic>> moreGames, {
    required int newPageNumber,
    required int totalCount,
    required bool hasMore,
  }) {
    return LibrarySearchResult(
      folders: folders,
      analyses: analyses,
      players: players,
      games: [...games, ...moreGames],
      playerPageNumber: playerPageNumber,
      playerTotalCount: playerTotalCount,
      hasMorePlayers: hasMorePlayers,
      gamePageNumber: newPageNumber,
      gameTotalCount: totalCount,
      hasMoreGames: hasMore,
    );
  }
}

// --- Providers ---

final libraryAnalysesProvider = StreamProvider<List<SavedAnalysis>>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.subscribeAnalyses();
});

final libraryCombinedSearchProvider = StateNotifierProvider.autoDispose.family<
  LibraryCombinedSearchNotifier,
  AsyncValue<LibrarySearchResult>,
  String
>((ref, query) {
  return LibraryCombinedSearchNotifier(ref, query);
});

class LibraryCombinedSearchNotifier
    extends StateNotifier<AsyncValue<LibrarySearchResult>> {
  final Ref _ref;
  final String _query;
  Timer? _debounceTimer;

  /// Page size for initial dropdown search (smaller for quick results)
  static const int _dropdownPageSize = 10;

  LibraryCombinedSearchNotifier(this._ref, this._query)
    : super(const AsyncValue.loading()) {
    _search();
  }

  void _search() {
    debugPrint('[LibrarySearch] _search called with query="${_query}"');
    if (_query.trim().isEmpty) {
      debugPrint('[LibrarySearch] Query is empty, returning empty result');
      state = const AsyncValue.data(LibrarySearchResult());
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      debugPrint('[LibrarySearch] Debounce timer fired, performing search');
      await _performSearch();
    });
  }

  Future<void> _performSearch() async {
    debugPrint('[LibrarySearch] _performSearch starting for query="$_query"');
    state = const AsyncValue.loading();
    try {
      final queryLower = _query.toLowerCase().trim();
      final queryTrimmed = _query.trim();

      // 1. Local Search (Folders & Analyses)
      final foldersAsync = _ref.read(libraryFoldersStreamProvider);
      final analysesAsync = _ref.read(libraryAnalysesProvider);

      List<LibraryFolder> filteredFolders = [];
      List<SavedAnalysis> filteredAnalyses = [];

      if (foldersAsync.hasValue) {
        filteredFolders =
            foldersAsync.value!
                .where((f) => f.name.toLowerCase().contains(queryLower))
                .toList();
      }
      debugPrint('[LibrarySearch] Local folders found: ${filteredFolders.length}');

      if (analysesAsync.hasValue) {
        filteredAnalyses =
            analysesAsync.value!.where((a) {
              final titleMatch = a.title.toLowerCase().contains(queryLower);
              final white =
                  (a.chessGame.metadata['White'] as String?)?.toLowerCase() ??
                  '';
              final black =
                  (a.chessGame.metadata['Black'] as String?)?.toLowerCase() ??
                  '';
              final event =
                  (a.chessGame.metadata['Event'] as String?)?.toLowerCase() ??
                  '';
              final site =
                  (a.chessGame.metadata['Site'] as String?)?.toLowerCase() ??
                  '';
              return titleMatch ||
                  white.contains(queryLower) ||
                  black.contains(queryLower) ||
                  event.contains(queryLower) ||
                  site.contains(queryLower);
            }).toList();
      }
      debugPrint('[LibrarySearch] Local analyses found: ${filteredAnalyses.length}');

      // 2. Gamebase Global Search - queries ALL columns (players, games, events, etc.)
      // Use smaller page size for quick dropdown results
      final gamebaseRepo = _ref.read(gamebaseRepositoryProvider);
      List<GamebasePlayer> players = [];
      List<Map<String, dynamic>> games = [];
      int playerTotalCount = 0;
      int gameTotalCount = 0;
      bool hasMorePlayers = false;
      bool hasMoreGames = false;

      try {
        debugPrint('[LibrarySearch] Calling gamebaseRepo.globalSearch with query="$queryTrimmed"');
        // Use globalSearch to search across ALL SQL columns with pagination
        final searchResponse = await gamebaseRepo.globalSearch(
          query: queryTrimmed,
          pageNumber: 1,
          pageSize: _dropdownPageSize * 2, // Fetch enough for both players and games
        );
        debugPrint('[LibrarySearch] globalSearch returned ${searchResponse.results.length} results');

        // Parse results by resource type
        for (final result in searchResponse.results) {
          debugPrint('[LibrarySearch] Result: resource=${result.resource}, label=${result.label}, id=${result.id}');

          if (result.resource == 'player') {
            // Convert search result to GamebasePlayer
            final preview = result.preview ?? {};
            final genderStr = (preview['gender'] as String?)?.toUpperCase();
            final gender = genderStr == 'FEMALE' ? PlayerGender.female : PlayerGender.male;
            final normalizedTitle = ChessTitleUtils.normalize(preview['title'] as String?);
            players.add(GamebasePlayer(
              id: result.id,
              name: result.label,
              fideId: (preview['fideId'] as String?) ?? '',
              gender: gender,
              fed: (preview['fed'] as String?) ?? '',
              title: normalizedTitle,
              ratingClassical: (preview['ratingClassical'] as num?)?.toInt(),
              ratingRapid: (preview['ratingRapid'] as num?)?.toInt(),
              ratingBlitz: (preview['ratingBlitz'] as num?)?.toInt(),
            ));
          } else if (result.resource == 'game') {
            // Add game data from preview to games list
            // IMPORTANT: Use preview's 'id' (actual game UUID) not result.id (search result ID)
            final preview = result.preview ?? <String, dynamic>{};
            final gameUuid = preview['id']?.toString() ?? result.id;
            final gameData = <String, dynamic>{
              'label': result.label,
              'snippet': result.snippet,
              ...preview,
              'id': gameUuid, // Ensure correct game UUID is used for API calls
            };
            games.add(gameData);
          }
        }

        // Calculate pagination info from metadata
        final totalCount = searchResponse.metadata.totalCount ?? 0;
        // Estimate player/game counts (API doesn't separate them)
        playerTotalCount = players.length;
        gameTotalCount = games.length;
        hasMorePlayers = searchResponse.metadata.hasMore && players.isNotEmpty;
        hasMoreGames = searchResponse.metadata.hasMore && games.isNotEmpty;

        // Enrich game preview rows with player details (titles/ratings/federations).
        // This keeps the UI informative even when full game PGN isn't available.
        final idsToFetch = <String>{};
        for (final row in games) {
          final w = row['whitePlayerId']?.toString().trim();
          final b = row['blackPlayerId']?.toString().trim();
          if (w != null && w.isNotEmpty) idsToFetch.add(w);
          if (b != null && b.isNotEmpty) idsToFetch.add(b);
        }

        int ratingFor(GamebasePlayer p, String? timeControl) {
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

        if (idsToFetch.isNotEmpty) {
          final fetched = await Future.wait(
            idsToFetch.map(gamebaseRepo.getPlayerById),
            eagerError: false,
          );
          final byId = <String, GamebasePlayer>{
            for (final p in fetched.whereType<GamebasePlayer>())
              p.id: GamebasePlayer(
                id: p.id,
                fideId: p.fideId,
                name: p.name,
                gender: p.gender,
                fed: p.fed,
                title: ChessTitleUtils.normalize(p.title),
                ratingClassical: p.ratingClassical,
                ratingRapid: p.ratingRapid,
                ratingBlitz: p.ratingBlitz,
              ),
          };

          for (final row in games) {
            final tc = row['timeControl']?.toString();
            final wId = row['whitePlayerId']?.toString().trim();
            final bId = row['blackPlayerId']?.toString().trim();

            final w = (wId != null) ? byId[wId] : null;
            final b = (bId != null) ? byId[bId] : null;

            if (w != null) {
              row['white_player'] = {
                'id': w.id,
                'name': w.displayName,
                'fed': w.fed,
                'title': w.title,
              };
              row['whiteTitle'] = w.title ?? '';
              row['whiteRating'] = ratingFor(w, tc);
              row['whiteFed'] = w.fed;
            }

            if (b != null) {
              row['black_player'] = {
                'id': b.id,
                'name': b.displayName,
                'fed': b.fed,
                'title': b.title,
              };
              row['blackTitle'] = b.title ?? '';
              row['blackRating'] = ratingFor(b, tc);
              row['blackFed'] = b.fed;
            }
          }
        }

        debugPrint('[LibrarySearch] Parsed ${players.length} players, ${games.length} games');
      } catch (e) {
        debugPrint('[LibrarySearch] globalSearch failed: $e');
        // Fallback to player-only search if globalSearch fails
        try {
          debugPrint('[LibrarySearch] Falling back to getPlayers');
          players = await gamebaseRepo.getPlayers(
            name: queryTrimmed,
            pageNumber: 0,
            pageSize: _dropdownPageSize,
          );
          playerTotalCount = players.length;
          hasMorePlayers = players.length >= _dropdownPageSize;
          debugPrint('[LibrarySearch] getPlayers fallback returned ${players.length} players');
        } catch (e2) {
          debugPrint('[LibrarySearch] getPlayers fallback also failed: $e2');
        }
      }

      debugPrint('[LibrarySearch] Final results - players: ${players.length}, games: ${games.length}');

      if (!mounted) return;

      state = AsyncValue.data(
        LibrarySearchResult(
          folders: filteredFolders,
          analyses: filteredAnalyses,
          players: players,
          games: games,
          playerPageNumber: 1,
          playerTotalCount: playerTotalCount,
          hasMorePlayers: hasMorePlayers,
          gamePageNumber: 1,
          gameTotalCount: gameTotalCount,
          hasMoreGames: hasMoreGames,
        ),
      );
      debugPrint('[LibrarySearch] State updated with results');
    } catch (e, st) {
      debugPrint('[LibrarySearch] _performSearch ERROR: $e');
      state = AsyncValue.error(e, st);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
