import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:country_code/country_code.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final autoPinLogicProvider = AutoDisposeProvider<_AutoPinLogController>(
  (ref) => _AutoPinLogController(ref),
);

class _AutoPinLogController {
  _AutoPinLogController(this.ref);

  final Ref ref;

  Future<List<String>> getAutoPinnedGames() async {
    final countryCode = ref.read(countryDropdownProvider).value!.countryCode;
    final players = await ref.read(tournamentFavoritePlayersProvider.future);

    final gamesList =
        ref.watch(gamesTourScreenProvider).value?.gamesTourModels ?? [];

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

    if (filteredGames.length == gamesList.length) {
      return [...favPlayers];
    }

    return [...favPlayers, ...filteredGames];
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
