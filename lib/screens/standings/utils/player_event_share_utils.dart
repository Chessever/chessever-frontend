import 'package:chessever2/screens/player_profile/utils/player_profile_share_utils.dart';
import 'package:chessever2/screens/standings/widgets/player_event_share_image_card.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show buildEventShareUrl;

/// Rating total for the same game snapshot rendered on the player report.
/// Standings can lag a completed game, so a complete set of known changes wins.
/// Preserve source totals for incomplete history, custom scoring, and mixed
/// rating pools; those cannot be reconstructed as one local Elo total.
int? resolvePlayerEventRatingDiff({
  required List<PlayerEventShareGameRow> rows,
  int sourcePlayed = 0,
  int? fallbackRatingDiff,
  bool preferSource = false,
}) {
  if (preferSource) return fallbackRatingDiff;
  final pools = <String>{};
  var finishedGames = 0;
  var total = 0.0;
  for (final row in rows) {
    if (row.outcome == PlayerEventGameOutcome.other) continue;
    finishedGames++;
    pools.add(row.ratingPool ?? 'standard');
    if (pools.length > 1) return fallbackRatingDiff;
    final change = row.ratingChange;
    if (change == null) return fallbackRatingDiff;
    total += change;
  }
  if (finishedGames == 0 || finishedGames < sourcePlayed) {
    return fallbackRatingDiff;
  }
  // Round once after summing: rounding each row can change the event total.
  return total.round();
}

/// Sentinels that gamebase/TWIC rows put in `tourId` when there is no real
/// broadcast identity — never treat these as URL path segments.
const _kDisplayOnlyTourIds = {'gamebase', 'miniatures'};

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _lichessShortIdPattern = RegExp(r'^[A-Za-z0-9]{8}$');

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// True when [id] is a real broadcast / group-broadcast identity, not a
/// written event name or archive sentinel.
bool isUrlBackedEventId(String? id) {
  final trimmed = _nonEmpty(id);
  if (trimmed == null) return false;
  if (_kDisplayOnlyTourIds.contains(trimmed.toLowerCase())) return false;
  if (RegExp(r'\s').hasMatch(trimmed)) return false;
  return StringUtils.looksLikeUrlSlug(trimmed) ||
      _uuidPattern.hasMatch(trimmed) ||
      _lichessShortIdPattern.hasMatch(trimmed);
}

/// True when a tour pair is safe to put in `/broadcast/<slug>/<id>`.
///
/// Game context copied off a scorecard — and some about-model fields on
/// archive rows — can be a display label (event name in `tourSlug`, invented
/// `Gamebase` id). Reject those so Share Link falls back instead of a dead
/// route.
bool isUrlBackedTourIdentity({String? tourId, String? tourSlug}) {
  final slug = _nonEmpty(tourSlug);
  if (slug == null || !StringUtils.looksLikeUrlSlug(slug)) return false;
  return isUrlBackedEventId(tourId);
}

/// Picks a URL-backed event identity from about-model and/or game context.
({String eventId, String? tourId, String? tourSlug})? resolveUrlBackedEvent({
  String? canonicalEventId,
  String? tourId,
  String? tourSlug,
  String? contextTourId,
  String? contextTourSlug,
}) {
  String? resolvedTourId;
  String? resolvedTourSlug;
  if (isUrlBackedTourIdentity(tourId: tourId, tourSlug: tourSlug)) {
    resolvedTourId = _nonEmpty(tourId);
    resolvedTourSlug = _nonEmpty(tourSlug);
  } else if (isUrlBackedTourIdentity(
    tourId: contextTourId,
    tourSlug: contextTourSlug,
  )) {
    resolvedTourId = _nonEmpty(contextTourId);
    resolvedTourSlug = _nonEmpty(contextTourSlug);
  }

  final eventId =
      isUrlBackedEventId(canonicalEventId)
          ? _nonEmpty(canonicalEventId)
          : resolvedTourId;
  if (eventId == null) return null;
  return (eventId: eventId, tourId: resolvedTourId, tourSlug: resolvedTourSlug);
}

/// Builds the strongest available share destination for a player performance.
///
/// Prefer the canonical event/player route. Some scorecard entry paths retain
/// only the games' tour identity after navigation; use that identity when it
/// is URL-backed rather than hiding Share Link. If no event can be resolved,
/// fall back to the main player profile so a FIDE player is never reduced to
/// image-only sharing.
String? buildPlayerEventShareUrl({
  required bool hasEventContext,
  String? canonicalEventId,
  String? eventName,
  String? tourId,
  String? tourSlug,
  String? contextTourId,
  String? contextTourSlug,
  int? playerFideId,
}) {
  if (hasEventContext) {
    final resolved = resolveUrlBackedEvent(
      canonicalEventId: canonicalEventId,
      tourId: tourId,
      tourSlug: tourSlug,
      contextTourId: contextTourId,
      contextTourSlug: contextTourSlug,
    );
    if (resolved != null) {
      return buildEventShareUrl(
        id: resolved.eventId,
        title: _nonEmpty(eventName) ?? 'ChessEver',
        tourId: resolved.tourId,
        tourSlug: resolved.tourSlug,
        playerFideId: playerFideId,
      );
    }
  }

  return buildPlayerProfileShareUrl(playerFideId);
}

/// Team-event share destination. Archive / display-only identities return
/// null so the preview is image-only rather than a dead `/broadcast/` link.
String? buildTeamEventShareUrl({
  required String teamName,
  String? canonicalEventId,
  String? eventName,
  String? tourId,
  String? tourSlug,
}) {
  final resolved = resolveUrlBackedEvent(
    canonicalEventId: canonicalEventId,
    tourId: tourId,
    tourSlug: tourSlug,
  );
  if (resolved == null) return null;
  return buildEventShareUrl(
    id: resolved.eventId,
    title: _nonEmpty(eventName) ?? teamName,
    tourId: resolved.tourId,
    tourSlug: resolved.tourSlug,
    teamName: teamName,
  );
}
