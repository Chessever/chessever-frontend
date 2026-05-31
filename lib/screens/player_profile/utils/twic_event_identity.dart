import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

final RegExp _roundTitlePattern = RegExp(
  r'^\s*(?:round|rd|r)\s*\d+[A-Za-z]?(?:\.\d+)?\s*[:\-–—]',
  caseSensitive: false,
);

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
  String fallback = 'Game Info',
}) {
  final pgn = pgnEvent?.trim();
  final slug = tourSlug?.trim();
  final id = tourId?.trim();

  if (_isUsefulEventTitle(pgn)) return pgn!;
  if (_isUsefulEventTitle(slug)) return slug!;
  if (_isUsefulEventTitle(id)) return id!;
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
