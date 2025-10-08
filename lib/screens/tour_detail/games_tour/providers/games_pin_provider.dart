import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_auto_pin_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesPinState {
  final List<String> manualPins;
  final List<String> autoPins;

  const GamesPinState({this.manualPins = const [], this.autoPins = const []});

  List<String> get allPins => {...manualPins, ...autoPins}.toList();

  GamesPinState copyWith({List<String>? manualPins, List<String>? autoPins}) {
    return GamesPinState(
      manualPins: manualPins ?? this.manualPins,
      autoPins: autoPins ?? this.autoPins,
    );
  }
}

final gamesPinprovider =
    StateNotifierProvider.family<_GamesPinController, GamesPinState, String>((
      ref,
      tourId,
    ) {
      return _GamesPinController(ref: ref, tourId: tourId);
    });

class _GamesPinController extends StateNotifier<GamesPinState> {
  _GamesPinController({required this.ref, required this.tourId})
    : super(GamesPinState()) {
    loadPinnedGames();
  }

  final Ref ref;
  final String tourId;

  Future<void> loadPinnedGames() async {
    final manualPins = await ref
        .read(pinGameLocalStorage)
        .getPinnedGameIds(tourId);
    final autoPinnedGames =
        await ref.read(autoPinLogicProvider).getAutoPinnedGames();

    state = state.copyWith(manualPins: manualPins, autoPins: autoPinnedGames);
  }

  Future<void> togglePin(String gameId) async {
    try {
      final storage = ref.read(pinGameLocalStorage);

      if (state.manualPins.contains(gameId) ||
          state.autoPins.contains(gameId)) {
        await storage.removePinnedGameId(tourId, gameId);
        final autoPins = state.autoPins;
        autoPins.removeWhere((id) => id == gameId);

        state = state.copyWith(
          manualPins: state.manualPins.where((id) => id != gameId).toList(),
          autoPins: autoPins,
        );
      } else {
        await storage.addPinnedGameId(tourId, gameId);
        final autoPins = state.autoPins;
        autoPins.add(gameId);
        state = state.copyWith(
          manualPins: [...state.manualPins, gameId],
          autoPins: autoPins,
        );
      }
    } catch (e, _) {}
  }

  Future<void> computeAutoPins() async {
    final autoPinnedGames =
        await ref.read(autoPinLogicProvider).getAutoPinnedGames();
    state = state.copyWith(autoPins: autoPinnedGames);
  }
}
