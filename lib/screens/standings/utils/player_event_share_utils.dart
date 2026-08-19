import 'package:chessever2/screens/player_profile/utils/player_profile_share_utils.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show buildEventShareUrl;

/// Builds the strongest available share destination for a player performance.
///
/// Prefer the canonical event/player route. Some scorecard entry paths retain
/// only the games' tour identity after navigation; use that identity rather
/// than hiding Share Link. If no event can be resolved, fall back to the main
/// player profile so a FIDE player is never reduced to image-only sharing.
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
  String? nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  if (hasEventContext) {
    final canonicalId = nonEmpty(canonicalEventId);
    final resolvedTourId = nonEmpty(tourId) ?? nonEmpty(contextTourId);
    final resolvedTourSlug = nonEmpty(tourSlug) ?? nonEmpty(contextTourSlug);
    final eventId = canonicalId ?? resolvedTourId;

    if (eventId != null) {
      return buildEventShareUrl(
        id: eventId,
        title: nonEmpty(eventName) ?? 'ChessEver',
        tourId:
            resolvedTourId != null && resolvedTourSlug != null
                ? resolvedTourId
                : null,
        tourSlug:
            resolvedTourId != null && resolvedTourSlug != null
                ? resolvedTourSlug
                : null,
        playerFideId: playerFideId,
      );
    }
  }

  return buildPlayerProfileShareUrl(playerFideId);
}
