import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_auto_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesPinState {
  final List<String> manualPins;
  final List<String> autoPins;
  final bool autoPinDisabled;

  const GamesPinState({
    this.manualPins = const [],
    this.autoPins = const [],
    this.autoPinDisabled = false,
  });

  List<String> get allPins {
    final seen = <String>{};
    final ordered = <String>[];

    for (final id in manualPins) {
      if (seen.add(id)) ordered.add(id);
    }

    for (final id in autoPins) {
      if (seen.add(id)) ordered.add(id);
    }

    return ordered;
  }

  GamesPinState copyWith({
    List<String>? manualPins,
    List<String>? autoPins,
    bool? autoPinDisabled,
  }) {
    return GamesPinState(
      manualPins: manualPins ?? this.manualPins,
      autoPins: autoPins ?? this.autoPins,
      autoPinDisabled: autoPinDisabled ?? this.autoPinDisabled,
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
    _listenToFavoritePlayers();
    _listenToKnockoutStages();
    _listenToCountrySelection();
    _listenToPrimaryGames();
  }

  final Ref ref;
  final String tourId;
  final Set<String> _stageListeners = <String>{};

  void _listenToFavoritePlayers() {
    // Listen to favorite players changes and recompute auto-pins
    ref.listen<AsyncValue<List<PlayerStandingModel>>>(
      tournamentFavoritePlayersProvider,
      (previous, next) {
        next.whenData((players) {
          // Recompute auto-pins when favorite players change
          computeAutoPins();
        });
      },
    );
  }

  void _listenToKnockoutStages() {
    ref.listen(tourDetailScreenProvider, (previous, next) {
      final detail = next.valueOrNull;
      if (detail == null) {
        return;
      }

      if (detail.tours.isEmpty) {
        return;
      }

      // Find the current tour to determine its group broadcast
      var matchingTour = detail.tours.first;
      for (final tourModel in detail.tours) {
        if (tourModel.tour.id == tourId) {
          matchingTour = tourModel;
          break;
        }
      }

      final groupBroadcastId = matchingTour.tour.groupBroadcastId;
      if (groupBroadcastId == null || groupBroadcastId.isEmpty) {
        return;
      }

      final relatedStageIds = detail.tours
          .where(
            (tourModel) => tourModel.tour.groupBroadcastId == groupBroadcastId,
          )
          .map((tourModel) => tourModel.tour.id);

      for (final stageId in relatedStageIds) {
        // Avoid wiring duplicate listeners
        if (_stageListeners.contains(stageId)) continue;
        _stageListeners.add(stageId);

        ref.listen<KnockoutTournamentState>(
          knockoutTournamentStateProvider(stageId),
          (prevState, nextState) {
            final previousGames =
                prevState?.allGames ?? const <GamesTourModel>[];
            final nextGames = nextState.allGames;

            if (_didGameListChange(previousGames, nextGames)) {
              computeAutoPins();
            }
          },
          fireImmediately: true,
        );
      }
    }, fireImmediately: true);
  }

  void _listenToPrimaryGames() {
    ref.listen<AsyncValue<List<Games>>>(gamesTourProvider(tourId), (
      previous,
      next,
    ) {
      if (!next.hasValue) {
        return;
      }

      final nextGames = next.value ?? const <Games>[];
      if (nextGames.isEmpty) {
        return;
      }

      final previousGames = previous?.valueOrNull;
      if (previousGames != null &&
          !_didRawGamesChange(previousGames, nextGames)) {
        return;
      }

      computeAutoPins();
    }, fireImmediately: true);
  }

  void _listenToCountrySelection() {
    ref.listen(countryDropdownProvider, (previous, next) {
      final previousCode = previous?.valueOrNull?.countryCode;
      final nextCode = next.valueOrNull?.countryCode;

      if (nextCode == null) {
        return;
      }

      if (previousCode == nextCode) {
        return;
      }

      computeAutoPins();
    });
  }

  bool _didGameListChange(
    List<GamesTourModel> previous,
    List<GamesTourModel> next,
  ) {
    if (previous.length != next.length) {
      return true;
    }

    final previousIds = previous.map((game) => game.gameId).toSet();
    final nextIds = next.map((game) => game.gameId).toSet();
    return !setEquals(previousIds, nextIds);
  }

  bool _didRawGamesChange(List<Games> previous, List<Games> next) {
    if (previous.length != next.length) {
      return true;
    }

    final previousIds = previous.map((game) => game.id).toSet();
    final nextIds = next.map((game) => game.id).toSet();
    return !setEquals(previousIds, nextIds);
  }

  Future<void> loadPinnedGames() async {
    final manualPins = await ref
        .read(pinGameLocalStorage)
        .getPinnedGameIds(tourId);
    final autoPinnedGames = await ref
        .read(autoPinLogicProvider)
        .getAutoPinnedGames(tourId);

    state = state.copyWith(
      manualPins: manualPins,
      autoPins: autoPinnedGames.$2,
      autoPinDisabled: autoPinnedGames.$1,
    );
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

  Future<void> enableAutoPin() async {
    await ref.read(autoPinLogicProvider).enableAutoPin(tourId);
    await computeAutoPins();
  }

  Future<void> disableAutoPin() async {
    await ref.read(autoPinLogicProvider).disableAutoPin(tourId);
    await computeAutoPins();
  }

  Future<void> computeAutoPins() async {
    final autoPinnedGames = await ref
        .read(autoPinLogicProvider)
        .getAutoPinnedGames(tourId);
    state = state.copyWith(
      autoPins: autoPinnedGames.$2,
      autoPinDisabled: autoPinnedGames.$1,
    );
  }
}
