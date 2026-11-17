import '../models/knockout_bracket.dart';
import 'bracket_game_result.dart';
import 'knockout_stage_parser.dart';

/// Confirmed match results in `tours.info.matchPlayBracket`, independent of a
/// shared stage's completion. A result must agree with the entire loaded match
/// (identities, game count and score). A later game or correction invalidates it.
/// Seeds are the organizer's complete first-stage pair order, not board numbers.
/// Missing next-round players are view-only TBDs, never fabricated game rows.
List<KnockoutStage> applyMatchPlayAdvancement(
  List<KnockoutStage> stages,
  Map<String, Map<String, dynamic>?> metadataByTour,
) {
  final result = <KnockoutStage>[];
  final seeded = <String>{};
  for (final stage in stages) {
    final metadata = stage.sourceTourIds.length == 1
        ? metadataByTour[stage.sourceTourIds.single]
        : null;
    if (metadata == null || stage.sourceRoundIds.length != 1) {
      result.add(stage);
      continue;
    }
    final roundId = stage.sourceRoundIds.single;
    final results = <String, Map>{};
    final duplicates = <String>{};
    for (final row in _rows(metadata['results'])) {
      if (row['roundId'] != roundId) continue;
      final key = _pair(row['fideIds']);
      if (key == null) {
        continue;
      }
      if (results.containsKey(key)) {
        duplicates.add(key);
      }
      results[key] = row;
    }
    for (final key in duplicates) {
      results.remove(key);
    }
    var matches = [
      for (final match in stage.matches)
        if (_confirmedWinner(match, results[_matchPair(match)])
            case final winner?)
          match.copyWith(winner: winner)
        else
          match,
    ];
    final seeds = _rows(
      metadata['seeds'],
    ).where((r) => r['roundId'] == roundId).toList();
    if (seeds.length == 1 && seeds.single['fideIds'] is List) {
      final pairs = seeds.single['fideIds'] as List;
      final keys = pairs.map(_pair).toList();
      final byPair = {for (final match in matches) _matchPair(match): match};
      final participants = pairs.whereType<List>().expand((p) => p).toSet();
      if (pairs.length == matches.length &&
          pairs.length >= 2 &&
          (pairs.length & (pairs.length - 1)) == 0 &&
          keys.every((k) => k != null && byPair.containsKey(k)) &&
          keys.toSet().length == keys.length &&
          participants.length == pairs.length * 2) {
        matches = [for (final key in keys) byPair[key]!];
        seeded.add(stage.key);
      }
    }
    result.add(stage.copyWith(matches: matches));
  }

  final possibleParticipants = <String, Set<String>>{};
  for (final stage in result.where((s) => seeded.contains(s.key))) {
    for (final match in stage.matches) {
      possibleParticipants[match.key] = {
        match.participant1.id,
        match.participant2.id,
      };
    }
  }
  for (var i = 0; i < result.length; i++) {
    final source = result[i];
    final size = _fieldSize(source);
    if (!seeded.contains(source.key) ||
        size < 4 ||
        source.matches.length != size ~/ 2) {
      continue;
    }
    final destinationIndex = result.indexWhere(
      (s) => _fieldSize(s) == size ~/ 2,
      i + 1,
    );
    if (destinationIndex >= 0) {
      final filled = _fillStage(
        source,
        result[destinationIndex],
        possibleParticipants,
      );
      if (filled != null) {
        result[destinationIndex] = filled;
        seeded.add(filled.key);
      }
    }
    if (size == 4) {
      final thirdIndex = result.indexWhere(
        (s) => resolveLogicalKnockoutStage(s.label, '')?.key == 'third-place',
      );
      if (thirdIndex >= 0) {
        final filled = _fillStage(
          source,
          result[thirdIndex],
          possibleParticipants,
          losers: true,
        );
        if (filled != null) result[thirdIndex] = filled;
      }
    }
  }
  return result;
}

// Preserve the official slots as real pairings arrive one match at a time.
// Each slot retains its seed pool, so subsequent rounds can be routed even
// while some players are still unknown. A contradictory pairing is never put
// into an invented slot.
KnockoutStage? _fillStage(
  KnockoutStage source,
  KnockoutStage destination,
  Map<String, Set<String>> pools, {
  bool losers = false,
}) {
  if (!destination.sourceTourIds.toSet().containsAll(source.sourceTourIds)) {
    return null;
  }
  final slots = source.matches.length ~/ 2;
  final published = <int, KnockoutMatch>{};
  for (final match in destination.matches) {
    final candidates = <int>[];
    for (var slot = 0; slot < slots; slot++) {
      final top = pools[source.matches[slot * 2].key] ?? const <String>{};
      final bottom =
          pools[source.matches[slot * 2 + 1].key] ?? const <String>{};
      if ((top.contains(match.participant1.id) &&
              bottom.contains(match.participant2.id)) ||
          (top.contains(match.participant2.id) &&
              bottom.contains(match.participant1.id))) {
        candidates.add(slot);
      }
    }
    if (candidates.length != 1 || published.containsKey(candidates.single)) {
      return null;
    }
    published[candidates.single] = match;
  }
  final matches = <KnockoutMatch>[];
  for (var slot = 0; slot < slots; slot++) {
    final top = source.matches[slot * 2];
    final bottom = source.matches[slot * 2 + 1];
    final feeders = [top.key, bottom.key];
    final existing = published[slot];
    final match =
        existing?.copyWith(feederMatchKeys: feeders, feedsLosers: losers) ??
        KnockoutMatch(
          key: '${destination.key}:pending:$slot',
          stageKey: destination.key,
          participant1:
              _qualified(top, losers: losers) ??
              _pending(destination.key, slot, 0),
          participant2:
              _qualified(bottom, losers: losers) ??
              _pending(destination.key, slot, 1),
          games: const [],
          participant1Score: 0,
          participant2Score: 0,
          leader: null,
          winner: null,
          minimumBoardOrder: slot,
          isProjected: true,
          isComplete: false,
          isLive: false,
          feederMatchKeys: feeders,
          feedsLosers: losers,
        );
    pools[match.key] = {...?pools[top.key], ...?pools[bottom.key]};
    matches.add(match);
  }
  return destination.copyWith(matches: matches);
}

BracketParticipant? _qualified(KnockoutMatch match, {required bool losers}) {
  final winner = match.winner;
  if (winner == null) return null;
  if (!losers) return winner;
  return winner.id == match.participant1.id
      ? match.participant2
      : match.participant1;
}

Iterable<Map> _rows(dynamic value) =>
    value is List ? value.take(256).whereType<Map>() : const [];

String? _pair(dynamic value) {
  if (value is! List ||
      value.length != 2 ||
      value.any(
        (id) => id is! String || !RegExp(r'^[1-9]\d{0,8}$').hasMatch(id),
      ) ||
      value[0] == value[1]) {
    return null;
  }
  return (List<String>.from(value)..sort()).join(':');
}

String? _matchPair(KnockoutMatch match) => _pair([
  match.participant1.fideId?.toString(),
  match.participant2.fideId?.toString(),
]);

BracketParticipant? _confirmedWinner(KnockoutMatch match, Map? row) {
  if (row == null ||
      match.games.length < 2 ||
      match.sourceRoundIds.length != 1 ||
      match.isLive ||
      match.games.any((g) => !bracketGameResult(g).isDecided) ||
      row['gameCount'] is! int ||
      row['gameCount'] != match.games.length) {
    return null;
  }
  final scores = row['scores'];
  if (scores is! List ||
      scores.length != 2 ||
      scores.any((s) => s is! num || !s.isFinite || s < 0)) {
    return null;
  }
  final ids = row['fideIds'] as List;
  final first = ids.indexOf(match.participant1.fideId.toString());
  if (first < 0 ||
      scores[first] != match.participant1Score ||
      scores[1 - first] != match.participant2Score ||
      match.leader == null ||
      row['winnerFideId'] != match.leader!.fideId.toString() ||
      (match.winner != null && match.winner != match.leader)) {
    return null;
  }
  return match.leader;
}

int _fieldSize(KnockoutStage stage) {
  final key = resolveLogicalKnockoutStage(stage.label, '')?.key ?? '';
  if (key == 'quarterfinals') return 8;
  if (key == 'semifinals') return 4;
  if (key == 'finals') return 2;
  return key.startsWith('round-of-') ? int.tryParse(key.substring(9)) ?? 0 : 0;
}

BracketParticipant _pending(String stage, int slot, int side) =>
    BracketParticipant(id: '$stage:pending:$slot:$side', name: 'TBD');
