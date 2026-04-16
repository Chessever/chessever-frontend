import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
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
  final List<String> unpinnedOverrides;
  final bool autoPinDisabled;

  const GamesPinState({
    this.manualPins = const [],
    this.autoPins = const [],
    this.unpinnedOverrides = const [],
    this.autoPinDisabled = false,
  });

  List<String> get allPins {
    return mergeEffectivePins(
      manualPins: manualPins,
      autoPins: autoPins,
      unpinnedOverrides: unpinnedOverrides,
    );
  }

  GamesPinState copyWith({
    List<String>? manualPins,
    List<String>? autoPins,
    List<String>? unpinnedOverrides,
    bool? autoPinDisabled,
  }) {
    return GamesPinState(
      manualPins: manualPins ?? this.manualPins,
      autoPins: autoPins ?? this.autoPins,
      unpinnedOverrides: unpinnedOverrides ?? this.unpinnedOverrides,
      autoPinDisabled: autoPinDisabled ?? this.autoPinDisabled,
    );
  }
}

enum PinToggleMode { unpinManualOnly, unpinWithOverride, repin }

List<String> mergePinListsPreservingOrder(List<List<String>> pinLists) {
  final mergedPins = <String>[];
  final seen = <String>{};

  for (final pinIds in pinLists) {
    for (final pinId in pinIds) {
      if (seen.add(pinId)) {
        mergedPins.add(pinId);
      }
    }
  }

  return mergedPins;
}

List<String> mergeEffectivePins({
  required List<String> manualPins,
  required List<String> autoPins,
  required List<String> unpinnedOverrides,
}) {
  final overrideSet = unpinnedOverrides.toSet();
  return mergePinListsPreservingOrder([
    manualPins,
    autoPins,
  ]).where((gameId) => !overrideSet.contains(gameId)).toList(growable: false);
}

PinToggleMode resolvePinToggleMode({
  required bool isManualPinned,
  required bool isAutoPinned,
  required bool isOverridden,
}) {
  if (isOverridden) {
    return PinToggleMode.repin;
  }

  if (isManualPinned && !isAutoPinned) {
    return PinToggleMode.unpinManualOnly;
  }

  if (isManualPinned || isAutoPinned) {
    return PinToggleMode.unpinWithOverride;
  }

  return PinToggleMode.repin;
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
    _listenToAutoPinPreferences();
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

  void _listenToAutoPinPreferences() {
    ref.listen<AsyncValue<AutoPinPreferences>>(autoPinPreferencesProvider, (
      previous,
      next,
    ) {
      final prev = previous?.valueOrNull;
      final curr = next.valueOrNull;
      if (curr == null) return;
      if (prev?.favoritePlayersAutoPinEnabled !=
              curr.favoritePlayersAutoPinEnabled ||
          prev?.countrymenAutoPinEnabled != curr.countrymenAutoPinEnabled) {
        computeAutoPins();
      }
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
    final storage = ref.read(pinGameLocalStorage);
    final relatedTourIds = _getRelatedTourIds();
    final pinResults = await Future.wait<Object?>([
      Future.wait(
        relatedTourIds.map(
          (relatedTourId) => storage.getPinnedGameIds(relatedTourId),
        ),
      ),
      Future.wait(
        relatedTourIds.map(
          (relatedTourId) => storage.getUnpinnedGameIds(relatedTourId),
        ),
      ),
      ref.read(autoPinLogicProvider).getAutoPinnedGames(tourId),
    ]);

    final manualPinLists = pinResults[0]! as List<List<String>>;
    final unpinnedOverrideLists = pinResults[1]! as List<List<String>>;
    final autoPinnedGames = pinResults[2]! as (bool, List<String>);

    state = state.copyWith(
      manualPins: mergePinListsPreservingOrder(manualPinLists),
      autoPins: autoPinnedGames.$2,
      unpinnedOverrides: mergePinListsPreservingOrder(unpinnedOverrideLists),
      autoPinDisabled: autoPinnedGames.$1,
    );
  }

  Future<void> togglePin({
    required String gameId,
    required String sourceTourId,
  }) async {
    try {
      final storage = ref.read(pinGameLocalStorage);
      final mode = resolvePinToggleMode(
        isManualPinned: state.manualPins.contains(gameId),
        isAutoPinned: state.autoPins.contains(gameId),
        isOverridden: state.unpinnedOverrides.contains(gameId),
      );

      switch (mode) {
        case PinToggleMode.unpinManualOnly:
          await storage.removePinnedGameId(sourceTourId, gameId);
          break;
        case PinToggleMode.unpinWithOverride:
          await Future.wait([
            storage.removePinnedGameId(sourceTourId, gameId),
            storage.addUnpinnedGameId(sourceTourId, gameId),
          ]);
          break;
        case PinToggleMode.repin:
          await Future.wait([
            storage.removeUnpinnedGameId(sourceTourId, gameId),
            storage.addPinnedGameId(sourceTourId, gameId),
          ]);
          break;
      }

      await loadPinnedGames();
    } catch (e, _) {
      debugPrint('Failed to toggle pin for $gameId in $sourceTourId: $e');
    }
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
    await loadPinnedGames();
  }

  List<String> _getRelatedTourIds() {
    final detail = ref.read(tourDetailScreenProvider).valueOrNull;
    if (detail == null || detail.tours.isEmpty) {
      return [tourId];
    }

    final matchingTour =
        detail.tours
            .firstWhere(
              (tourModel) => tourModel.tour.id == tourId,
              orElse: () => detail.tours.first,
            )
            .tour;

    final groupBroadcastId = matchingTour.groupBroadcastId;
    if (groupBroadcastId == null || groupBroadcastId.isEmpty) {
      return [tourId];
    }

    final relatedIds = <String>[tourId];
    for (final tourModel in detail.tours) {
      final relatedTourId = tourModel.tour.id;
      if (relatedTourId == tourId) {
        continue;
      }
      if (tourModel.tour.groupBroadcastId == groupBroadcastId) {
        relatedIds.add(relatedTourId);
      }
    }

    return relatedIds;
  }
}
