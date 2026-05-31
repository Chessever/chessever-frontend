import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/string_utils.dart';

final RegExp _roundTitlePattern = RegExp(
  r'^\s*(?:round|rd|r)\s*\d+[A-Za-z]?(?:\.\d+)?\s*[:\-–—]',
  caseSensitive: false,
);

/// Matches the parent broadcast slug in a Lichess broadcast `Site` URL, e.g.
/// `https://lichess.org/broadcast/<parent-slug>/round-7/<roundId>/<chapterId>`
/// -> `<parent-slug>`. This is the only place the canonical parent-event name
/// survives for TWIC/broadcast games whose PGN Event is a per-round pairing
/// label; the gamebase rows carry no tour_id/tournament_id/tourSlug field.
final RegExp _lichessBroadcastSitePattern = RegExp(
  r'lichess\.org/broadcast/([^/?#]+)',
  caseSensitive: false,
);

/// Derives a canonical event title from a Lichess broadcast `Site` URL by
/// title-casing the parent broadcast slug. Returns null when [site] is not a
/// recognizable Lichess broadcast URL (e.g. `Chess.com`, `Oslo, NO`).
String? eventTitleFromBroadcastSite(String? site) {
  final value = site?.trim();
  if (value == null || value.isEmpty) return null;
  final slug = _lichessBroadcastSitePattern.firstMatch(value)?.group(1)?.trim();
  if (slug == null || slug.isEmpty) return null;
  // `--` slug separators become double spaces via slugToTitle; collapse them.
  final title =
      StringUtils.slugToTitle(slug).replaceAll(RegExp(r'\s+'), ' ').trim();
  return title.isEmpty ? null : title;
}

/// Returns true for TWIC/Gamebase labels that describe a round or pairing,
/// not the parent tournament/event.
///
/// These labels can arrive in PGN Event headers or player-events rows. They
/// should never replace a canonical event title when one is available from the
/// player-games list.
bool isTwicRoundDisplayTitle(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return false;
  return _roundTitlePattern.hasMatch(text);
}

bool _isUsefulEventTitle(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return false;
  if (text == '?' || text == 'Gamebase' || text == 'library') return false;
  return !isTwicRoundDisplayTitle(text);
}

/// Prefer the canonical event carried by the game list over a PGN/Event value
/// that is only a round/pairing label (e.g. `Round 13: Yilmaz, Mustafa ...`).
String preferredTwicEventTitle({
  String? pgnEvent,
  String? tourSlug,
  String? tourId,
  String? site,
  String fallback = 'Game Info',
}) {
  final pgn = pgnEvent?.trim();
  final slug = tourSlug?.trim();
  final id = tourId?.trim();

  if (_isUsefulEventTitle(pgn)) return pgn!;
  if (_isUsefulEventTitle(slug)) return slug!;
  if (_isUsefulEventTitle(id)) return id!;

  // PGN Event / tour fields were only round/pairing labels. For TWIC broadcast
  // games the canonical parent event survives solely in the Lichess `Site` URL.
  final fromSite = eventTitleFromBroadcastSite(site);
  if (fromSite != null) return fromSite;

  if (pgn != null && pgn.isNotEmpty && pgn != '?') return pgn;
  if (slug != null && slug.isNotEmpty) return slug;
  if (id != null && id.isNotEmpty) return id;
  return fallback;
}

String twicCanonicalEventKeyForGame(GamesTourModel game) {
  final title = preferredTwicEventTitle(
    tourSlug: game.tourSlug,
    tourId: game.tourId,
    fallback: game.gameId,
  );
  return title
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}
