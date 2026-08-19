import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/utils/country_utils.dart';

final _titlePrefix = RegExp(
  r'^(gm|im|fm|cm|nm|wgm|wim|wfm|wcm|wnm)\s+',
  caseSensitive: false,
);

const _neutralFederations = <String>{
  'FID',
  'FIDE',
  'INT',
  'XX',
  'NON',
  'NONE',
  '?',
};

/// True when [name1] and [name2] refer to the same person.
///
/// Handles `Last, First` vs `First Last`, optional title prefixes, and
/// missing/extra middle names. Empty names never match.
bool playerNamesMatch(String? name1, String? name2) {
  if (name1 == null || name2 == null) return false;

  final n1 = _nameTokens(name1);
  final n2 = _nameTokens(name2);
  if (n1.isEmpty || n2.isEmpty) return false;
  if (n1.join(' ') == n2.join(' ')) return true;

  if (n1.length == 2 && n2.length == 2) {
    if (n1[0] == n2[1] && n1[1] == n2[0]) return true;
  }

  if (n1.length >= 2 && n2.length >= 2) {
    final set1 = n1.toSet();
    final set2 = n2.toSet();
    if (set1.length == set2.length && set1.containsAll(set2)) return true;

    final intersection = set1.intersection(set2);
    if (intersection.length >= 2) {
      final smallerSize = set1.length < set2.length ? set1.length : set2.length;
      if (intersection.length >= smallerSize - 1) return true;
    }
  }

  return false;
}

/// Federation values that do not identify a country. Lichess/FIDE ship `FID`
/// for many Russian and Belarusian players instead of `RUS`/`BLR`.
bool isNeutralFederation(String? value) {
  final normalized = value?.trim().toUpperCase() ?? '';
  return normalized.isEmpty || _neutralFederations.contains(normalized);
}

/// Country codes are compatible when either side is missing/neutral (`FID`)
/// or both resolve to the same ISO-2 country. Two concrete different
/// countries still do not match, so "Shared Name" USA ≠ GER.
bool favoriteCountryCompatible(String favoriteCountry, String playerCountry) {
  if (isNeutralFederation(favoriteCountry) ||
      isNeutralFederation(playerCountry)) {
    return true;
  }
  final favoriteIso2 = countryCodeToIso2(favoriteCountry);
  final playerIso2 = countryCodeToIso2(playerCountry);
  if (favoriteIso2.isEmpty || playerIso2.isEmpty) return true;
  return favoriteIso2 == playerIso2;
}

String countryCodeToIso2(String value) {
  final normalized = value.trim().toUpperCase();
  if (normalized.length == 2) return normalized;
  if (normalized.length == 3) return CountryUtils.toIso2Code(normalized);
  return CountryUtils.countryNameToIso2(value);
}

int? parsePositiveFideId(String? raw) {
  final parsed = int.tryParse(raw?.trim() ?? '');
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

/// Whether a stored favourite is the same person as a broadcast/standings
/// player. Positive FIDE ids are authoritative; otherwise a name match is
/// accepted unless both sides have concrete conflicting countries.
bool favoriteMatchesPlayer({
  required FavoritePlayer favorite,
  required String playerName,
  int? playerFideId,
  String playerCountry = '',
}) {
  final favoriteFideId = parsePositiveFideId(favorite.fideId);
  final validPlayerFideId =
      playerFideId != null && playerFideId > 0 ? playerFideId : null;

  if (favoriteFideId != null && validPlayerFideId != null) {
    return favoriteFideId == validPlayerFideId;
  }

  if (!playerNamesMatch(favorite.playerName, playerName)) return false;
  return favoriteCountryCompatible(
    favoriteCountryCode(favorite),
    playerCountry,
  );
}

String favoriteCountryCode(FavoritePlayer favorite) {
  return (favorite.metadata['countryCode'] ?? favorite.metadata['country'])
          ?.toString()
          .trim() ??
      '';
}

List<String> _nameTokens(String name) {
  final stripped = name.trim().replaceFirst(_titlePrefix, '');
  return stripped
      .toLowerCase()
      .replaceAll(',', ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}
