/// Broad chess time-control buckets, kept identical to the desktop app's
/// `time_control_classifier.dart` so both index a game into the same clock.
///
/// PGN `TimeControl` tags are stored in seconds (`300+2`, `40/7200:3600`),
/// while broadcast metadata often stores free-form minute text (`15+10`,
/// `G/25;+10`). Keep those parsing contexts separate so ratings are not mixed
/// across incompatible clocks.
String? classifyTimeControlCategory(
  Object? timeControl, {
  Object? event,
  Object? site,
  Object? source,
}) {
  return classifyPgnTimeControlCategory(
        timeControl,
        site: site,
        source: source,
      ) ??
      inferTimeControlCategoryFromEvent(event, site, source: source);
}

String? classifyPgnTimeControlCategory(
  Object? value, {
  Object? site,
  Object? source,
}) {
  final raw = _clean(value);
  if (raw == null) return null;

  // Numeric PGN clocks are overwhelmingly the hot path during large imports.
  // Avoid running the free-form word regexes for every ordinary game.
  if (!_startsWithNumber(raw)) {
    final canonical = _canonicalWordCategory(raw);
    if (canonical != null) return canonical;
  }

  final firstStage = raw.split(':').first.trim();
  if (firstStage.isEmpty) return null;
  final baseSegment =
      firstStage.contains('/') ? firstStage.split('/').last.trim() : firstStage;
  final plusParts = baseSegment.split('+');
  if (plusParts.isEmpty) return null;

  final baseSeconds = double.tryParse(plusParts.first.trim());
  if (baseSeconds == null || baseSeconds <= 0) {
    return classifyFreeformTimeControlCategory(value);
  }

  final incrementSeconds =
      plusParts.length > 1 ? double.tryParse(plusParts[1].trim()) ?? 0 : 0;
  final safeIncrement = incrementSeconds > 0 ? incrementSeconds : 0;
  return _classifyEffectiveSeconds(
    baseSeconds + safeIncrement * 40,
    source: _providerFor(site: site, source: source),
  );
}

String? classifyFreeformTimeControlCategory(Object? value) {
  final raw = _clean(value);
  if (raw == null) return null;

  final canonical = _canonicalWordCategory(raw);
  if (canonical != null) return canonical;

  final baseMinutes = _freeformBaseMinutes(raw);
  if (baseMinutes == null || baseMinutes <= 0) return null;
  return _classifyBaseMinutes(baseMinutes);
}

String? inferTimeControlCategoryFromEvent(
  Object? event,
  Object? site, {
  Object? source,
}) {
  final rawEvent = _clean(event);
  final rawSite = _clean(site) ?? '';
  final rawSource = _clean(source) ?? '';
  if (rawEvent == null) {
    return _sourceDefaultCategory('$rawSite $rawSource');
  }

  if (rawEvent.contains('checkmate covid rematch')) return 'blitz';
  if (rawEvent.contains('titled') && rawEvent.contains('tue')) {
    return 'blitz';
  }
  if (rawEvent.contains('titled arena')) return 'blitz';
  if (rawEvent.contains('speedchess') || rawEvent.contains('speed chess')) {
    return 'blitz';
  }
  if (rawEvent.contains('wscc')) return 'blitz';
  if (rawEvent.contains('ultrabullet') ||
      rawEvent.contains('ultra bullet') ||
      rawEvent.contains('ultra-bullet')) {
    return 'ultrabullet';
  }
  if (rawEvent.contains('correspondence')) return 'correspondence';
  if (rawEvent.contains('bullet')) return 'bullet';
  if (rawEvent.contains('blitz')) return 'blitz';
  if (rawEvent.contains('armageddon')) return 'blitz';
  if (rawEvent.contains('online olym')) return 'rapid';
  if (rawEvent.startsWith('euro online')) return 'rapid';
  if (rawEvent.startsWith('world corporate')) return 'rapid';
  if (rawEvent.contains('rapid')) return 'rapid';
  if (rawEvent.contains('pro league')) return 'rapid';
  if (rawEvent.contains('gran canaria online')) return 'rapid';
  if (rawEvent.contains('online') && rawEvent.contains('women')) return 'rapid';

  final embeddedMinutes = _freeformBaseMinutes(rawEvent);
  if (embeddedMinutes != null) return _classifyBaseMinutes(embeddedMinutes);

  final isChessCom = _containsChessCom('$rawSite $rawSource');
  if (!isChessCom) return _sourceDefaultCategory('$rawSite $rawSource');

  if (rawEvent.startsWith('chess.com speed')) return 'blitz';
  if (rawEvent.contains('women') && rawEvent.contains('speed')) return 'blitz';
  if (rawEvent.contains('junior speed')) return 'blitz';
  if (rawEvent.contains('speed play-in') ||
      rawEvent.contains('speed play in')) {
    return 'blitz';
  }
  if (_threeZeroEventPattern.hasMatch(rawEvent)) {
    return 'blitz';
  }
  if (rawEvent.startsWith('chess.com rcc')) return 'rapid';

  final rapidish =
      rawEvent.contains('play-in') ||
      rawEvent.contains('play in') ||
      rawEvent.contains('masters') ||
      rawEvent.contains('cup') ||
      rawEvent.contains('classic');
  final fast =
      rawEvent.contains('blitz') ||
      rawEvent.contains('bullet') ||
      rawEvent.contains('speed');
  return rapidish && !fast
      ? 'rapid'
      : _sourceDefaultCategory('$rawSite $rawSource');
}

/// ChessEver's player export is the FIDE/OTB database source. Those PGNs
/// frequently omit `TimeControl`, so provenance is the only reliable fallback
/// after the event-name heuristics above have ruled out rapid/blitz events.
String? _sourceDefaultCategory(String rawSite) =>
    rawSite.contains('chessever') ? 'classical' : null;

String? _clean(Object? value) {
  final raw = value?.toString().trim().toLowerCase();
  if (raw == null || raw.isEmpty || raw == '?' || raw == '-' || raw == '*') {
    return null;
  }
  return raw;
}

enum _TimeControlProvider { generic, chessCom, lichess }

_TimeControlProvider _providerFor({Object? site, Object? source}) {
  final rawSite = _clean(site) ?? '';
  if (_containsLichess(rawSite)) return _TimeControlProvider.lichess;
  if (_containsChessCom(rawSite)) return _TimeControlProvider.chessCom;

  final rawSource = _clean(source) ?? '';
  if (_containsLichess(rawSource)) return _TimeControlProvider.lichess;
  if (_containsChessCom(rawSource)) return _TimeControlProvider.chessCom;
  return _TimeControlProvider.generic;
}

bool _containsLichess(String raw) =>
    raw.contains('lichess.org') || raw.contains('lichess');

bool _containsChessCom(String raw) =>
    raw.contains('chess.com') || raw.contains('chesscom');

bool _startsWithNumber(String raw) {
  if (raw.isEmpty) return false;
  final first = raw.codeUnitAt(0);
  return first >= 0x30 && first <= 0x39;
}

final RegExp _classicalWordPattern = RegExp(
  r'\b(classical|standard|classic)\b',
);
final RegExp _rapidWordPattern = RegExp(r'\brapid\b');
final RegExp _ultraBulletWordPattern = RegExp(r'\bultra[ _-]?bullet\b');
final RegExp _bulletWordPattern = RegExp(r'\bbullet\b');
final RegExp _blitzWordPattern = RegExp(r'\bblitz\b');
final RegExp _hoursPattern = RegExp(r'\b(\d+)\s*h\s*(\d+)?');
final List<RegExp> _freeformMinutePatterns = <RegExp>[
  RegExp(r'\b\d+\s*x\s*(\d+(?:[.,]\d+)?)'),
  RegExp(r'\bg\s*/?\s*(\d+(?:[.,]\d+)?)'),
  RegExp(r"\b(\d+(?:[.,]\d+)?)\s*(?:min|m\b|'|\+)"),
];
final RegExp _threeZeroEventPattern = RegExp(r'(^|[^0-9])3-0([^0-9]|$)');

String? _canonicalWordCategory(String raw) {
  if (raw == 'correspondence' ||
      raw == 'timecontrol.correspondence' ||
      raw == 'time_control.correspondence') {
    return 'correspondence';
  }
  if (raw == 'ultrabullet' ||
      raw == 'ultra_bullet' ||
      raw == 'ultra-bullet' ||
      raw == 'ultra bullet') {
    return 'ultrabullet';
  }
  if (raw == 'bullet' ||
      raw == 'timecontrol.bullet' ||
      raw == 'time_control.bullet') {
    return 'bullet';
  }
  if (raw == 'b' || raw == 'timecontrol.blitz' || raw == 'time_control.blitz') {
    return 'blitz';
  }
  if (raw == 'r' || raw == 'timecontrol.rapid' || raw == 'time_control.rapid') {
    return 'rapid';
  }
  if (raw == 'c' ||
      raw == 'timecontrol.classical' ||
      raw == 'time_control.classical' ||
      raw == 'standard') {
    return 'classical';
  }

  if (_classicalWordPattern.hasMatch(raw)) {
    return 'classical';
  }
  if (_rapidWordPattern.hasMatch(raw)) return 'rapid';
  if (_ultraBulletWordPattern.hasMatch(raw)) return 'ultrabullet';
  if (_bulletWordPattern.hasMatch(raw)) return 'bullet';
  if (_blitzWordPattern.hasMatch(raw)) return 'blitz';
  return null;
}

double? _freeformBaseMinutes(String raw) {
  final hourMatch = _hoursPattern.firstMatch(raw);
  if (hourMatch != null) {
    final hours = double.tryParse(hourMatch.group(1) ?? '');
    if (hours == null) return null;
    final minutes = double.tryParse(hourMatch.group(2) ?? '') ?? 0;
    return hours * 60 + minutes;
  }

  for (final pattern in _freeformMinutePatterns) {
    final match = pattern.firstMatch(raw);
    if (match == null) continue;
    return double.tryParse((match.group(1) ?? '').replaceAll(',', '.'));
  }
  return null;
}

String _classifyBaseMinutes(double baseMinutes) {
  if (baseMinutes < 10) return 'blitz';
  if (baseMinutes < 60) return 'rapid';
  return 'classical';
}

String _classifyEffectiveSeconds(
  double effectiveSeconds, {
  required _TimeControlProvider source,
}) {
  if (source == _TimeControlProvider.lichess) {
    // Mirrors scalachess Speed.byTime. Lichess estimates a 40-move game and
    // deliberately uses an earlier Rapid/Classical boundary than Chess.com.
    if (effectiveSeconds < 30) return 'ultrabullet';
    if (effectiveSeconds < 180) return 'bullet';
    if (effectiveSeconds < 480) return 'blitz';
    if (effectiveSeconds < 1500) return 'rapid';
    if (effectiveSeconds < 21600) return 'classical';
    return 'correspondence';
  }
  if (source == _TimeControlProvider.chessCom) {
    // Chess.com uses the 40-move estimate for its rated pools: under 3 minutes
    // is bullet, 3 to under 10 is blitz, and 10 minutes is already rapid.
    // Keep the 30-second ultra-bullet subset distinct as a ChessEver facet.
    if (effectiveSeconds <= 30) return 'ultrabullet';
    if (effectiveSeconds < 180) return 'bullet';
    if (effectiveSeconds < 600) return 'blitz';
    if (effectiveSeconds <= 3600) return 'rapid';
    return 'classical';
  }

  // Preserve the established Gamebase buckets for manual, FIDE, and other
  // generic PGNs. Provider-specific Bullet facets require provider evidence.
  if (effectiveSeconds <= 600) return 'blitz';
  if (effectiveSeconds <= 3600) return 'rapid';
  return 'classical';
}
