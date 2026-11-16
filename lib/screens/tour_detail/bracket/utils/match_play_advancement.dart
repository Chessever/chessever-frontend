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

  for (var i = 0; i < result.length - 1; i++) {
    final source = result[i];
    if (!seeded.contains(source.key) ||
        !source.matches.any((m) => m.winner != null)) {
      continue;
    }
    // Placement rounds are not steps toward the title. Never fill a different
    // stage or replace pairings already published by the organizer.
    final destinationIndex = result.indexWhere(
      (s) => _fieldSize(s) == _fieldSize(source) ~/ 2,
      i + 1,
    );
    if (destinationIndex < 0 || _fieldSize(source) < 4) continue;
    final destination = result[destinationIndex];
    if (destination.matches.isNotEmpty ||
        !destination.sourceTourIds.toSet().containsAll(source.sourceTourIds)) {
      continue;
    }
    result[destinationIndex] = destination.copyWith(
      matches: [
        for (var slot = 0; slot < source.matches.length ~/ 2; slot++)
          KnockoutMatch(
            key: '${destination.key}:pending:$slot',
            stageKey: destination.key,
            participant1:
                source.matches[slot * 2].winner ??
                _pending(destination.key, slot, 0),
            participant2:
                source.matches[slot * 2 + 1].winner ??
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
          ),
      ],
    );
  }
  return result;
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
      row['winnerFideId'] != match.leader!.fideId.toString()) {
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
