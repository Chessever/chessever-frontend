import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- Models ---

class LibrarySearchResult {
  final List<LibraryFolder> folders;
  final List<SavedAnalysis> analyses;
  final List<GamebasePlayer> players;
  final List<Map<String, dynamic>> games; // Gamebase games (raw rows)

  const LibrarySearchResult({
    this.folders = const [],
    this.analyses = const [],
    this.players = const [],
    this.games = const [],
  });

  bool get isEmpty =>
      folders.isEmpty && analyses.isEmpty && players.isEmpty && games.isEmpty;
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
      final gamebaseRepo = _ref.read(gamebaseRepositoryProvider);
      List<GamebasePlayer> players = [];
      List<Map<String, dynamic>> games = [];

      try {
        debugPrint('[LibrarySearch] Calling gamebaseRepo.globalSearch with query="$queryTrimmed"');
        // Use globalSearch to search across ALL SQL columns
        final searchResponse = await gamebaseRepo.globalSearch(
          query: queryTrimmed,
          pageSize: 50,
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
            players.add(GamebasePlayer(
              id: result.id,
              name: result.label,
              fideId: (preview['fideId'] as String?) ?? '',
              gender: gender,
              fed: (preview['fed'] as String?) ?? '',
              title: preview['title'] as String?,
            ));
          } else if (result.resource == 'game') {
            // Add game data from preview to games list
            final gameData = <String, dynamic>{
              'id': result.id,
              'label': result.label,
              'snippet': result.snippet,
              ...?result.preview,
            };
            games.add(gameData);
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
            pageSize: 30,
          );
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
