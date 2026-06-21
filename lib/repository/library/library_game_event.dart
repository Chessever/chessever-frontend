class ResolvedLibraryGameEvent {
  const ResolvedLibraryGameEvent({
    this.eventName,
    this.sourceTournamentId,
    this.tourSlug,
  });

  final String? eventName;
  final String? sourceTournamentId;
  final String? tourSlug;
}

String? chooseLibraryEventName({
  String? canonicalEventName,
  String? metadataEvent,
  String? denormalizedEvent,
  String? site,
  String? tourSlug,
  String? tourId,
  String? whiteName,
  String? blackName,
}) {
  final siteEventName = eventNameFromLibrarySite(site);
  final candidates = <_EventCandidate>[
    _EventCandidate(canonicalEventName),
    _EventCandidate(denormalizedEvent),
    _EventCandidate(metadataEvent),
    _EventCandidate(siteEventName),
    _EventCandidate(tourSlug, humanizeSlug: true),
    _EventCandidate(tourId),
  ];

  for (final candidate in candidates) {
    final value = candidate.value?.trim() ?? '';
    if (!isReadableLibraryEventName(
      value,
      whiteName: whiteName,
      blackName: blackName,
    )) {
      continue;
    }
    return candidate.humanizeSlug ? humanizeLibrarySlug(value) : value;
  }

  return null;
}

/// Display event/tournament name for a gamebase ("ChessEver master database")
/// game row.
///
/// Gamebase stores the raw PGN `Event` header verbatim. For lichess-broadcast-
/// ingested games that header is a round/pairing label — either the separator
/// form "Round 6: A - B" or the separator-less "Game 1: Wee, Yu Heng Lucas John
///  Xu, Zhihan" — while the real tournament lives only in the broadcast `Site`
/// URL. This rejects the pairing and recovers the tournament from the site,
/// falling back to a generic label when nothing readable remains so a raw
/// pairing string never reaches the card. Mirrors how saved-analysis cards
/// resolve their event name via [chooseLibraryEventName].
String resolveGamebaseEventName({
  String? event,
  String? site,
  String? tourId,
  String? whiteName,
  String? blackName,
}) {
  return chooseLibraryEventName(
        metadataEvent: event,
        site: site,
        tourId: tourId,
        whiteName: whiteName,
        blackName: blackName,
      ) ??
      'Gamebase';
}

bool isReadableLibraryEventName(
  String? value, {
  String? whiteName,
  String? blackName,
}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return false;

  final lower = text.toLowerCase();
  if (lower == '?' ||
      lower == 'library' ||
      lower == 'gamebase' ||
      lower == 'search' ||
      lower == 'opening_explorer' ||
      lower == 'saved_analysis') {
    return false;
  }

  if (looksLikeRoundPairingEvent(
    text,
    whiteName: whiteName,
    blackName: blackName,
  )) {
    return false;
  }

  return !looksLikeOpaqueLibraryEventId(text);
}

bool looksLikeRoundPairingEvent(
  String? value, {
  String? whiteName,
  String? blackName,
}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return false;

  final colonIndex = text.indexOf(':');
  final lower = text.toLowerCase();
  final hasRoundPrefix =
      RegExp(
        r'^(round|r|match|game|board|final|semifinal|semi-final|quarterfinal|quarter-final)\b',
        caseSensitive: false,
      ).hasMatch(text) &&
      colonIndex > 0;

  if (colonIndex <= 0) {
    return hasRoundPrefix && _hasVersusSeparator(text);
  }

  final afterColon = text.substring(colonIndex + 1);
  if (hasRoundPrefix && _hasVersusSeparator(afterColon)) return true;

  final normalizedAfter = _normalizeForPairing(afterColon);
  final normalizedWhite = _normalizeForPairing(whiteName ?? '');
  final normalizedBlack = _normalizeForPairing(blackName ?? '');
  final hasBothPlayers =
      normalizedWhite.isNotEmpty &&
      normalizedBlack.isNotEmpty &&
      normalizedAfter.contains(normalizedWhite) &&
      normalizedAfter.contains(normalizedBlack);

  // Both player names appearing after the colon is conclusive proof this is a
  // round/pairing label, not a tournament name — a real event title never
  // embeds both players. This holds even when the two "Last, First" names are
  // joined by spaces instead of a " - "/"vs" separator (e.g. lichess
  // study-chapter imports like "Game 1: Wee, Yu Heng Lucas John  Xu, Zhihan").
  // The old `&& _hasVersusSeparator` gate let those slip through and surface as
  // the card's event name.
  if (hasBothPlayers) return true;

  return lower.startsWith('round ') && _hasVersusSeparator(afterColon);
}

bool looksLikeOpaqueLibraryEventId(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return false;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  if (uuid.hasMatch(text)) return true;

  final objectId = RegExp(r'^[0-9a-f]{24}$', caseSensitive: false);
  if (objectId.hasMatch(text)) return true;

  final longHex = RegExp(r'^[0-9a-f]{12,64}$', caseSensitive: false);
  if (longHex.hasMatch(text)) return true;

  if (!text.contains(RegExp(r'\s')) &&
      !text.contains('-') &&
      !text.contains('_') &&
      text.length >= 6 &&
      text.length <= 16) {
    final hasLower = RegExp(r'[a-z]').hasMatch(text);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(text);
    final hasDigit = RegExp(r'\d').hasMatch(text);
    final isAllCaps = text == text.toUpperCase();

    if (hasDigit && (hasLower || hasUpper)) return true;
    if (hasLower && hasUpper && !isAllCaps) return true;
  }

  if (text.length >= 16 && !text.contains(RegExp(r'\s'))) {
    final alphaCount = RegExp(r'[A-Za-z]').allMatches(text).length;
    final digitCount = RegExp(r'\d').allMatches(text).length;
    final separatorCount = RegExp(r'[-_]').allMatches(text).length;
    final otherCount = text.length - alphaCount - digitCount - separatorCount;
    if (otherCount == 0 && digitCount >= alphaCount) return true;
  }

  return false;
}

String? normalizeSourceTournamentId(String? sourceTournamentId) {
  final value = sourceTournamentId?.trim() ?? '';
  if (value.isEmpty) return null;
  if (looksLikeRoundPairingEvent(value)) return null;
  return value;
}

String humanizeLibrarySlug(String value) {
  final trimmed = value.trim();
  if (!trimmed.contains('-') && !trimmed.contains('_')) return trimmed;

  final words = trimmed
      .split(RegExp(r'[-_]+'))
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return trimmed;

  return words.map(_capitalizeWord).join(' ');
}

String? eventNameFromLibrarySite(String? site) {
  final text = site?.trim() ?? '';
  if (text.isEmpty) return null;

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.toLowerCase() != 'lichess.org') {
    return null;
  }

  final segments = uri.pathSegments;
  final broadcastIndex = segments.indexOf('broadcast');
  if (broadcastIndex < 0 || broadcastIndex + 1 >= segments.length) {
    return null;
  }

  final eventSlug = segments[broadcastIndex + 1].trim();
  if (eventSlug.isEmpty) return null;
  return humanizeLibrarySlug(eventSlug.replaceAll('--', '-'));
}

bool _hasVersusSeparator(String value) {
  return RegExp(r'\s(-|–|—|vs\.?|v)\s', caseSensitive: false).hasMatch(value);
}

String _normalizeForPairing(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _capitalizeWord(String word) {
  if (word.isEmpty) return word;
  if (RegExp(r'^\d+$').hasMatch(word)) return word;
  final lower = word.toLowerCase();
  return '${lower[0].toUpperCase()}${lower.substring(1)}';
}

class _EventCandidate {
  const _EventCandidate(this.value, {this.humanizeSlug = false});

  final String? value;
  final bool humanizeSlug;
}
