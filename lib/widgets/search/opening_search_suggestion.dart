import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';

const int minimumOpeningSearchCharacters = 3;

/// A locally indexed, hierarchy-aware ECO destination shown alongside remote
/// search results and in the vertical filter browser.
class OpeningSearchSuggestion {
  const OpeningSearchSuggestion({
    required this.id,
    required this.filter,
    required this.title,
    required this.fullTitle,
    required this.subtitle,
    required this.hierarchyLabel,
    required this.score,
    required this.movePath,
    required this.isAggregate,
  });

  /// Stable per-result identity. Named lines may intentionally share the same
  /// selectable ECO code, so the filter code alone is not a valid widget key.
  final String id;
  final GameEcoFilter filter;

  /// The root opening name shown beside the ECO code.
  final String title;
  final String fullTitle;

  /// Non-repeating supporting text. Named CSV lines use their child path here,
  /// e.g. "Wing gambit › Carlsbad variation".
  final String subtitle;
  final String hierarchyLabel;
  final int score;
  final List<String> movePath;
  final bool isAggregate;

  bool get isFamily => filter.isFamily;

  String get codeLabel =>
      EcoOpenings.getFamily(filter.code)?.rangeLabel ?? filter.displayText;

  OpeningSearchSelection get selection => OpeningSearchSelection(
    filter: filter,
    hierarchyLabel: hierarchyLabel,
    movePath: movePath,
    isAggregate: isAggregate,
  );

  bool isParentOf(OpeningSearchSuggestion other) {
    if (id == other.id || hierarchyLabel.isEmpty) return false;
    return other.hierarchyLabel.startsWith('$hierarchyLabel ›');
  }
}

/// The opening destination carried beyond the search UI.
///
/// [filter] is the database truth. The remaining fields preserve which named
/// line the user actually tapped so a smart event can explain that selection
/// even though Supabase matches games by ECO classification.
class OpeningSearchSelection {
  const OpeningSearchSelection({
    required this.filter,
    required this.hierarchyLabel,
    required this.movePath,
    required this.isAggregate,
  });

  factory OpeningSearchSelection.forFilter(GameEcoFilter filter) {
    final family = EcoOpenings.getFamily(filter.code);
    final record =
        family == null
            ? EcoOpenings.canonicalRecordForCode(filter.code!)
            : null;
    return OpeningSearchSelection(
      filter: filter,
      hierarchyLabel:
          family?.name ??
          record?.name ??
          filter.openingName ??
          filter.displayText,
      movePath: EcoOpenings.moveTokens(family?.moves ?? record?.moves ?? ''),
      isAggregate: true,
    );
  }

  final GameEcoFilter filter;
  final String hierarchyLabel;
  final List<String> movePath;
  final bool isAggregate;

  String get codeLabel =>
      EcoOpenings.getFamily(filter.code)?.rangeLabel ?? filter.displayText;
}

/// Searches all 1,813 bundled source rows. Each matched named line remains a
/// visible result even when several lines share one selectable ECO code. The
/// complete ancestry is carried inside that result rather than injected as a
/// row of broad, weakly related destinations before it.
List<OpeningSearchSuggestion> searchOpeningSuggestions(
  String rawQuery, {
  int? limit,
}) {
  final query = _normalizeSearchText(rawQuery);
  final exactFamily = EcoOpenings.getFamily(rawQuery);
  final exactFamilyQuery = exactFamily != null;
  if ((!exactFamilyQuery &&
          _searchCharacterCount(query) < minimumOpeningSearchCharacters) ||
      (limit != null && limit <= 0)) {
    return const [];
  }

  final candidates = <String, _OpeningCandidate>{};

  void consider(_OpeningCandidate candidate) {
    final existing = candidates[candidate.id];
    if (existing == null || candidate.isBetterThan(existing)) {
      candidates[candidate.id] = candidate;
    }
  }

  for (final family in EcoOpenings.families) {
    final score = _matchScore(
      query: query,
      code: _normalizeSearchText('${family.id} ${family.rangeLabel}'),
      name: _normalizeSearchText(family.name),
      moves: _normalizeMoves(family.moves ?? ''),
    );
    if (score == null) continue;
    // A named range is a stronger destination than an incidental occurrence
    // of the same words inside one exact-code variation.
    consider(_OpeningCandidate.forFamily(family, score: score + 700));
  }

  final matchedRecordCodes = <String>{};
  for (final record in EcoOpenings.exactCatalog) {
    final score = _matchScore(
      query: query,
      code: record.code.toLowerCase(),
      name: _normalizeSearchText(record.name),
      moves: _normalizeMoves(record.moves),
    );
    if (score == null) continue;
    matchedRecordCodes.add(record.code);
    consider(_OpeningCandidate.forRecord(record, score: score));
  }

  // Curated code labels remain useful aliases when the source uses older
  // spelling or a more specific line name for the same code.
  for (final entry in EcoOpenings.codeToName.entries) {
    if (matchedRecordCodes.contains(entry.key)) continue;
    final score = _matchScore(
      query: query,
      code: entry.key.toLowerCase(),
      name: _normalizeSearchText(entry.value),
      moves: '',
    );
    if (score == null) continue;
    final record = EcoOpenings.canonicalRecordForCode(entry.key);
    if (record == null) continue;
    consider(
      _OpeningCandidate.forRecord(
        record,
        score: score - 5,
        titleOverride: entry.value,
        aggregate: true,
      ),
    );
  }

  final suggestions = candidates.values
      .map(_buildSuggestion)
      .toList(growable: false);
  final exactCodeQuery = RegExp(r'^[a-e][0-9]{2}$').hasMatch(query);
  final exactDestinationId =
      exactFamily?.id.toLowerCase() ?? (exactCodeQuery ? query : null);
  suggestions.sort((left, right) {
    if (exactDestinationId != null) {
      final leftExact = left.filter.code?.toLowerCase() == exactDestinationId;
      final rightExact = right.filter.code?.toLowerCase() == exactDestinationId;
      if (leftExact != rightExact) return leftExact ? -1 : 1;
    }
    final scoreOrder = right.score.compareTo(left.score);
    if (scoreOrder != 0) return scoreOrder;
    final ancestryOrder = _compareSuggestionsParentFirst(left, right);
    if (ancestryOrder != 0) return ancestryOrder;
    final codeOrder = left.codeLabel.compareTo(right.codeLabel);
    if (codeOrder != 0) return codeOrder;
    if (left.isAggregate != right.isAggregate) {
      return left.isAggregate ? -1 : 1;
    }
    final pathOrder = EcoOpenings.compareMovePaths(
      left.movePath,
      right.movePath,
    );
    if (pathOrder != 0) return pathOrder;
    if (left.isFamily != right.isFamily) return left.isFamily ? -1 : 1;
    return left.codeLabel.compareTo(right.codeLabel);
  });
  if (limit == null || suggestions.length <= limit) return suggestions;
  return suggestions.take(limit).toList(growable: false);
}

int _compareSuggestionsParentFirst(
  OpeningSearchSuggestion left,
  OpeningSearchSuggestion right,
) {
  final leftFamily = EcoOpenings.getFamily(left.filter.code);
  final rightFamily = EcoOpenings.getFamily(right.filter.code);
  if (leftFamily != null && rightFamily != null) {
    if (_rangeContainsFamily(leftFamily, rightFamily)) return -1;
    if (_rangeContainsFamily(rightFamily, leftFamily)) return 1;
  } else if (leftFamily != null &&
      leftFamily.containsCode(right.filter.code!) &&
      right.hierarchyLabel.startsWith('${left.hierarchyLabel} ›')) {
    return -1;
  } else if (rightFamily != null &&
      rightFamily.containsCode(left.filter.code!) &&
      left.hierarchyLabel.startsWith('${right.hierarchyLabel} ›')) {
    return 1;
  }

  if (right.hierarchyLabel.startsWith('${left.hierarchyLabel} ›')) return -1;
  if (left.hierarchyLabel.startsWith('${right.hierarchyLabel} ›')) return 1;
  return 0;
}

/// Complete parent-aware vertical browser used before a filter query is typed.
/// It intentionally lists selectable scopes, not 1,813 duplicate destinations:
/// every explicit/derived family plus all 500 exact ECO codes.
List<OpeningSearchSuggestion> browseOpeningSuggestions() {
  final candidates = <_OpeningCandidate>[
    for (final family in EcoOpenings.families)
      _OpeningCandidate.forFamily(family, score: 0),
    for (final entry in EcoOpenings.codeToName.entries)
      if (EcoOpenings.canonicalRecordForCode(entry.key) case final record?)
        _OpeningCandidate.forRecord(
          record,
          score: 0,
          titleOverride: entry.value,
          aggregate: true,
        ),
  ];
  final suggestions = candidates.map(_buildSuggestion).toList(growable: false);
  suggestions.sort((left, right) {
    final leftFamily = EcoOpenings.getFamily(left.filter.code);
    final rightFamily = EcoOpenings.getFamily(right.filter.code);
    final leftStart = leftFamily?.rangeStart ?? left.filter.code!;
    final rightStart = rightFamily?.rangeStart ?? right.filter.code!;
    final category = leftStart[0].compareTo(rightStart[0]);
    if (category != 0) return category;
    final startOrder = int.parse(
      leftStart.substring(1),
    ).compareTo(int.parse(rightStart.substring(1)));
    if (startOrder != 0) return startOrder;
    if (left.isFamily != right.isFamily) return left.isFamily ? -1 : 1;
    final widerFirst = (rightFamily?.codeCount ?? 1).compareTo(
      leftFamily?.codeCount ?? 1,
    );
    if (widerFirst != 0) return widerFirst;
    return left.codeLabel.compareTo(right.codeLabel);
  });
  return suggestions;
}

class _OpeningCandidate {
  const _OpeningCandidate({
    required this.id,
    required this.filter,
    required this.fullTitle,
    required this.moves,
    required this.score,
    this.record,
    this.family,
    this.aggregate = false,
  });

  factory _OpeningCandidate.forRecord(
    EcoOpeningRecord record, {
    required int score,
    String? titleOverride,
    bool aggregate = false,
  }) {
    final fullTitle = titleOverride ?? record.name;
    return _OpeningCandidate(
      id:
          aggregate
              ? record.code
              : '${record.code}:${record.name}:${record.moves}',
      filter: GameEcoFilter.forCode(record.code),
      fullTitle: fullTitle,
      moves: record.moves,
      score: score,
      record: record,
      aggregate: aggregate,
    );
  }

  factory _OpeningCandidate.forFamily(
    EcoOpeningFamily family, {
    required int score,
  }) {
    return _OpeningCandidate(
      id: family.id,
      filter: GameEcoFilter.forFamily(family.id),
      fullTitle: family.name,
      moves: family.moves ?? '',
      score: score,
      family: family,
      aggregate: true,
    );
  }

  final String id;
  final GameEcoFilter filter;
  final String fullTitle;
  final String moves;
  final int score;
  final EcoOpeningRecord? record;
  final EcoOpeningFamily? family;
  final bool aggregate;

  bool isBetterThan(_OpeningCandidate other) {
    if (score != other.score) return score > other.score;
    final depth = EcoOpenings.moveTokens(moves).length;
    final otherDepth = EcoOpenings.moveTokens(other.moves).length;
    if (depth != otherDepth) return depth < otherDepth;
    return fullTitle.length < other.fullTitle.length;
  }
}

OpeningSearchSuggestion _buildSuggestion(_OpeningCandidate candidate) {
  final family = candidate.family;
  final record = candidate.record;
  final hierarchy = <String>[];

  void addHierarchy(String value) {
    for (final segment in _nameSegments(value)) {
      final normalized = _normalizeSearchText(segment);
      final duplicatesExisting = hierarchy.any((existing) {
        final normalizedExisting = _normalizeSearchText(existing);
        return normalizedExisting == normalized ||
            normalizedExisting.startsWith('$normalized ') ||
            normalized.startsWith('$normalizedExisting ');
      });
      if (!duplicatesExisting) hierarchy.add(segment);
    }
  }

  if (record != null) {
    for (final parent in EcoOpenings.familiesForCode(
      record.code,
      moves: record.moves,
    )) {
      addHierarchy(parent.name);
    }
    for (final ancestor in EcoOpenings.ancestorRecords(record)) {
      addHierarchy(ancestor.name);
    }
  } else if (family != null) {
    for (final parent in EcoOpenings.families) {
      if (parent.id != family.id &&
          _rangeContainsFamily(parent, family) &&
          _familyMoveContains(parent, family)) {
        addHierarchy(parent.name);
      }
    }
  }
  addHierarchy(candidate.fullTitle);

  final primary = hierarchy.isEmpty ? candidate.fullTitle : hierarchy.first;
  final childPath = hierarchy.skip(1).join(' › ');
  final variantCount =
      record == null ? 0 : EcoOpenings.variantCountForCode(record.code);
  late final String subtitle;
  if (family != null) {
    final scope = '${family.codeCount} ECO codes';
    subtitle = childPath.isEmpty ? scope : '$childPath · $scope';
  } else if (candidate.aggregate) {
    final scope =
        'All $variantCount indexed ${variantCount == 1 ? 'line' : 'variations'}';
    subtitle = childPath.isEmpty ? scope : '$childPath · $scope';
  } else {
    subtitle = childPath.isEmpty ? record!.moves : childPath;
  }
  final hierarchyLabel = hierarchy.join(' › ');

  return OpeningSearchSuggestion(
    id: candidate.id,
    filter: candidate.filter,
    title: primary,
    fullTitle: hierarchyLabel.isEmpty ? candidate.fullTitle : hierarchyLabel,
    subtitle: subtitle,
    hierarchyLabel: hierarchyLabel,
    score: candidate.score,
    movePath: EcoOpenings.moveTokens(candidate.moves),
    isAggregate: candidate.aggregate,
  );
}

bool _rangeContainsFamily(EcoOpeningFamily parent, EcoOpeningFamily child) {
  return parent.containsCode(child.rangeStart) &&
      parent.containsCode(child.rangeEnd) &&
      parent.codeCount > child.codeCount;
}

bool _familyMoveContains(EcoOpeningFamily parent, EcoOpeningFamily child) {
  if (parent.moves == null || child.moves == null) return true;
  return EcoOpenings.isMovePrefix(
    EcoOpenings.moveTokens(parent.moves!),
    EcoOpenings.moveTokens(child.moves!),
  );
}

List<String> _nameSegments(String value) => value
    .replaceAll(RegExp(r'\s*:\s*'), ',')
    .split(',')
    .map((segment) => segment.trim())
    .where((segment) => segment.isNotEmpty)
    .map(_sentenceCase)
    .toList(growable: false);

String _sentenceCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

int _searchCharacterCount(String query) =>
    query.replaceAll(RegExp(r'\s+'), '').length;

String _normalizeMoves(String moves) =>
    _normalizeSearchText(EcoOpenings.moveTokens(moves).join(' '));

String _normalizeSearchText(String value) {
  var normalized = value.trim().toLowerCase();
  const folds = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'ā': 'a',
    'ç': 'c',
    'č': 'c',
    'ď': 'd',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ě': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ł': 'l',
    'ñ': 'n',
    'ń': 'n',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ø': 'o',
    'ř': 'r',
    'š': 's',
    'ß': 'ss',
    'ť': 't',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ž': 'z',
    'æ': 'ae',
    'œ': 'oe',
  };
  for (final entry in folds.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized
      .replaceAll(RegExp(r"['‘’`´]"), '')
      .replaceAll('defence', 'defense')
      .replaceAll(RegExp(r'[^a-z0-9+#=]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int? _matchScore({
  required String query,
  required String code,
  required String name,
  required String moves,
}) {
  if (code == query) return 20000;
  final codeWithoutSeparators = code.replaceAll(RegExp(r'[^a-z0-9]'), '');
  final queryWithoutSeparators = query.replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (codeWithoutSeparators == queryWithoutSeparators) return 19800;

  final nameScore = _textMatchScore(name, query);
  final moveScore = moves.isEmpty ? null : _textMatchScore(moves, query);
  if (nameScore == null && moveScore == null && !code.contains(query)) {
    return null;
  }
  if (code.startsWith(query)) return 18500;
  if (code.contains(query)) return 17500;
  if (nameScore != null) return 10000 + nameScore;
  return 2000 + moveScore!;
}

int? _textMatchScore(String value, String query) {
  if (value == query) return 9000;
  if (value.startsWith(query)) return 8500;
  if (_wordStartsWith(value, query)) return 8000;
  if (value.contains(query)) return 7500;

  final compactValue = value.replaceAll(' ', '');
  final compactQuery = query.replaceAll(' ', '');
  if (compactValue.contains(compactQuery)) return 7100;

  final tokenScore = _fuzzyTokenScore(value, query);
  return tokenScore == null ? null : 5000 + tokenScore;
}

bool _wordStartsWith(String value, String query) =>
    value.split(' ').any((word) => word.startsWith(query) && query.length >= 3);

int? _fuzzyTokenScore(String value, String query) {
  final valueTokens = value.split(' ').where((token) => token.isNotEmpty);
  final queryTokens = query.split(' ').where((token) => token.isNotEmpty);
  var total = 0;
  for (final queryToken in queryTokens) {
    if (queryToken.length < 3) return null;
    var best = -1;
    for (final valueToken in valueTokens) {
      if (valueToken == queryToken) {
        best = 300;
        break;
      }
      if (valueToken.startsWith(queryToken)) {
        best = best < 260 ? 260 : best;
        continue;
      }
      final maxDistance =
          queryToken.length <= 4
              ? 1
              : queryToken.length <= 7
              ? 2
              : 3;
      final distance = _damerauLevenshtein(valueToken, queryToken);
      if (distance <= maxDistance) {
        final score = 220 - distance * 45;
        if (score > best) best = score;
      }
    }
    if (best < 0) return null;
    total += best;
  }
  return total;
}

int _damerauLevenshtein(String left, String right) {
  if (left == right) return 0;
  final matrix = List.generate(
    left.length + 1,
    (_) => List<int>.filled(right.length + 1, 0),
  );
  for (var i = 0; i <= left.length; i++) {
    matrix[i][0] = i;
  }
  for (var j = 0; j <= right.length; j++) {
    matrix[0][j] = j;
  }

  for (var i = 1; i <= left.length; i++) {
    for (var j = 1; j <= right.length; j++) {
      final cost = left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1;
      var value = _min3(
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost,
      );
      if (i > 1 &&
          j > 1 &&
          left.codeUnitAt(i - 1) == right.codeUnitAt(j - 2) &&
          left.codeUnitAt(i - 2) == right.codeUnitAt(j - 1)) {
        final transposed = matrix[i - 2][j - 2] + cost;
        if (transposed < value) value = transposed;
      }
      matrix[i][j] = value;
    }
  }
  return matrix[left.length][right.length];
}

int _min3(int first, int second, int third) {
  final pairMin = first < second ? first : second;
  return pairMin < third ? pairMin : third;
}
