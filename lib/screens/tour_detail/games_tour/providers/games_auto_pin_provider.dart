import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_priority_matching.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef AutoPinnedGamesResult =
    ({
      bool autoPinDisabled,
      bool favoritePriorityEnabled,
      bool countrymanPriorityEnabled,
      List<String> favoriteGameIds,
      List<String> countrymanGameIds,
      List<FavoritePlayer> favoritePlayersSnapshot,
      String selectedCountryCode,
    });

final autoPinLogicProvider = Provider<_AutoPinLogController>(
  (ref) => _AutoPinLogController(ref),
);

class _AutoPinLogController {
  _AutoPinLogController(this.ref);

  final Ref ref;

  AutoPinPreferencesRepository get _repo =>
      AutoPinPreferencesRepository(AppDatabase.instance);

  String? get _userId => ref.read(currentUserProvider)?.id;

  Future<AutoPinnedGamesResult> getAutoPinnedGames(String tourId) async {
    final shouldHidePin = await _repo.getTournamentAutoPinDisabled(
      tourId,
      _userId,
    );
    if (shouldHidePin) {
      return (
        autoPinDisabled: true,
        favoritePriorityEnabled: false,
        countrymanPriorityEnabled: false,
        favoriteGameIds: <String>[],
        countrymanGameIds: <String>[],
        favoritePlayersSnapshot: <FavoritePlayer>[],
        selectedCountryCode: '',
      );
    }

    final prefs = await ref.read(autoPinPreferencesProvider.future);

    if (!prefs.favoritePlayersAutoPinEnabled &&
        !prefs.countrymenAutoPinEnabled) {
      return (
        autoPinDisabled: false,
        favoritePriorityEnabled: false,
        countrymanPriorityEnabled: false,
        favoriteGameIds: <String>[],
        countrymanGameIds: <String>[],
        favoritePlayersSnapshot: <FavoritePlayer>[],
        selectedCountryCode: '',
      );
    }

    final gamesList = _getAllGamePrioritiesIncludingStages(tourId);
    var favoriteGameIds = <String>{};
    var countrymanGameIds = <String>{};
    var favoritePlayersSnapshot = <FavoritePlayer>[];
    var selectedCountryCode = '';

    // Favorite players auto-pin
    if (prefs.favoritePlayersAutoPinEnabled) {
      final favorites = await ref.read(favoritePlayersProviderNew.future);
      favoritePlayersSnapshot = favorites;
      favoriteGameIds = favoritePlayerGameIdsForIdentities(
        games: gamesList,
        favorites: favorites,
      );
    }

    // Countrymen auto-pin
    if (prefs.countrymenAutoPinEnabled) {
      final countryCode = await _resolveCountryCode();
      if (countryCode != null && countryCode.isNotEmpty) {
        selectedCountryCode = countryCode;
        final countryGames = countrymanGameIdsForIdentities(
          games: gamesList,
          selectedCountryCode: countryCode,
        );

        // Skip if every game matches (entire field is same country)
        if (countryGames.length < gamesList.length) {
          countrymanGameIds = countryGames;
        }
      }
    }

    return (
      autoPinDisabled: false,
      favoritePriorityEnabled: prefs.favoritePlayersAutoPinEnabled,
      countrymanPriorityEnabled: prefs.countrymenAutoPinEnabled,
      favoriteGameIds: favoriteGameIds.toList(growable: false),
      countrymanGameIds: countrymanGameIds.toList(growable: false),
      favoritePlayersSnapshot: favoritePlayersSnapshot,
      selectedCountryCode: selectedCountryCode,
    );
  }

  Future<String?> _resolveCountryCode() async {
    final current = ref.read(countryDropdownProvider);
    final currentCode = _countryCodeFrom(current);
    if (currentCode != null || current.hasError) return currentCode;

    // When country priority is enabled, do not place boards against an
    // unresolved country and move them again a moment later. The country
    // provider owns local-cache migration, location fallback, and defaults;
    // wait for its one resolved value rather than polling either source.
    final completer = Completer<String?>();
    late final ProviderSubscription<AsyncValue<Country>> subscription;
    subscription = ref.listen<AsyncValue<Country>>(countryDropdownProvider, (
      previous,
      next,
    ) {
      if (completer.isCompleted) return;
      if (next.hasValue) {
        completer.complete(_countryCodeFrom(next));
      } else if (next.hasError) {
        completer.complete(null);
      }
    }, fireImmediately: true);
    try {
      // The country provider normally answers immediately from cache, but a
      // location fallback can stall. An unbounded wait here used to block the
      // whole pin snapshot, so a later manual pin never surfaced.
      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } finally {
      subscription.close();
    }
  }

  String? _countryCodeFrom(AsyncValue<Country> country) {
    final code = country.valueOrNull?.countryCode.trim().toUpperCase();
    return code == null || code.isEmpty ? null : code;
  }

  /// Collects lightweight player identities from the selected tour and every
  /// related knockout stage without reparsing PGNs or clocks.
  List<GamePriorityIdentity> _getAllGamePrioritiesIncludingStages(
    String tourId,
  ) {
    final allGames = <GamePriorityIdentity>[];
    final seenGameIds = <String>{};

    void addGames(Iterable<GamePriorityIdentity> games) {
      for (final game in games) {
        if (seenGameIds.add(game.gameId)) allGames.add(game);
      }
    }

    // Get games from the main/selected tour using the raw games provider
    final mainGamesRaw =
        ref.read(gamesTourProvider(tourId)).valueOrNull ?? const <Games>[];
    addGames(gamePriorityIdentitiesFromRawGames(mainGamesRaw));

    // Check if this is a multi-stage knockout tournament
    final tourDetail = ref.read(tourDetailScreenProvider).valueOrNull;
    if (tourDetail == null || tourDetail.tours.isEmpty) return allGames;

    // Find the current tour to get its groupBroadcastId
    final currentTour =
        tourDetail.tours
            .firstWhere(
              (t) => t.tour.id == tourId,
              orElse: () => tourDetail.tours.first,
            )
            .tour;

    final groupBroadcastId = currentTour.groupBroadcastId;
    if (groupBroadcastId == null || groupBroadcastId.isEmpty) {
      return allGames; // Not a multi-stage knockout
    }

    // Get all tours in the group broadcast
    final allToursInGroup =
        tourDetail.tours
            .where((t) => t.tour.groupBroadcastId == groupBroadcastId)
            .toList();

    if (allToursInGroup.length <= 1) {
      return allGames; // Not multi-stage
    }

    debugPrint(
      '🎯 Auto-pin: Detected ${allToursInGroup.length} stages in multi-stage knockout',
    );

    // Collect games from ALL stages
    for (final tourModel in allToursInGroup) {
      final stageTourId = tourModel.tour.id;
      if (stageTourId == tourId) continue; // Skip main tour (already added)

      final stageState = ref.read(knockoutTournamentStateProvider(stageTourId));
      addGames(gamePriorityIdentitiesFromModels(stageState.allGames));
    }

    debugPrint(
      '🎯 Auto-pin: Collected ${allGames.length} total games from all stages',
    );
    return allGames;
  }

  Future<void> enableAutoPin(String tourId) async {
    await _repo.setTournamentAutoPinDisabled(tourId, false, _userId);
  }

  Future<void> disableAutoPin(String tourId) async {
    await _repo.setTournamentAutoPinDisabled(tourId, true, _userId);
  }
}
