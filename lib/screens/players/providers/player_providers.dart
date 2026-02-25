import 'dart:async';

import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/pending_favorite_players_provider.dart';
import 'package:chessever2/screens/players/view_models/player_view_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final favoritePlayersProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final playersState = ref.watch(playerPaginationProvider);
  return playersState.maybeWhen(
    data: (players) => players.where((p) => p['isFavorite'] == true).toList(),
    orElse: () => [],
  );
});
final playerViewModelProvider = Provider<PlayerViewModel>((ref) {
  return PlayerViewModel();
});

final playerInitializationProvider = FutureProvider<void>((ref) async {
  final paginationNotifier = ref.read(playerPaginationProvider.notifier);
  await paginationNotifier.initFirstPage();
});

final playerSearchQueryProvider = StateProvider<String>((ref) => '');

final playerPaginationProvider = StateNotifierProvider<
  PlayerPaginationNotifier,
  AsyncValue<List<Map<String, dynamic>>>
>((ref) {
  final viewModel = ref.read(playerViewModelProvider);
  return PlayerPaginationNotifier(viewModel, ref);
});

/// Provider specifically for onboarding - uses optimized fetch
final onboardingPlayerProvider = StateNotifierProvider<
  PlayerPaginationNotifier,
  AsyncValue<List<Map<String, dynamic>>>
>((ref) {
  final viewModel = ref.read(playerViewModelProvider);
  return PlayerPaginationNotifier(viewModel, ref, isOnboarding: true);
});

final filteredPlayersProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(playerPaginationProvider).valueOrNull ?? [];
});

class PlayerPaginationNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final PlayerViewModel _viewModel;
  final Ref _ref;
  final bool _isOnboarding;
  bool _isFetching = false;
  bool hasMore = true;
  String _search = '';
  String? _countryCode;
  int _searchVersion = 0;

  /// Expose fetching state for UI loading indicators
  bool get isFetching => _isFetching;

  PlayerPaginationNotifier(
    this._viewModel,
    this._ref, {
    bool isOnboarding = false,
  }) : _isOnboarding = isOnboarding,
       super(const AsyncValue.loading());

  Future<void> initFirstPage() async {
    final currentVersion = ++_searchVersion;
    _isFetching = true;
    state = const AsyncValue.loading();
    try {
      await _viewModel.initialize(clear: true, isOnboarding: _isOnboarding);

      // Check if a newer search was started while we were initializing
      if (currentVersion != _searchVersion) return;

      final country = _search.isEmpty ? _countryCode : null;
      final firstBatch = await _viewModel.fetchNextPage(
        search: _search,
        countryCode: country,
      );

      // Check again if a newer search was started
      if (currentVersion != _searchVersion) return;

      final enriched = _mergeWithFavorites(_filterRealPlayers(firstBatch));
      state = AsyncValue.data(enriched);
      hasMore = enriched.isNotEmpty;
    } catch (e) {
      // Only set error if this is still the current search
      if (currentVersion == _searchVersion) {
        state = AsyncValue.error(e, StackTrace.current);
      }
    } finally {
      if (currentVersion == _searchVersion) {
        _isFetching = false;
      }
    }
  }

  Future<void> fetchNextPage() async {
    if (_isFetching || !hasMore) return;
    _isFetching = true;

    try {
      final newBatch = await _viewModel.fetchNextPage(
        search: _search,
        // For onboarding: fetch global players (more heterogeneous mix)
        // For regular: filter by country if set
        countryCode:
            _isOnboarding ? null : (_search.isEmpty ? _countryCode : null),
      );
      final filtered = _filterRealPlayers(newBatch);
      final enriched = _mergeWithFavorites(filtered);
      if (enriched.isEmpty) {
        hasMore = false;
      } else {
        state = state.whenData((players) => [...players, ...enriched]);
      }
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    } finally {
      _isFetching = false;
    }
  }

  Future<void> toggleFavorite(String fideId) async {
    final currentPlayers = state.valueOrNull ?? [];
    final idx = currentPlayers.indexWhere(
      (p) => p['fideId'].toString() == fideId,
    );
    if (idx == -1) return;

    final player = currentPlayers[idx];
    final toggled = !(player['isFavorite'] ?? false);

    // Optimistic UI update
    state = AsyncValue.data([
      ...currentPlayers.take(idx),
      {...player, 'isFavorite': toggled},
      ...currentPlayers.skip(idx + 1),
    ]);

    // Keep local cache consistent
    unawaited(_viewModel.updateFavoriteFlag(fideId, toggled));

    final supabaseUser = Supabase.instance.client.auth.currentUser;
    final isAuthenticated =
        supabaseUser != null && supabaseUser.isAnonymous != true;

    if (!isAuthenticated) {
      _ref
          .read(pendingFavoriteSelectionsProvider.notifier)
          .setSelection(
            PendingFavoritePlayer(
              fideId: fideId,
              playerName: player['name']?.toString() ?? '',
              countryCode: player['fed']?.toString(),
              rating: player['rating'] as int?,
              title: player['title']?.toString(),
              isSelected: toggled,
            ),
          );
      return;
    }

    // Fire Supabase toggle in background
    unawaited(
      _ref
          .read(favoritePlayersProviderNew.notifier)
          .toggleFavorite(
            fideId: fideId,
            playerName: player['name']?.toString() ?? '',
            countryCode: player['fed']?.toString(),
            rating: player['rating'] as int?,
            title: player['title']?.toString(),
          ),
    );
  }

  Future<void> setSearchQuery(String query) async {
    _search = query;
    await _resetAndFetch();
  }

  Future<void> setCountry(String? countryCode) async {
    final normalized = countryCode?.toUpperCase();
    if (_countryCode == normalized) return;
    _countryCode = normalized;
    if (_search.isEmpty) {
      await _resetAndFetch();
    }
  }

  Future<void> _resetAndFetch() async {
    hasMore = true;
    await initFirstPage();
  }

  List<Map<String, dynamic>> _filterRealPlayers(
    List<Map<String, dynamic>> players,
  ) {
    return players.where((player) {
      final name = (player['name'] ?? '').toString().toUpperCase();
      final rating = (player['rating'] ?? 0) as int? ?? 0;
      final isBot = name.contains('BOT') || name.contains('STOCKFISH');
      final isCrazyRating = rating >= 3300 || rating <= 0;
      return !isBot && !isCrazyRating;
    }).toList();
  }

  List<Map<String, dynamic>> _mergeWithFavorites(
    List<Map<String, dynamic>> players,
  ) {
    final favorites = _ref.read(favoritePlayersProviderNew).valueOrNull ?? [];
    final pendingFavorites = _ref.read(pendingFavoriteSelectionsProvider);
    final favoriteNames =
        favorites.map((f) => f.playerName.toLowerCase()).toSet();
    final favoriteFideIds =
        favorites.map((f) => f.fideId?.toLowerCase() ?? '').toSet();
    final pendingFideIds =
        pendingFavorites.values
            .where((p) => p.isSelected)
            .map((p) => p.fideId.toLowerCase())
            .toSet();

    return players.map((player) {
      final name = (player['name'] ?? '').toString().toLowerCase();
      final fideId = player['fideId']?.toString().toLowerCase() ?? '';
      final isFav =
          favoriteNames.contains(name) ||
          (fideId.isNotEmpty &&
              (favoriteFideIds.contains(fideId) ||
                  pendingFideIds.contains(fideId)));
      return {...player, 'isFavorite': isFav};
    }).toList();
  }
}

final filteredFavoritePlayersProvider = Provider<List<Map<String, dynamic>>>((
  ref,
) {
  final searchQuery = ref.watch(playerSearchQueryProvider);
  final favoritePlayers = ref.watch(favoritePlayersProvider);

  if (searchQuery.isEmpty) return favoritePlayers;

  final lowercaseQuery = searchQuery.toLowerCase();
  return favoritePlayers.where((player) {
    return player['name'].toString().toLowerCase().contains(lowercaseQuery);
  }).toList();
});
