import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:country_code/country_code.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final autoPinLogicProvider = AutoDisposeProvider<_AutoPinLogController>(
  (ref) => _AutoPinLogController(ref),
);

const _autoPinFavKey = 'autoPinFavGames';

class _AutoPinLogController {
  _AutoPinLogController(this.ref);

  final Ref ref;
  String _getTournamentKey(String tourId) => '${_autoPinFavKey}_$tourId';

  Future<(bool, List<String>)> getAutoPinnedGames(String tourId) async {
    final shouldHidePin = await _getHidePin(tourId);
    if (shouldHidePin) {
      return (true, <String>[]);
    } else {
      final countryCode = await _resolveCountryCode();
      final players = await ref.read(tournamentFavoritePlayersProvider.future);

      // Collect games from ALL stages in multi-stage knockouts
      final gamesList = _getAllGamesIncludingStages(tourId);

      final favPlayers =
          gamesList
              .where((games) {
                return players.any(
                      (player) =>
                          player.name == games.whitePlayer.name &&
                          games.whitePlayer.federation == player.countryCode,
                    ) ||
                    players.any(
                      (player) =>
                          player.name == games.blackPlayer.name &&
                          games.blackPlayer.federation == player.countryCode,
                    );
              })
              .map((e) => e.gameId)
              .toList();

      if (countryCode == null || countryCode.isEmpty) {
        print('⚠️ Auto-pin: Country unavailable, falling back to favorites only');
        return (false, [...favPlayers]);
      }

      final filteredGames =
          gamesList
              .where((game) {
                // Use the matcher to compare regardless of ISO format
                return CountryCodeMatcher.matches(
                      game.whitePlayer.countryCode,
                      countryCode,
                    ) ||
                    CountryCodeMatcher.matches(
                      game.blackPlayer.countryCode,
                      countryCode,
                    );
              })
              .map((e) => e.gameId)
              .toList();

      if (filteredGames.length == gamesList.length) {
        return (false, [...favPlayers]);
      }

      return (false, [...favPlayers, ...filteredGames]);
    }
  }

  Future<String?> _resolveCountryCode() async {
    // Get country code directly from SharedPreferences (fast, synchronous)
    // This ensures auto-pin works even while Supabase is syncing
    final prefs = await SharedPreferencesService.instance.ensureInitialized();
    final cachedCountryCode = prefs.getString('selected_country_code');

    if (cachedCountryCode != null && cachedCountryCode.isNotEmpty) {
      // Use cached country code (works immediately, no async wait)
      print('🎯 Auto-pin: Using cached country code: $cachedCountryCode');
      return cachedCountryCode;
    }

    // Fallback: wait for provider to load if no cache
    final countryAsync = ref.read(countryDropdownProvider);
    if (countryAsync.hasValue && countryAsync.value != null) {
      final countryCode = countryAsync.value!.countryCode;
      print('🎯 Auto-pin: Using provider country code: $countryCode');
      return countryCode;
    }

    // Wait up to 3 seconds for country to load
    print('⚠️ Auto-pin: Country not cached, waiting for provider...');
    var attempts = 0;
    while (attempts < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      final retry = ref.read(countryDropdownProvider);
      if (retry.hasValue && retry.value != null) {
        final countryCode = retry.value!.countryCode;
        print('🎯 Auto-pin: Provider loaded, using: $countryCode');
        return countryCode;
      }
      attempts++;
    }

    print('❌ Auto-pin: Country still not loaded after 3s');
    return null;
  }

  /// Collects games from the main tour AND all stages in multi-stage knockouts
  List<GamesTourModel> _getAllGamesIncludingStages(String tourId) {
    final allGames = <GamesTourModel>[];

    // Get games from the main/selected tour using the raw games provider
    final mainGamesRaw =
        ref.read(gamesTourProvider(tourId)).valueOrNull ?? const <Games>[];
    final mainGames = mainGamesRaw
        .map((game) {
          try {
            return GamesTourModel.fromGame(game);
          } catch (_) {
            return null;
          }
        })
        .whereType<GamesTourModel>()
        .toList();
    allGames.addAll(mainGames);

    // Check if this is a multi-stage knockout tournament
    final tourDetail = ref.read(tourDetailScreenProvider).valueOrNull;
    if (tourDetail == null || tourDetail.tours.isEmpty) return allGames;

    // Find the current tour to get its groupBroadcastId
    final currentTour = tourDetail.tours
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
    final allToursInGroup = tourDetail.tours
        .where((t) => t.tour.groupBroadcastId == groupBroadcastId)
        .toList();

    if (allToursInGroup.length <= 1) {
      return allGames; // Not multi-stage
    }

    print('🎯 Auto-pin: Detected ${allToursInGroup.length} stages in multi-stage knockout');

    // Collect games from ALL stages
    final stageGamesSet = <String>{}; // Track game IDs to avoid duplicates
    for (final game in mainGames) {
      stageGamesSet.add(game.gameId);
    }

    for (final tourModel in allToursInGroup) {
      final stageTourId = tourModel.tour.id;
      if (stageTourId == tourId) continue; // Skip main tour (already added)

      final stageState = ref.read(knockoutTournamentStateProvider(stageTourId));
      for (final game in stageState.allGames) {
        if (!stageGamesSet.contains(game.gameId)) {
          allGames.add(game);
          stageGamesSet.add(game.gameId);
        }
      }
    }

    print('🎯 Auto-pin: Collected ${allGames.length} total games from all stages');
    return allGames;
  }

  Future<void> enableAutoPin(String tourId) async {
    await _shouldHidePin(tourId: tourId, shouldHide: false);
  }

  Future<void> disableAutoPin(String tourId) async {
    await _shouldHidePin(tourId: tourId, shouldHide: true);
  }

  Future<void> _shouldHidePin({
    required String tourId,
    required bool shouldHide,
  }) async {
    final key = _getTournamentKey(tourId);
    await _prefs.setBool(key, shouldHide);
  }

  Future<bool> _getHidePin(String tourId) async {
    final key = _getTournamentKey(tourId);
    return _prefs.getBool(key) ?? false;
  }
}

class CountryCodeMatcher {
  static bool matches(String code1, String code2) {
    if (code1.isEmpty || code2.isEmpty) return false;

    final c1 = code1.toUpperCase().trim();
    final c2 = code2.toUpperCase().trim();

    if (c1 == c2) return true;

    final iso3_1 = _normalizeToIso3(c1);
    final iso3_2 = _normalizeToIso3(c2);
    if (iso3_1.isNotEmpty && iso3_1 == iso3_2) return true;

    final iso2_1 = _normalizeToIso2(c1);
    final iso2_2 = _normalizeToIso2(c2);
    if (iso2_1.isNotEmpty && iso2_1 == iso2_2) return true;

    // 4️⃣ Cross comparison (ISO2 of one vs ISO3 of another)
    if (iso2_1.isNotEmpty && iso2_1 == _normalizeToIso2(iso3_2)) return true;
    if (iso3_1.isNotEmpty && iso3_1 == _normalizeToIso3(iso2_2)) return true;

    return false;
  }

  static String _normalizeToIso3(String code) {
    final upper = code.toUpperCase().trim();

    if (upper.length == 3) return upper; // Already ISO3

    if (upper.length == 2) {
      try {
        final data = CountryCode.tryParse(upper);
        return data?.alpha3 ?? '';
      } catch (_) {
        return '';
      }
    }

    return '';
  }

  static String _normalizeToIso2(String code) {
    final upper = code.toUpperCase().trim();

    if (upper.length == 2) return upper; // Already ISO2

    if (upper.length == 3) {
      try {
        final data = CountryCode.tryParse(upper);
        return data?.alpha2 ?? '';
      } catch (_) {
        return '';
      }
    }

    return '';
  }
}
