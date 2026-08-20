import 'package:chessever2/screens/player_profile/utils/player_profile_share_utils.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show buildEventShareUrl;

/// Sentinels that gamebase/TWIC rows put in `tourId` when there is no real
/// broadcast identity — never treat these as URL path segments.
const _kDisplayOnlyTourIds = {'Gamebase', 'Miniatures'};

/// True when a games-context tour pair is safe to put in `/broadcast/...`.
///
/// Canonical `aboutModel` / broadcast fields are already URL-backed. Context
/// copied off a scorecard game can be a display label (event name in
/// `tourSlug`, invented `Gamebase` id) — reject those so Share Link falls back
/// to the player profile instead of a dead route.
bool isUrlBackedTourIdentity({String? tourId, String? tourSlug}) {
  final id = tourId?.trim();
  final slug = tourSlug?.trim();
  if (id == null || id.isEmpty || slug == null || slug.isEmpty) return false;
  if (_kDisplayOnlyTourIds.contains(id)) return false;
  if (id.contains(' ')) return false;
  return StringUtils.looksLikeUrlSlug(slug);
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
  String? nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  if (hasEventContext) {
    final canonicalId = nonEmpty(canonicalEventId);
    final aboutTourId = nonEmpty(tourId);
    final aboutTourSlug = nonEmpty(tourSlug);

    String? resolvedTourId;
    String? resolvedTourSlug;
    if (aboutTourId != null && aboutTourSlug != null) {
      // aboutModel / broadcast pairs come from the API — always URL-backed.
      resolvedTourId = aboutTourId;
      resolvedTourSlug = aboutTourSlug;
    } else if (isUrlBackedTourIdentity(
      tourId: contextTourId,
      tourSlug: contextTourSlug,
    )) {
      resolvedTourId = nonEmpty(contextTourId);
      resolvedTourSlug = nonEmpty(contextTourSlug);
    }

    final eventId = canonicalId ?? resolvedTourId;
    if (eventId != null) {
      return buildEventShareUrl(
        id: eventId,
        title: nonEmpty(eventName) ?? 'ChessEver',
        tourId: resolvedTourId,
        tourSlug: resolvedTourSlug,
        playerFideId: playerFideId,
      );
    }
  }

  return buildPlayerProfileShareUrl(playerFideId);
}
