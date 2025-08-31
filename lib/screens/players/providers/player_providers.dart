import 'package:chessever2/screens/players/view_models/player_view_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';



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
  return PlayerPaginationNotifier(viewModel);
});

final filteredPlayersProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final searchQuery = ref.watch(playerSearchQueryProvider);
  final playersState = ref.watch(playerPaginationProvider);

  return playersState.when(
    loading: () => [],
    error: (_, __) => [],
    data: (players) {
      if (searchQuery.isEmpty) return players;
      final lowercaseQuery = searchQuery.toLowerCase();
      return players.where((player) {
        return player['name'].toString().toLowerCase().contains(lowercaseQuery);
      }).toList();
    },
  );
});

class PlayerPaginationNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final PlayerViewModel _viewModel;
  bool _isFetching = false;
  bool hasMore = true;

  PlayerPaginationNotifier(this._viewModel) : super(const AsyncValue.loading());

  Future<void> initFirstPage() async {
    if (_isFetching) return;
    _isFetching = true;
    state = const AsyncValue.loading();
    try {
      await _viewModel.initialize(clear: true);
      final firstBatch = await _viewModel.fetchNextPage();
      state = AsyncValue.data(firstBatch);
      hasMore = firstBatch.isNotEmpty;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    } finally {
      _isFetching = false;
    }
  }

  Future<void> fetchNextPage() async {
    if (_isFetching || !hasMore) return;
    _isFetching = true;

    try {
      final newBatch = await _viewModel.fetchNextPage();
      if (newBatch.isEmpty) {
        hasMore = false;
      } else {
        state = state.whenData((players) => [...players, ...newBatch]);
      }
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    } finally {
      _isFetching = false;
    }
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
