import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_auto_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_priority_matching.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesPinState {
  final List<String> manualPins;
  final List<String> favoriteAutoPins;
  final List<String> countrymanAutoPins;
  final bool favoritePriorityEnabled;
  final bool countrymanPriorityEnabled;
  final List<FavoritePlayer> favoritePlayersSnapshot;
  final String selectedCountryCode;
  final List<String> unpinnedOverrides;
  final bool autoPinDisabled;
  final bool hasResolvedAutoPins;
  final bool isRefreshingAutoPins;

  const GamesPinState({
    this.manualPins = const [],
    this.favoriteAutoPins = const [],
    this.countrymanAutoPins = const [],
    this.favoritePriorityEnabled = false,
    this.countrymanPriorityEnabled = false,
    this.favoritePlayersSnapshot = const [],
    this.selectedCountryCode = '',
    this.unpinnedOverrides = const [],
    this.autoPinDisabled = false,
    this.hasResolvedAutoPins = false,
    this.isRefreshingAutoPins = false,
  });

  List<String> get autoPins =>
      autoPinDisabled
          ? const <String>[]
          : mergePinListsPreservingOrder([
            favoriteAutoPins,
            countrymanAutoPins,
          ]);

  List<String> get allPins {
    return mergeEffectivePins(
      manualPins: manualPins,
      autoPins: autoPins,
      unpinnedOverrides: unpinnedOverrides,
    );
  }

  GamesPinState copyWith({
    List<String>? manualPins,
    List<String>? favoriteAutoPins,
    List<String>? countrymanAutoPins,
    bool? favoritePriorityEnabled,
    bool? countrymanPriorityEnabled,
    List<FavoritePlayer>? favoritePlayersSnapshot,
    String? selectedCountryCode,
    List<String>? unpinnedOverrides,
    bool? autoPinDisabled,
    bool? hasResolvedAutoPins,
    bool? isRefreshingAutoPins,
  }) {
    return GamesPinState(
      manualPins: manualPins ?? this.manualPins,
      favoriteAutoPins: favoriteAutoPins ?? this.favoriteAutoPins,
      countrymanAutoPins: countrymanAutoPins ?? this.countrymanAutoPins,
      favoritePriorityEnabled:
          favoritePriorityEnabled ?? this.favoritePriorityEnabled,
      countrymanPriorityEnabled:
          countrymanPriorityEnabled ?? this.countrymanPriorityEnabled,
      favoritePlayersSnapshot:
          favoritePlayersSnapshot ?? this.favoritePlayersSnapshot,
      selectedCountryCode: selectedCountryCode ?? this.selectedCountryCode,
      unpinnedOverrides: unpinnedOverrides ?? this.unpinnedOverrides,
      autoPinDisabled: autoPinDisabled ?? this.autoPinDisabled,
      hasResolvedAutoPins: hasResolvedAutoPins ?? this.hasResolvedAutoPins,
      isRefreshingAutoPins: isRefreshingAutoPins ?? this.isRefreshingAutoPins,
    );
  }

  /// Manual pins that are still in force, i.e. not undone by an explicit
  /// unpin. These lead the Games tab order.
  Set<String> get effectiveManualPinIds {
    if (manualPins.isEmpty) return const <String>{};
    final overrides = unpinnedOverrides.toSet();
    return manualPins.where((id) => !overrides.contains(id)).toSet();
  }

  Set<String> get effectiveFavoritePriorityIds =>
      _effectivePriorityIds(favoriteAutoPins);

  Set<String> get effectiveCountrymanPriorityIds =>
      _effectivePriorityIds(countrymanAutoPins);

  Set<String> effectiveFavoritePriorityIdsForGames(
    Iterable<GamesTourModel> games,
  ) {
    if (favoritePriorityEnabled && favoritePlayersSnapshot.isNotEmpty) {
      return _effectivePriorityIds(
        favoritePlayerGameIdsForGames(
          games: games,
          favorites: favoritePlayersSnapshot,
        ),
      );
    }
    return effectiveFavoritePriorityIds;
  }

  Set<String> effectiveCountrymanPriorityIdsForGames(
    Iterable<GamesTourModel> games,
  ) {
    if (countrymanPriorityEnabled && selectedCountryCode.isNotEmpty) {
      final uniqueGames = <String, GamesTourModel>{
        for (final game in games) game.gameId: game,
      };
      final ids = countrymanGameIdsForGames(
        games: uniqueGames.values,
        selectedCountryCode: selectedCountryCode,
      );
      // Preserve the existing behavior: country priority adds no value when
      // the entire field consists of countrymen.
      if (ids.length >= uniqueGames.length) return const <String>{};
      return _effectivePriorityIds(ids);
    }
    return effectiveCountrymanPriorityIds;
  }

  Set<String> _effectivePriorityIds(Iterable<String> ids) {
    if (autoPinDisabled || ids.isEmpty) return const <String>{};
    final overrides = unpinnedOverrides.toSet();
    return ids.where((id) => !overrides.contains(id)).toSet();
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

final gamesPinprovider = StateNotifierProvider.autoDispose
    .family<_GamesPinController, GamesPinState, String>((ref, tourId) {
      return _GamesPinController(ref: ref, tourId: tourId);
    });

/// Upper bound on one auto-pin resolution pass. It reads local preferences,
/// favorites and the resolved country, none of which may stall the pin
/// snapshot indefinitely.
const _autoPinResolveTimeout = Duration(seconds: 8);

class _GamesPinController extends StateNotifier<GamesPinState> {
  _GamesPinController({required this.ref, required this.tourId})
    : super(GamesPinState()) {
    _listenToFavoritePlayers();
    _listenToKnockoutStages();
    _listenToCountrySelection();
    _listenToPrimaryGames();
    _listenToAutoPinPreferences();
    if (_pinLoadInFlight == null) loadPinnedGames();
  }

  final Ref ref;
  final String tourId;
  final Set<String> _stageListeners = <String>{};
  Future<void>? _pinLoadInFlight;
  bool _reloadPinSnapshot = false;

  void _listenToFavoritePlayers() {
    // Observe the canonical favorites provider. Loading/error transitions do
    // not clear the last resolved pin snapshot.
    ref.listen<AsyncValue<List<FavoritePlayer>>>(favoritePlayersProviderNew, (
      previous,
      next,
    ) {
      if (!next.hasValue) return;
      final prefs =
          ref.read(autoPinPreferencesProvider).valueOrNull ??
          AutoPinPreferences.defaults;
      if (prefs.favoritePlayersAutoPinEnabled) computeAutoPins();
    });
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

      var addedStageListener = false;
      for (final stageId in relatedStageIds) {
        // The selected tour already has the raw primary-games listener below.
        // Listening to its derived knockout state as well would enqueue the
        // same scan twice for one identity update.
        if (stageId == tourId) continue;

        // Avoid wiring duplicate listeners
        if (_stageListeners.contains(stageId)) continue;
        _stageListeners.add(stageId);
        addedStageListener = true;

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
        );
      }

      // One scan covers every newly wired stage and its current snapshot.
      if (addedStageListener) computeAutoPins();
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
    });
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

      final prefs =
          ref.read(autoPinPreferencesProvider).valueOrNull ??
          AutoPinPreferences.defaults;
      if (!prefs.countrymenAutoPinEnabled) return;

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
    return didModelGamePriorityInputsChange(previous, next);
  }

  bool _didRawGamesChange(List<Games> previous, List<Games> next) {
    return didRawGamePriorityInputsChange(previous, next);
  }

  Future<void> loadPinnedGames() {
    final inFlight = _pinLoadInFlight;
    if (inFlight != null) {
      _reloadPinSnapshot = true;
      return inFlight;
    }

    final future = _drainPinLoads();
    _pinLoadInFlight = future;
    return future;
  }

  Future<void> _drainPinLoads() async {
    try {
      do {
        _reloadPinSnapshot = false;
        await _loadPinnedGamesOnce();
      } while (mounted && _reloadPinSnapshot);
    } finally {
      _pinLoadInFlight = null;
    }
  }

  /// Publishes the manual pin snapshot first, then the auto-pin one.
  ///
  /// The two used to resolve in a single `Future.wait`, which meant a failing
  /// (or, with an unresolvable country, a never-completing) auto-pin lookup
  /// threw away the manual pin the user had just tapped — the pin appeared to
  /// do nothing at all. A pin is local, instant and explicit, so it is applied
  /// on its own and cannot be held hostage by the auto-pin scan.
  Future<void> _loadPinnedGamesOnce() async {
    final storage = ref.read(pinGameLocalStorage);
    final relatedTourIds = _getRelatedTourIds();

    // Kicked off first so it still overlaps the manual read, but with its own
    // failure and time bounds so it can never wedge this pass.
    final autoPinFuture = Future<AutoPinnedGamesResult?>(
      () => ref.read(autoPinLogicProvider).getAutoPinnedGames(tourId),
    ).timeout(_autoPinResolveTimeout, onTimeout: () => null).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      debugPrint('Failed to resolve auto pins for $tourId: $error\n$stackTrace');
      return null;
    });

    try {
      final manualResults = await Future.wait([
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
      ]);

      if (!mounted || _reloadPinSnapshot) return;
      _publish(
        state.copyWith(
          manualPins: mergePinListsPreservingOrder(manualResults[0]),
          unpinnedOverrides: mergePinListsPreservingOrder(manualResults[1]),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to load manual pins for $tourId: $error\n$stackTrace');
    }

    final autoPinnedGames = await autoPinFuture;
    if (!mounted || _reloadPinSnapshot) return;

    // Never leave the Games tab behind a permanent loading state. Whatever pin
    // data resolved stays intact and board-number ordering is the fallback.
    _publish(
      autoPinnedGames == null
          ? state.copyWith(
            hasResolvedAutoPins: true,
            isRefreshingAutoPins: false,
          )
          : state.copyWith(
            favoriteAutoPins: autoPinnedGames.favoriteGameIds,
            countrymanAutoPins: autoPinnedGames.countrymanGameIds,
            favoritePriorityEnabled: autoPinnedGames.favoritePriorityEnabled,
            countrymanPriorityEnabled:
                autoPinnedGames.countrymanPriorityEnabled,
            favoritePlayersSnapshot: autoPinnedGames.favoritePlayersSnapshot,
            selectedCountryCode: autoPinnedGames.selectedCountryCode,
            autoPinDisabled: autoPinnedGames.autoPinDisabled,
            hasResolvedAutoPins: true,
            isRefreshingAutoPins: false,
          ),
    );
  }

  void _publish(GamesPinState nextState) {
    if (_haveSamePinState(state, nextState)) return;
    state = nextState;
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
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to toggle pin for $gameId in $sourceTourId: $error\n$stackTrace',
      );
    }
  }

  /// Drops every manual pin for this tour and its related stages.
  ///
  /// "Unpin all" used to call a storage method whose body was empty, so manual
  /// pins survived it.
  Future<void> clearManualPins() async {
    try {
      final storage = ref.read(pinGameLocalStorage);
      await Future.wait(
        _getRelatedTourIds().map(
          (relatedTourId) => storage.clearPinnedGames(relatedTourId),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to clear manual pins for $tourId: $error\n$stackTrace');
    }
    await loadPinnedGames();
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
    if (mounted && state.hasResolvedAutoPins && !state.isRefreshingAutoPins) {
      state = state.copyWith(isRefreshingAutoPins: true);
    }
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

bool _haveSamePinState(GamesPinState first, GamesPinState second) {
  return first.autoPinDisabled == second.autoPinDisabled &&
      first.hasResolvedAutoPins == second.hasResolvedAutoPins &&
      first.isRefreshingAutoPins == second.isRefreshingAutoPins &&
      first.favoritePriorityEnabled == second.favoritePriorityEnabled &&
      first.countrymanPriorityEnabled == second.countrymanPriorityEnabled &&
      first.selectedCountryCode == second.selectedCountryCode &&
      listEquals(first.manualPins, second.manualPins) &&
      listEquals(first.favoriteAutoPins, second.favoriteAutoPins) &&
      listEquals(first.countrymanAutoPins, second.countrymanAutoPins) &&
      listEquals(
        first.favoritePlayersSnapshot,
        second.favoritePlayersSnapshot,
      ) &&
      listEquals(first.unpinnedOverrides, second.unpinnedOverrides);
}
