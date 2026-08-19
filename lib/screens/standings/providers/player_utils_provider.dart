import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/utils/favorite_player_identity.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The stored favourite matching a player, or null when they are not followed.
///
/// A FIDE id identifies the player when both sides have one. Comparing the raw
/// ids without that guard makes `null == null` a match, so the first favourite
/// saved without a FIDE id would light up the heart for every unrated or
/// unidentified player in the standings — routine in broadcast fields — and
/// each tap would take the add branch again, burning a free-tier slot and
/// firing the paywall while the heart never clears.
///
/// The name fallback covers players a broadcast ships with no FIDE id at all,
/// and it is also what removal keys on: the profile screen stores the raw
/// profile name while the scorecard stores the backfilled standings name, so
/// callers unfollow by the returned favourite's own [FavoritePlayer.playerName]
/// rather than by whatever name their own screen happens to hold.
FavoritePlayer? storedFavoriteFor(
  List<FavoritePlayer> favorites, {
  String? fideId,
  required String name,
  String? countryCode,
}) {
  final parsedFideId = parsePositiveFideId(fideId);
  for (final favorite in favorites) {
    if (favoriteMatchesPlayer(
      favorite: favorite,
      playerName: name,
      playerFideId: parsedFideId,
      playerCountry: countryCode ?? '',
    )) {
      return favorite;
    }
  }
  return null;
}

/// Presents canonical `Last, First` chess data in natural `First Last` order.
/// Names already supplied in display order are preserved.
String formatPlayerDisplayName(String name) {
  final displayName = name.trim();
  final commaIndex = displayName.indexOf(',');
  if (commaIndex <= 0 || commaIndex == displayName.length - 1) {
    return displayName;
  }

  final familyName = displayName.substring(0, commaIndex).trim();
  final givenNames = displayName.substring(commaIndex + 1).trim();
  if (familyName.isEmpty || givenNames.isEmpty) return displayName;

  return '$givenNames $familyName';
}

final playerUtilsProvider = AutoDisposeProvider(
  (ref) => _PlayerUtilsController(ref),
);

class _PlayerUtilsController {
  _PlayerUtilsController(this.ref);

  final Ref ref;

  /// Checks if a player matches by fideId first (most reliable), then by name.
  /// Returns true if fideIds match OR if names match using fuzzy logic.
  bool isSamePlayerWithFideId(
    String? name1,
    String? name2, {
    int? fideId1,
    int? fideId2,
  }) {
    // Prefer fideId matching - most reliable
    if (fideId1 != null && fideId2 != null && fideId1 > 0 && fideId2 > 0) {
      return fideId1 == fideId2;
    }

    // Fall back to name matching
    return isSamePlayer(name1, name2);
  }

  bool isSamePlayer(String? name1, String? name2) {
    return playerNamesMatch(name1, name2);
  }
}
