import 'package:chessever2/repository/supabase/tour/tour.dart';

class LogicalKnockoutStage {
  const LogicalKnockoutStage({
    required this.key,
    required this.label,
    required this.sortOrder,
  });

  final String key;
  final String label;
  final int sortOrder;
}

class KnockoutTourStageDescriptor {
  const KnockoutTourStageDescriptor({
    required this.eventRoot,
    required this.lane,
    required this.stage,
  });

  final String eventRoot;
  final String lane;
  final LogicalKnockoutStage? stage;
}

/// Resolves a stored Lichess round into the logical elimination stage it
/// belongs to. Round names are authoritative; slugs and [tourName] are only
/// supporting evidence.
LogicalKnockoutStage? resolveLogicalKnockoutStage(
  String name,
  String slug, {
  String? tourName,
}) {
  final cleanName = _clean(name);

  if (cleanName.isNotEmpty) {
    final piped = RegExp(
      r'^(.+?)\s*\|\s*(?:game|leg|tie[ -]?breaks?|rapid|blitz|armageddon)\b.*$',
      caseSensitive: false,
    ).firstMatch(cleanName);
    if (piped != null) {
      return _stageFromDisplayText(piped.group(1)!);
    }

    final numberedRound = RegExp(
      r'^round\s+(\d+)(?:[._]\d+)?(?:\s*(?:\||[-–—])?\s*(?:game|leg|tie[ -]?breaks?|rapid|blitz|armageddon)\b.*)?$',
      caseSensitive: false,
    ).firstMatch(cleanName);
    if (numberedRound != null) {
      return _roundStage(int.parse(numberedRound.group(1)!));
    }

    final namedStage = _recognizedStage(cleanName);
    if (namedStage != null) return namedStage;
  }

  // Matchup-labeled stages: Lichess names each knockout pairing round after the
  // stage AND its players ("Round of 16: Ju Wenjun vs Pham Le Thao Nguyen",
  // slug "round-of-16-ju-wenjun-vs-pham-le-thao-nguyen"). The trailing pairing
  // defeats the end-anchored recognizers above, so read the stage from the
  // leading token whenever a "vs" pairing follows it.
  final cleanSlug = _clean(slug).toLowerCase();
  final matchupStage = _stageFromMatchupPairing(cleanName, cleanSlug);
  if (matchupStage != null) return matchupStage;

  if (cleanSlug.isNotEmpty) {
    final stageSlug = cleanSlug
        .split('--')
        .first
        .replaceFirst(RegExp(r'^stage-'), '');
    if (stageSlug != cleanSlug || !_isGenericLegSlug(stageSlug)) {
      final slugRound = RegExp(
        r'^round-(\d+)(?:[-._]\d+)?$',
        caseSensitive: false,
      ).firstMatch(stageSlug);
      if (slugRound != null) {
        return _roundStage(int.parse(slugRound.group(1)!));
      }

      final fromSlug = _recognizedStage(
        stageSlug.replaceAll(RegExp(r'[-_]+'), ' '),
      );
      if (fromSlug != null) return fromSlug;
    }
  }

  if (tourName != null &&
      (_isGenericLegName(cleanName) || _isGenericLegSlug(cleanSlug))) {
    return parseKnockoutTourStageDescriptor(tourName).stage;
  }

  return null;
}

/// Known stage token anchored at the START of a round name, mirroring the
/// tokens [_recognizedStage] understands. Used to read the stage off a
/// matchup-labeled round ("Round of 16: A vs B").
final RegExp _leadingStageName = RegExp(
  r'^(round\s+of\s+\d+'
  r'|last\s+\d+'
  r'|round\s+\d+(?:[._]\d+)?'
  r'|quarter[ -]?finals?'
  r'|semi[ -]?finals?'
  r'|(?:third[ -]?place|bronze)(?:[ -]?match)?'
  r'|finals?)\b',
  caseSensitive: false,
);

/// Same token anchored at the START of a slug, requiring a `-` after it so a
/// pairing ("round-of-16-a-vs-b") — not a bare stage slug — is what follows.
final RegExp _leadingStageSlug = RegExp(
  r'^(round-of-\d+'
  r'|last-\d+'
  r'|round-\d+(?:[-._]\d+)?'
  r'|quarter-?finals?'
  r'|semi-?finals?'
  r'|(?:third-place|bronze)(?:-match)?'
  r'|finals?)(?=-)',
  caseSensitive: false,
);

/// A "vs" pairing separator (vs, vs., v, v.) between two players.
final RegExp _matchupSeparator = RegExp(r'\bvs?\.?\b', caseSensitive: false);

/// Resolves matchup-labeled rounds — "<Stage>: A vs B" / "<stage>-a-vs-b" —
/// where the pairing appended after the stage defeats the end-anchored
/// recognizers. Only fires when a pairing actually follows the leading stage
/// token, so plain stage rounds keep flowing through the stricter parsers.
LogicalKnockoutStage? _stageFromMatchupPairing(String name, String slug) {
  if (name.isNotEmpty) {
    final match = _leadingStageName.firstMatch(name);
    if (match != null &&
        _matchupSeparator.hasMatch(name.substring(match.end))) {
      final stage = _recognizedStage(match.group(1)!);
      if (stage != null) return stage;
    }
  }

  if (slug.contains('-vs-')) {
    final match = _leadingStageSlug.firstMatch(slug);
    if (match != null) {
      final stage = _recognizedStage(
        match.group(1)!.replaceAll(RegExp(r'[-_]+'), ' '),
      );
      if (stage != null) return stage;
    }
  }

  return null;
}

KnockoutTourStageDescriptor parseKnockoutTourStageDescriptor(String tourName) {
  final parts =
      tourName.split('|').map(_clean).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return const KnockoutTourStageDescriptor(
      eventRoot: '',
      lane: '',
      stage: null,
    );
  }

  if (parts.length == 1) {
    final extracted = _stageSuffix(parts.single);
    if (extracted == null || extracted.prefix.isEmpty) {
      return KnockoutTourStageDescriptor(
        eventRoot: parts.single,
        lane: '',
        stage: extracted?.stage,
      );
    }
    return KnockoutTourStageDescriptor(
      eventRoot: extracted.prefix,
      lane: '',
      stage: extracted.stage,
    );
  }

  final eventRoot = parts.first;
  final remainder = parts.sublist(1);
  final extracted = _stageSuffix(remainder.last);
  if (extracted != null) {
    final laneParts = <String>[
      ...remainder.take(remainder.length - 1),
      if (extracted.prefix.isNotEmpty) extracted.prefix,
    ];
    return KnockoutTourStageDescriptor(
      eventRoot: eventRoot,
      lane: _normalizeLane(laneParts.join(' ')),
      stage: extracted.stage,
    );
  }

  return KnockoutTourStageDescriptor(
    eventRoot: eventRoot,
    lane: _normalizeLane(remainder.join(' ')),
    stage: null,
  );
}

String resolveKnockoutCategoryLane(String tourName) =>
    parseKnockoutTourStageDescriptor(tourName).lane;

/// Returns the selected tour and same-event sibling stages in the selected
/// category lane. Tours with a different group broadcast, event root, or lane
/// are excluded.
List<Tour> filterKnockoutSiblingTours({
  required Tour selectedTour,
  required Iterable<Tour> siblingTours,
}) {
  final selected = parseKnockoutTourStageDescriptor(selectedTour.name);
  final selectedRoot = _normalizeKey(selected.eventRoot);
  final byId = <String, Tour>{selectedTour.id: selectedTour};
  final selectedGroupId = selectedTour.groupBroadcastId;

  for (final tour in siblingTours) {
    if (tour.id == selectedTour.id) continue;
    // Without a broadcast-group identity there is no trustworthy evidence
    // that a same-named tour is another stage of this event.
    if (selectedGroupId == null ||
        tour.groupBroadcastId != selectedGroupId ||
        !_isIndividualKnockoutCandidate(tour)) {
      continue;
    }

    final candidate = parseKnockoutTourStageDescriptor(tour.name);
    if (_normalizeKey(candidate.eventRoot) != selectedRoot ||
        candidate.lane != selected.lane ||
        candidate.stage == null) {
      continue;
    }
    byId[tour.id] = tour;
  }

  final result = byId.values.toList();
  result.sort((a, b) {
    final aStage = parseKnockoutTourStageDescriptor(a.name).stage;
    final bStage = parseKnockoutTourStageDescriptor(b.name).stage;
    if (aStage != null && bStage != null) {
      final semantic = aStage.sortOrder.compareTo(bStage.sortOrder);
      if (semantic != 0) return semantic;
    } else if (aStage != null) {
      return -1;
    } else if (bStage != null) {
      return 1;
    }
    final aDate = a.dates.isEmpty ? a.createdAt : a.dates.first;
    final bDate = b.dates.isEmpty ? b.createdAt : b.dates.first;
    final chronological = aDate.compareTo(bDate);
    return chronological != 0 ? chronological : a.id.compareTo(b.id);
  });
  return List.unmodifiable(result);
}

bool _isIndividualKnockoutCandidate(Tour tour) {
  final format = tour.info.format?.trim().toLowerCase() ?? '';
  if (format.contains('team')) return false;
  if (format.contains('swiss') ||
      format.contains('round robin') ||
      format.contains('round-robin') ||
      format.contains('league')) {
    return false;
  }
  // Stage names and exact broadcast-group identity remain the primary signal
  // because several trusted Lichess knockout feeds omit format metadata.
  return true;
}

LogicalKnockoutStage _stageFromDisplayText(String value) {
  final cleanValue = _clean(value);
  return _recognizedStage(cleanValue) ??
      LogicalKnockoutStage(
        key: _normalizeKey(cleanValue),
        label: _titleCaseIfNeeded(cleanValue),
        sortOrder: 2000,
      );
}

LogicalKnockoutStage _roundStage(int number) => LogicalKnockoutStage(
  key: 'round-$number',
  label: 'Round $number',
  sortOrder: 1000 + number,
);

LogicalKnockoutStage? _recognizedStage(String value) {
  // Tiebreaks and other deciding legs ("Round 4.Tiebreaks", "Semifinals Rapid
  // 2", "round-4tiebreaks") are extra games inside an existing stage, never a
  // stage of their own. Fold them back into the parent round so the decider
  // that settles a place — the final for first, the bronze match for third —
  // lands in the right bracket slot instead of a stray "Other pairings" column.
  final cleanValue = _stripTrailingLegQualifiers(_clean(value));

  final roundOf = RegExp(
    r'^round\s+of\s+(\d+)$',
    caseSensitive: false,
  ).firstMatch(cleanValue);
  if (roundOf != null) {
    final size = int.parse(roundOf.group(1)!);
    return LogicalKnockoutStage(
      key: 'round-of-$size',
      label: 'Round of $size',
      sortOrder: 3000 - size,
    );
  }

  final last = RegExp(
    r'^last\s+(\d+)$',
    caseSensitive: false,
  ).firstMatch(cleanValue);
  if (last != null) {
    final size = int.parse(last.group(1)!);
    return LogicalKnockoutStage(
      key: 'round-of-$size',
      label: 'Round of $size',
      sortOrder: 3000 - size,
    );
  }

  final round = RegExp(
    r'^round\s+(\d+)(?:[._]\d+)?$',
    caseSensitive: false,
  ).firstMatch(cleanValue);
  if (round != null) return _roundStage(int.parse(round.group(1)!));

  if (RegExp(
    r'^quarter[ -]?finals?$',
    caseSensitive: false,
  ).hasMatch(cleanValue)) {
    return const LogicalKnockoutStage(
      key: 'quarterfinals',
      label: 'Quarterfinals',
      sortOrder: 4000,
    );
  }
  if (RegExp(
    r'^semi[ -]?finals?$',
    caseSensitive: false,
  ).hasMatch(cleanValue)) {
    return const LogicalKnockoutStage(
      key: 'semifinals',
      label: 'Semifinals',
      sortOrder: 5000,
    );
  }
  if (RegExp(
    r'^(?:third[ -]?place|bronze)(?:[ -]?match)?$',
    caseSensitive: false,
  ).hasMatch(cleanValue)) {
    return const LogicalKnockoutStage(
      key: 'third-place',
      label: 'Third place',
      sortOrder: 6000,
    );
  }
  if (RegExp(r'^finals?$', caseSensitive: false).hasMatch(cleanValue)) {
    return const LogicalKnockoutStage(
      key: 'finals',
      label: 'Finals',
      sortOrder: 7000,
    );
  }
  return null;
}

_ExtractedStage? _stageSuffix(String value) {
  final patterns = <RegExp>[
    RegExp(r'\bround\s+of\s+\d+$', caseSensitive: false),
    RegExp(r'\blast\s+\d+$', caseSensitive: false),
    RegExp(r'\bround\s+\d+(?:[._]\d+)?$', caseSensitive: false),
    RegExp(r'\bquarter[ -]?finals?$', caseSensitive: false),
    RegExp(r'\bsemi[ -]?finals?$', caseSensitive: false),
    RegExp(
      r'\b(?:third[ -]?place|bronze)(?:[ -]?match)?$',
      caseSensitive: false,
    ),
    RegExp(r'\bfinals?$', caseSensitive: false),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(value);
    if (match == null) continue;
    final stage = _recognizedStage(match.group(0)!);
    if (stage == null) continue;
    return _ExtractedStage(
      prefix: _clean(value.substring(0, match.start)),
      stage: stage,
    );
  }
  return null;
}

bool _isGenericLegName(String value) => RegExp(
  r'^(?:game|leg|tie[ -]?breaks?|rapid|blitz|armageddon)\b',
  caseSensitive: false,
).hasMatch(value);

bool _isGenericLegSlug(String value) => RegExp(
  r'^(?:game|leg|tie-?breaks?|rapid|blitz|armageddon)(?:-|$)',
  caseSensitive: false,
).hasMatch(value);

/// A deciding-leg suffix appended to a stage label. Lichess tacks the tiebreak
/// or speed-chess playoff that resolves a match onto the stage round name
/// ("Round 4.Tiebreaks", "Semifinals - Rapid 2", "round-4tiebreaks"). These are
/// additional games within the stage, so they are stripped before stage
/// recognition rather than treated as a separate bracket column.
final RegExp _trailingLegQualifier = RegExp(
  r'[\s.|:_/–—-]*'
  r'(?:tie[ -]?breaks?|play[ -]?offs?|sudden[ -]?death|armageddon|rapid|blitz|bullet|game|leg)'
  r'(?:[\s.|:_/–—-]*\d+)*$',
  caseSensitive: false,
);

/// Repeatedly removes trailing leg qualifiers so compound deciders such as
/// "Round 3 Tiebreak Rapid 1" collapse down to the parent stage ("Round 3").
/// Only strips when a stage token would remain, so a bare "Tiebreaks" round —
/// which carries no evidence of which stage it settles — is left unresolved.
String _stripTrailingLegQualifiers(String value) {
  var result = value;
  while (true) {
    final next = _clean(result.replaceFirst(_trailingLegQualifier, ''));
    if (next.isEmpty || next == result) return result;
    result = next;
  }
}

String _clean(String value) => value
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'^[\s|:–—-]+|[\s|:–—-]+$'), '');

String _normalizeLane(String value) => _clean(value)
    .toLowerCase()
    .replaceAll(RegExp(r'[._]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

String _normalizeKey(String value) => _clean(value)
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String _titleCaseIfNeeded(String value) {
  if (value != value.toLowerCase()) return value;
  return value
      .split(' ')
      .map(
        (word) =>
            word.isEmpty
                ? word
                : '${word.substring(0, 1).toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

class _ExtractedStage {
  const _ExtractedStage({required this.prefix, required this.stage});

  final String prefix;
  final LogicalKnockoutStage stage;
}
