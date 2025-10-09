import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum GamesTourScreenMode { normal, groupEvent }

final gamesTourScreenModeProvider = StateNotifierProvider((ref) {
  // Watch tour details first - this is the primary dependency
  final tourDetailAsync = ref.watch(tourDetailScreenProvider);
  final showFinishedGames = ref.watch(showFinishedGamesProvider);

  if (tourDetailAsync.isLoading) {
    return _GamesTourScreenModeNotifier.loading(ref);
  }

  if (tourDetailAsync.hasError) {
    return _GamesTourScreenModeNotifier.error(ref);
  }

  final aboutTourModel = tourDetailAsync.valueOrNull?.aboutTourModel;

  if (aboutTourModel == null) {
    return _GamesTourScreenModeNotifier.loading(ref);
  }

  // The notifier will read games/pins itself and keep state in sync
  return _GamesTourScreenModeNotifier(ref);
});

class _GamesTourScreenModeNotifier
    extends StateNotifier<AsyncValue<GamesTourScreenMode>> {
  _GamesTourScreenModeNotifier(this.ref) : super(AsyncValue.loading()) {
    _init();
  }

  _GamesTourScreenModeNotifier.loading(this.ref) : super(AsyncValue.loading());

  _GamesTourScreenModeNotifier.error(this.ref) : super(AsyncValue.loading());

  final Ref ref;

  bool _isGroupEvent(List<Games> games) {
    if (games.isEmpty) return false;

    final Map<String, List<Games>> gamesByRound = {};
    for (var g in games) {
      gamesByRound.putIfAbsent(g.roundId, () => []).add(g);
    }

    for (final roundEntry in gamesByRound.entries) {
      final roundGames = roundEntry.value;

      // Within each round, we may have multiple matches like USA_vs_UZB, CHN_vs_ARM
      final Set<String> matchKeys = {};

      for (final game in roundGames) {
        final white = game.players?[0];
        final black = game.players?[1];
        if (white == null || black == null) return false;
        if (white.fed.isEmpty || black.fed.isEmpty) return false;

        // Use a unique key for each country pairing
        final key = '${white.fed}_vs_${black.fed}';
        matchKeys.add(key);
      }

      if (matchKeys.length > 1) {
        return true; // ✅ Multiple country-vs-country matchups → group event
      }
    }

    return false;
  }

  Future<void> _init() async {
    final tourDetail = ref.read(tourDetailScreenProvider);
    late final ProviderSubscription<AsyncValue<List<Games>>> subscription;
    subscription = ref.listen<AsyncValue<List<Games>>>(
      gamesTourProvider(tourDetail.value!.aboutTourModel.id),
      (previous, next) {
        if (next is AsyncData<List<Games>>) {
          // ✅ Stop listening after first data
          subscription.close();
          final games = next.value;

          final isGroupEvent = _isGroupEvent(games);
          state = AsyncValue.data(
            isGroupEvent
                ? GamesTourScreenMode.groupEvent
                : GamesTourScreenMode.normal,
          );
        }
      },
    );
  }
}
