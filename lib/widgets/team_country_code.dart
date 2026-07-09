import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/location_service_provider.dart';

/// Resolves a team display name to an ISO-3166 alpha-2 country code when the
/// name is (or is a federation code for) a known country.
///
/// Matches Games-tab behaviour ([LocationService.getValidCountryCodeFromName])
/// and also accepts FIDE/IOC codes (`USA`, `IND`) and ISO2 (`US`) the same way
/// [LocationService.getValidCountryCode] does, so olympiad-style squads like
/// "USA" / "Norway" / "India" get flags while club names stay crest-only.
///
/// Returns `null` when the name is empty or not a country.
String? resolveTeamCountryCode(String teamName) {
  final raw = teamName.trim();
  if (raw.isEmpty) return null;

  final service = LocationService();

  // Codes first: "USA", "US", "IND", "GER", …
  final fromCode = service.getValidCountryCode(raw);
  if (fromCode.isNotEmpty) return fromCode;

  // Full country names: "Norway", "United States", …
  final fromName = service.getValidCountryCodeFromName(raw);
  if (fromName.isNotEmpty) return fromName;

  // Manual name map used elsewhere in the app (FederationFlag path).
  final manual = CountryUtils.countryNameToIso2(raw);
  if (manual.isNotEmpty) return manual;

  final byPicker = CountryUtils.getCountryCode(raw);
  if (byPicker != null && byPicker.length == 2) return byPicker;

  return null;
}
