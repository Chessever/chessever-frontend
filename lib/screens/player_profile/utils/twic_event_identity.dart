import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/string_utils.dart';

final RegExp _roundTitlePattern = RegExp(
  r'^\s*(?:round|rd|r)\s*\d+[A-Za-z]?(?:\.\d+)?\s*[:\-–—]',
  caseSensitive: false,
);

final RegExp _gamePairingTitlePattern = RegExp(
  r'^\s*(?:.+\|\s*)?(?:game|match|board)\s*\d+[A-Za-z]?(?:\.\d+)?\s*[:\-–—]',
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

const Map<String, String> _monthTokenToSlug = {
  'jan': 'january',
  'january': 'january',
  'feb': 'february',
  'february': 'february',
  'mar': 'march',
  'march': 'march',
  'apr': 'april',
  'april': 'april',
  'may': 'may',
  'jun': 'june',
  'june': 'june',
  'jul': 'july',
  'july': 'july',
  'aug': 'august',
  'august': 'august',
  'sep': 'september',
  'sept': 'september',
  'september': 'september',
  'oct': 'october',
  'october': 'october',
  'nov': 'november',
  'november': 'november',
  'dec': 'december',
  'december': 'december',
};

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

/// Extracts the Lichess broadcast parent slug from a `Site` URL, e.g.
/// `https://lichess.org/broadcast/<slug>/round-7/<roundId>/<chapterId>` ->
/// `<slug>`. This slug is stored verbatim in the ChessEver `tours.slug`
/// column, so it is the reliable key for matching a TWIC/database event to
/// its canonical ChessEver event page. Returns null when [site] is not a
/// recognizable Lichess broadcast URL.
String? broadcastSlugFromSite(String? site) {
  final value = site?.trim();
  if (value == null || value.isEmpty) return null;
  final slug = _lichessBroadcastSitePattern.firstMatch(value)?.group(1)?.trim();
  return (slug == null || slug.isEmpty) ? null : slug;
}

/// Slugify a gamebase event NAME into the form ChessEver stores in
/// `tours.slug` (lichess-style: lowercase, non-alphanumeric runs collapsed to a
/// single hyphen). Gamebase event names are ASCII, so this matches the
/// diacritic-stripped lichess slug — e.g. "Druzynowe Mistrzostwa Polski -
/// Ekstraliga 2026" -> "druzynowe-mistrzostwa-polski-ekstraliga-2026". Used to
/// route a database event to its real ChessEver broadcast when the game `Site`
/// is a venue string (no Lichess URL) rather than a broadcast link.
String eventNameToBroadcastSlug(String name) {
  final dashed = name.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '-',
  );
  return dashed.replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Slug candidates for cloud-broadcast takeover from Gamebase/TWIC event text.
///
/// Most event names slugify directly to `tours.slug`. Chess.com Titled Tuesday
/// rows arrive as names like `2026 Titled Tuesday Blitz June 23`, while the
/// cloud broadcast is stored as `Titled Tuesday June 23 2026`; include that
/// parent-event identity so the cloud source can silently win when present.
List<String> eventNameToBroadcastSlugCandidates(String name) {
  final titledTuesdaySlugs = _titledTuesdayBroadcastSlugs(name);
  final candidates = <String>{
    ...?titledTuesdaySlugs,
    eventNameToBroadcastSlug(name),
  };
  candidates.removeWhere((slug) => slug.trim().isEmpty);
  return candidates.toList(growable: false);
}

List<String>? _titledTuesdayBroadcastSlugs(String name) {
  final normalized =
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  if (normalized.isEmpty) return null;

  final tokens = normalized.split(RegExp(r'\s+'));
  final hasTitled = tokens.contains('titled');
  final hasTuesday = tokens.contains('tuesday') || tokens.contains('tue');
  if (!hasTitled || !hasTuesday) return null;

  final year = tokens.firstWhere(
    (token) => RegExp(r'^(?:19|20)\d{2}$').hasMatch(token),
    orElse: () => '',
  );
  if (year.isEmpty) return null;

  for (var i = 0; i < tokens.length; i++) {
    final month = _monthTokenToSlug[tokens[i]];
    if (month == null) continue;

    final nextDay = i + 1 < tokens.length ? _parseOrdinalDay(tokens[i + 1]) : 0;
    final previousDay = i > 0 ? _parseOrdinalDay(tokens[i - 1]) : 0;
    final day = nextDay > 0 ? nextDay : previousDay;
    if (day <= 0 || day > 31) return null;

    final unpadded = 'titled-tuesday-$month-$day-$year';
    final padded =
        'titled-tuesday-$month-${day.toString().padLeft(2, '0')}-$year';
    return [unpadded, if (padded != unpadded) padded];
  }

  return null;
}

int _parseOrdinalDay(String token) {
  final match = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?$').firstMatch(token);
  if (match == null) return 0;
  return int.tryParse(match.group(1) ?? '') ?? 0;
}

/// Extracts the `Site` header value from a PGN string, or null when the header
/// is absent or a placeholder (`?`). TWIC games carry the canonical Lichess
/// broadcast URL only in this header.
String? siteFromPgn(String? pgn) {
  if (pgn == null || pgn.isEmpty) return null;
  final match = RegExp(r'^\[Site\s+"(.*)"\]$', multiLine: true).firstMatch(pgn);
  final site = match?.group(1)?.trim();
  return (site == null || site.isEmpty || site == '?') ? null : site;
}

/// Extracts the `Event` header value from a PGN string, or null when absent.
String? eventFromPgn(String? pgn) {
  if (pgn == null || pgn.isEmpty) return null;
  final match = RegExp(
    r'^\[Event\s+"(.*)"\]$',
    multiLine: true,
  ).firstMatch(pgn);
  final event = match?.group(1)?.trim();
  return (event == null || event.isEmpty || event == '?') ? null : event;
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
  return _roundTitlePattern.hasMatch(text) ||
      _gamePairingTitlePattern.hasMatch(text);
}

bool _isUsefulEventTitle(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return false;
  if (text == '?' || text == 'Gamebase' || text == 'library') return false;
  return !isTwicRoundDisplayTitle(text);
}

/// True when [value] is a real event title (not empty/placeholder/round or
/// pairing label) and can be trusted as a canonical grouping key.
bool isUsefulTwicEventTitle(String? value) => _isUsefulEventTitle(value);

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
  final fromSite = eventTitleFromBroadcastSite(site);

  if (fromSite != null) return fromSite;
  if (_isUsefulEventTitle(pgn)) return pgn!;
  if (_isUsefulEventTitle(slug)) return slug!;
  if (_isUsefulEventTitle(id)) return id!;

  // PGN Event / tour fields were only round/pairing labels, or no Lichess
  // broadcast URL was available.
  if (pgn != null && pgn.isNotEmpty && pgn != '?') return pgn;
  if (slug != null && slug.isNotEmpty) return slug;
  if (id != null && id.isNotEmpty) return id;
  return fallback;
}

String twicCanonicalEventKeyForGame(GamesTourModel game) {
  final title = twicCanonicalEventTitleForGame(game);
  return title
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

String twicCanonicalEventTitleForGame(GamesTourModel game) {
  // Player-profile TWIC games carry the gamebase canonical event name
  // (group-broadcast level, e.g. "Lankaran Open 2026") in their Event header.
  // It must win over the Site URL: the Site slug is per-tour/section
  // (`lankaran-open-2026-group-a`, `...-group-b`, `...-rapid`), which splits
  // one event into several cards that all resolve to the same display name.
  final pgnEvent = eventFromPgn(game.pgn);
  if (_isUsefulEventTitle(pgnEvent)) return pgnEvent!;

  return preferredTwicEventTitle(
    pgnEvent: pgnEvent,
    tourSlug: game.tourSlug,
    tourId: game.tourId,
    site: siteFromPgn(game.pgn),
    fallback: game.gameId,
  );
}
