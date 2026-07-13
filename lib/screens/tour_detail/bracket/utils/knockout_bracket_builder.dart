import 'dart:math' as math;

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/bracket_game_result.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_stage_parser.dart';

KnockoutBracket buildKnockoutBracket({
  required Tour selectedTour,
  required List<Tour> siblingTours,
  required Map<String, List<Round>> roundsByTourId,
  required Map<String, List<Games>> gamesByTourId,
  Set<String> liveTourIds = const {},
  Set<String> liveRoundIds = const {},
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final relevantTours = filterKnockoutSiblingTours(
    selectedTour: selectedTour,
    siblingTours: siblingTours,
  );
  final stageTours =
      relevantTours
          .where(
            (tour) => parseKnockoutTourStageDescriptor(tour.name).stage != null,
          )
          .toList();
  final selectedIsNamedStage = stageTours.any(
    (tour) => tour.id == selectedTour.id,
  );
  final isMultiTour =
      stageTours.length > 1 ||
      stageTours.any((tour) => tour.id != selectedTour.id);

  late final _StageSeedResult seedResult;
  if (isMultiTour) {
    final namedStageResult = _multiTourStageSeeds(
      stageTours,
      roundsByTourId: roundsByTourId,
      gamesByTourId: gamesByTourId,
    );
    final selectedRounds = roundsByTourId[selectedTour.id] ?? const <Round>[];
    final selectedGames = gamesByTourId[selectedTour.id] ?? const <Games>[];
    if (!selectedIsNamedStage &&
        (selectedRounds.isNotEmpty || selectedGames.isNotEmpty)) {
      final selectedResult = _singleTourStageSeeds(
        selectedTour,
        rounds: selectedRounds,
        games: selectedGames,
      );
      seedResult = _StageSeedResult(
        seeds: [...selectedResult.seeds, ...namedStageResult.seeds],
        ambiguousEvidence:
            selectedResult.ambiguousEvidence ||
            namedStageResult.ambiguousEvidence,
      );
    } else {
      seedResult = namedStageResult;
    }
  } else {
    seedResult = _singleTourStageSeeds(
      selectedTour,
      rounds: roundsByTourId[selectedTour.id] ?? const [],
      games: gamesByTourId[selectedTour.id] ?? const [],
    );
  }
  final seeds = seedResult.seeds..sort(_compareStageSeeds);
  final registry = _ParticipantRegistry(seeds.expand((seed) => seed.games));
  final namedStageTourIds = stageTours.map((tour) => tour.id).toSet();
  final seedCountByTourId = <String, int>{};
  for (final seed in seeds) {
    for (final tourId in seed.sourceTourIds) {
      seedCountByTourId.update(tourId, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  var discardedGameEvidence = false;
  final baseStages = <KnockoutStage>[];
  for (var index = 0; index < seeds.length; index++) {
    final seed = seeds[index];
    // A tour-level live flag identifies the active stage only when each source
    // tour is itself a named stage, or contributes exactly one seed. A generic
    // selected/root tour can coexist with sibling stages while still holding
    // several round-derived stages of its own.
    final allowTourLevelLive = seed.sourceTourIds.every(
      (tourId) =>
          namedStageTourIds.contains(tourId) || seedCountByTourId[tourId] == 1,
    );
    final matchResult = _buildMatches(
      seed,
      registry: registry,
      liveTourIds: liveTourIds,
      liveRoundIds: liveRoundIds,
      allowTourLevelLive: allowTourLevelLive,
    );
    discardedGameEvidence |= matchResult.discardedEvidence;
    final matches = matchResult.matches;
    final isLive =
        (allowTourLevelLive && seed.sourceTourIds.any(liveTourIds.contains)) ||
        seed.sourceRoundIds.any(liveRoundIds.contains) ||
        matches.any((match) => match.isLive);
    final hasFutureRound = seed.rounds.any(
      (round) =>
          round.startsAt != null && round.startsAt!.isAfter(effectiveNow),
    );
    final completionWindowEnded =
        seed.completionNotBefore != null &&
        !seed.completionNotBefore!.isAfter(effectiveNow);
    final state = _stageState(
      matches,
      isLive: isLive,
      hasFutureRound: hasFutureRound,
      completionWindowEnded: completionWindowEnded,
    );

    baseStages.add(
      KnockoutStage(
        key: seed.key,
        label: seed.label,
        sourceTourIds: seed.sourceTourIds,
        sourceRoundIds: seed.sourceRoundIds,
        order: index,
        state: state,
        isLive: isLive,
        matches: matches,
      ),
    );
  }

  final edgeResult = _inferEdges(baseStages);
  final stages = <KnockoutStage>[];
  for (var stageIndex = 0; stageIndex < baseStages.length; stageIndex++) {
    final stage = baseStages[stageIndex];
    final matches =
        stage.matches.map((match) {
          BracketParticipant? winner;
          final advanced = edgeResult.advancedBySourceMatch[match.key];
          if (advanced != null && advanced.length == 1) {
            winner = match.participantById(advanced.single);
          }
          if (winner == null && stage.isComplete && match.isComplete) {
            winner = match.leader;
          }
          return winner == null ? match : match.copyWith(winner: winner);
        }).toList();
    stages.add(stage.copyWith(matches: matches));
  }

  String? currentStageKey;
  for (final stage in stages.reversed) {
    if (stage.isLive) {
      currentStageKey = stage.key;
      break;
    }
  }
  if (currentStageKey == null) {
    for (final stage in stages.reversed) {
      if (!stage.isComplete) {
        currentStageKey = stage.key;
        break;
      }
    }
  }
  currentStageKey ??= stages.isEmpty ? null : stages.last.key;

  String? selectedStageKey;
  for (final stage in stages) {
    if (stage.sourceTourIds.contains(selectedTour.id)) {
      selectedStageKey = stage.key;
      break;
    }
  }
  selectedStageKey ??= currentStageKey;

  final isPartial =
      stages.isEmpty ||
      seedResult.ambiguousEvidence ||
      edgeResult.ambiguousEvidence ||
      discardedGameEvidence ||
      stages.any((stage) => !stage.isComplete || stage.matches.isEmpty);

  return KnockoutBracket(
    stages: stages,
    edges: edgeResult.edges,
    selectedStageKey: selectedStageKey,
    currentStageKey: currentStageKey,
    isPartial: isPartial,
  );
}

_StageSeedResult _multiTourStageSeeds(
  List<Tour> tours, {
  required Map<String, List<Round>> roundsByTourId,
  required Map<String, List<Games>> gamesByTourId,
}) {
  final grouped = <String, List<Tour>>{};
  final stages = <String, LogicalKnockoutStage>{};
  for (final tour in tours) {
    final stage = parseKnockoutTourStageDescriptor(tour.name).stage!;
    grouped.putIfAbsent(stage.key, () => []).add(tour);
    stages[stage.key] = stage;
  }

  final seeds = <_StageSeed>[];
  for (final entry in grouped.entries) {
    final sourceTours = entry.value..sort((a, b) => a.id.compareTo(b.id));
    final rounds =
        sourceTours
            .expand((tour) => roundsByTourId[tour.id] ?? const <Round>[])
            .toList()
          ..sort(_compareRounds);
    final games =
        sourceTours
            .expand((tour) => gamesByTourId[tour.id] ?? const <Games>[])
            .toList();
    final tourIds = sourceTours.map((tour) => tour.id).toList();
    final firstDate = sourceTours
        .map((tour) => tour.dates.isEmpty ? tour.createdAt : tour.dates.first)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    seeds.add(
      _StageSeed(
        key: _stageKey(tourIds, entry.key),
        label: stages[entry.key]!.label,
        semanticOrder: stages[entry.key]!.sortOrder,
        chronologicalOrder: firstDate,
        completionNotBefore: _completionNotBefore(
          sourceTours,
          rounds: rounds,
          games: games,
        ),
        sourceTourIds: tourIds,
        rounds: rounds,
        games: games,
      ),
    );
  }
  return _StageSeedResult(seeds: seeds, ambiguousEvidence: false);
}

_StageSeedResult _singleTourStageSeeds(
  Tour tour, {
  required List<Round> rounds,
  required List<Games> games,
}) {
  final sortedRounds = List<Round>.from(rounds)..sort(_compareRounds);
  final resolved = <String, _ResolvedRound>{};
  for (final round in sortedRounds) {
    final stage = resolveLogicalKnockoutStage(
      round.name,
      round.slug,
      tourName: tour.name,
    );
    if (stage != null) resolved[round.id] = _ResolvedRound(round, stage);
  }

  if (resolved.isEmpty) {
    final tourStage = parseKnockoutTourStageDescriptor(tour.name).stage;
    final fallback =
        tourStage ??
        const LogicalKnockoutStage(
          key: 'bracket',
          label: 'Bracket',
          sortOrder: 2000,
        );
    return _StageSeedResult(
      seeds: [
        _StageSeed(
          key: _stageKey([tour.id], fallback.key),
          label: fallback.label,
          semanticOrder: fallback.sortOrder,
          chronologicalOrder: _firstDate(tour, sortedRounds, games),
          completionNotBefore: _completionNotBefore(
            [tour],
            rounds: sortedRounds,
            games: games,
          ),
          sourceTourIds: [tour.id],
          rounds: sortedRounds,
          games: games,
        ),
      ],
      ambiguousEvidence: rounds.isNotEmpty || games.isNotEmpty,
    );
  }

  final roundsByStage = <String, List<Round>>{};
  final stageDefinitions = <String, LogicalKnockoutStage>{};
  for (final item in resolved.values) {
    roundsByStage.putIfAbsent(item.stage.key, () => []).add(item.round);
    stageDefinitions[item.stage.key] = item.stage;
  }

  final unresolvedRounds =
      sortedRounds.where((round) => !resolved.containsKey(round.id)).toList();
  var ambiguous = false;
  if (unresolvedRounds.isNotEmpty) {
    if (roundsByStage.length == 1) {
      roundsByStage.values.single.addAll(unresolvedRounds);
    } else {
      ambiguous = true;
    }
  }

  final stageForRoundId = <String, String>{};
  for (final entry in roundsByStage.entries) {
    for (final round in entry.value) {
      stageForRoundId[round.id] = entry.key;
    }
  }
  final gamesByStage = <String, List<Games>>{};
  final unassignedGames = <Games>[];
  for (final game in games) {
    final stageKey = stageForRoundId[game.roundId];
    if (stageKey == null) {
      unassignedGames.add(game);
    } else {
      gamesByStage.putIfAbsent(stageKey, () => []).add(game);
    }
  }
  if (unassignedGames.isNotEmpty) {
    if (roundsByStage.length == 1) {
      gamesByStage
          .putIfAbsent(roundsByStage.keys.single, () => [])
          .addAll(unassignedGames);
    } else {
      ambiguous = true;
    }
  }

  final seeds = <_StageSeed>[];
  for (final entry in roundsByStage.entries) {
    final stage = stageDefinitions[entry.key]!;
    final stageRounds = entry.value..sort(_compareRounds);
    final stageGames = gamesByStage[entry.key] ?? const <Games>[];
    seeds.add(
      _StageSeed(
        key: _stageKey([tour.id], stage.key),
        label: stage.label,
        semanticOrder: stage.sortOrder,
        chronologicalOrder: _firstDate(tour, stageRounds, stageGames),
        completionNotBefore: _completionNotBefore(
          [tour],
          rounds: stageRounds,
          games: stageGames,
        ),
        sourceTourIds: [tour.id],
        rounds: stageRounds,
        games: stageGames,
      ),
    );
  }

  if ((unresolvedRounds.isNotEmpty || unassignedGames.isNotEmpty) &&
      roundsByStage.length > 1) {
    final unresolvedRoundIds =
        unresolvedRounds.map((round) => round.id).toSet();
    final fallbackGames =
        games
            .where(
              (game) =>
                  unresolvedRoundIds.contains(game.roundId) ||
                  !stageForRoundId.containsKey(game.roundId),
            )
            .toList();
    seeds.add(
      _StageSeed(
        key: _stageKey([tour.id], 'other-pairings'),
        label: 'Other pairings',
        semanticOrder: 6500,
        chronologicalOrder: _firstDate(tour, unresolvedRounds, fallbackGames),
        completionNotBefore: _completionNotBefore(
          [tour],
          rounds: unresolvedRounds,
          games: fallbackGames,
        ),
        sourceTourIds: [tour.id],
        rounds: unresolvedRounds,
        games: fallbackGames,
      ),
    );
  }

  return _StageSeedResult(seeds: seeds, ambiguousEvidence: ambiguous);
}

_MatchBuildResult _buildMatches(
  _StageSeed seed, {
  required _ParticipantRegistry registry,
  required Set<String> liveTourIds,
  required Set<String> liveRoundIds,
  required bool allowTourLevelLive,
}) {
  final roundOrder = <String, int>{
    for (var index = 0; index < seed.rounds.length; index++)
      seed.rounds[index].id: index,
  };
  final feedOrder = <String, int>{
    for (var index = 0; index < seed.games.length; index++)
      seed.games[index].id: index,
  };
  final grouped = <String, List<Games>>{};
  var discarded = false;

  for (final game in seed.games) {
    final players = game.players;
    if (players == null || players.length < 2) {
      discarded = true;
      continue;
    }
    final firstId = registry.idFor(players[0]);
    final secondId = registry.idFor(players[1]);
    if (firstId == null || secondId == null || firstId == secondId) {
      discarded = true;
      continue;
    }
    final ids = [firstId, secondId]..sort();
    final matchup = '${ids[0]}\u0000${ids[1]}';
    grouped.putIfAbsent(matchup, () => []).add(game);
  }

  final matches = <KnockoutMatch>[];
  final firstFeedOrderByMatchKey = <String, int>{};
  for (final matchGames in grouped.values) {
    matchGames.sort((a, b) {
      final round = (roundOrder[a.roundId] ?? 1 << 30).compareTo(
        roundOrder[b.roundId] ?? 1 << 30,
      );
      if (round != 0) return round;
      final date = _gameDate(a).compareTo(_gameDate(b));
      if (date != 0) return date;
      final board = (a.boardNr ?? 1 << 30).compareTo(b.boardNr ?? 1 << 30);
      if (board != 0) return board;
      return (feedOrder[a.id] ?? 1 << 30).compareTo(feedOrder[b.id] ?? 1 << 30);
    });

    final firstGamePlayers = matchGames.first.players!;
    final participant1 = registry.participantFor(firstGamePlayers[0])!;
    final participant2 = registry.participantFor(firstGamePlayers[1])!;
    var participant1Score = 0.0;
    var participant2Score = 0.0;
    var allDecided = true;
    var isLive = false;

    for (final game in matchGames) {
      final result = bracketGameResult(game);
      if (result == BracketGameResult.undecided) allDecided = false;
      // Stale tour/round live markers must never paint a decided game as live.
      isLive |=
          result == BracketGameResult.undecided &&
          ((allowTourLevelLive && liveTourIds.contains(game.tourId)) ||
              liveRoundIds.contains(game.roundId) ||
              (game.lastMove != null && game.lastMove!.isNotEmpty));
      if (result == BracketGameResult.undecided) continue;

      final whiteId = registry.idFor(game.players![0]);
      final participant1IsWhite = whiteId == participant1.id;
      switch (result) {
        case BracketGameResult.whiteWin:
          if (participant1IsWhite) {
            participant1Score += 1;
          } else {
            participant2Score += 1;
          }
        case BracketGameResult.blackWin:
          if (participant1IsWhite) {
            participant2Score += 1;
          } else {
            participant1Score += 1;
          }
        case BracketGameResult.draw:
          participant1Score += 0.5;
          participant2Score += 0.5;
        case BracketGameResult.doubleForfeit:
          break;
        case BracketGameResult.undecided:
          break;
      }
    }

    final BracketParticipant? leader =
        participant1Score == participant2Score
            ? null
            : participant1Score > participant2Score
            ? participant1
            : participant2;
    final ids = [participant1.id, participant2.id]..sort();
    final key =
        '${seed.key}:match:'
        '${Uri.encodeComponent(ids[0])}--${Uri.encodeComponent(ids[1])}';
    firstFeedOrderByMatchKey[key] = matchGames
        .map((game) => feedOrder[game.id] ?? 1 << 30)
        .reduce(math.min);
    int? minimumBoard;
    for (final game in matchGames) {
      if (game.boardNr == null) continue;
      minimumBoard =
          minimumBoard == null
              ? game.boardNr
              : math.min(minimumBoard, game.boardNr!);
    }

    matches.add(
      KnockoutMatch(
        key: key,
        stageKey: seed.key,
        participant1: participant1,
        participant2: participant2,
        games: matchGames,
        participant1Score: participant1Score,
        participant2Score: participant2Score,
        leader: leader,
        winner: null,
        minimumBoardOrder: minimumBoard,
        isComplete: matchGames.isNotEmpty && allDecided,
        isLive: isLive,
      ),
    );
  }

  matches.sort((a, b) {
    final board = (a.minimumBoardOrder ?? 1 << 30).compareTo(
      b.minimumBoardOrder ?? 1 << 30,
    );
    if (board != 0) return board;
    final feed = (firstFeedOrderByMatchKey[a.key] ?? 1 << 30).compareTo(
      firstFeedOrderByMatchKey[b.key] ?? 1 << 30,
    );
    return feed != 0 ? feed : a.key.compareTo(b.key);
  });
  return _MatchBuildResult(matches: matches, discardedEvidence: discarded);
}

_EdgeInferenceResult _inferEdges(List<KnockoutStage> stages) {
  final edges = <KnockoutEdge>[];
  final advanced = <String, Set<String>>{};
  final edgeKeys = <String>{};
  var ambiguousEvidence = false;

  for (
    var destinationIndex = 1;
    destinationIndex < stages.length;
    destinationIndex++
  ) {
    final destination = stages[destinationIndex];
    if (_isAmbiguousStage(destination)) continue;
    for (final destinationMatch in destination.matches) {
      for (final participant in [
        destinationMatch.participant1,
        destinationMatch.participant2,
      ]) {
        for (
          var sourceIndex = destinationIndex - 1;
          sourceIndex >= 0;
          sourceIndex--
        ) {
          if (_isAmbiguousStage(stages[sourceIndex])) continue;
          final sources =
              stages[sourceIndex].matches
                  .where((match) => match.containsParticipant(participant.id))
                  .toList();
          if (sources.isEmpty) continue;
          if (sources.length != 1) {
            ambiguousEvidence = true;
            break;
          }
          final source = sources.single;
          final edgeKey =
              '${source.key}\u0000${destinationMatch.key}\u0000${participant.id}';
          if (edgeKeys.add(edgeKey)) {
            edges.add(
              KnockoutEdge(
                sourceMatchKey: source.key,
                destinationMatchKey: destinationMatch.key,
                participantId: participant.id,
              ),
            );
            // A later appearance in a placement branch (for example a bronze
            // match) is real connector evidence, but it proves elimination,
            // not advancement toward the championship match.
            if (!_isPlacementStage(destination)) {
              advanced.putIfAbsent(source.key, () => {}).add(participant.id);
            }
          }
          break;
        }
      }
    }
  }

  return _EdgeInferenceResult(
    edges: edges,
    advancedBySourceMatch: advanced,
    ambiguousEvidence: ambiguousEvidence,
  );
}

bool _isAmbiguousStage(KnockoutStage stage) =>
    stage.key.endsWith(':other-pairings') ||
    stage.label.toLowerCase() == 'other pairings';

KnockoutStageState _stageState(
  List<KnockoutMatch> matches, {
  required bool isLive,
  required bool hasFutureRound,
  required bool completionWindowEnded,
}) {
  if (matches.isEmpty) return KnockoutStageState.upcoming;
  if (!isLive &&
      completionWindowEnded &&
      !hasFutureRound &&
      matches.every((match) => match.isComplete)) {
    return KnockoutStageState.completed;
  }
  final hasDecidedGame = matches.any(
    (match) => match.participant1Score > 0 || match.participant2Score > 0,
  );
  return isLive || hasDecidedGame
      ? KnockoutStageState.inProgress
      : KnockoutStageState.upcoming;
}

bool _isPlacementStage(KnockoutStage stage) {
  final value = '${stage.key} ${stage.label}'.toLowerCase();
  return value.contains('third-place') ||
      value.contains('third place') ||
      value.contains('3rd place') ||
      value.contains('bronze') ||
      value.contains('consolation') ||
      value.contains('placement');
}

int _compareStageSeeds(_StageSeed a, _StageSeed b) {
  final semantic = a.semanticOrder.compareTo(b.semanticOrder);
  if (semantic != 0) return semantic;
  final chronological = a.chronologicalOrder.compareTo(b.chronologicalOrder);
  return chronological != 0 ? chronological : a.key.compareTo(b.key);
}

int _compareRounds(Round a, Round b) {
  final date = (a.startsAt ?? a.createdAt).compareTo(b.startsAt ?? b.createdAt);
  if (date != 0) return date;
  final leg = _roundLegOrder(a).compareTo(_roundLegOrder(b));
  return leg != 0 ? leg : a.id.compareTo(b.id);
}

int _roundLegOrder(Round round) {
  final value = '${round.name} ${round.slug}'.toLowerCase();
  final decimal = RegExp(r'round\s+\d+[._](\d+)').firstMatch(value);
  if (decimal != null) return int.parse(decimal.group(1)!);
  final game = RegExp(r'(?:game|leg)[ -]?(\d+)').firstMatch(value);
  if (game != null) return int.parse(game.group(1)!);
  if (value.contains('tiebreak') || value.contains('tie-break')) return 100;
  if (value.contains('rapid')) return 110;
  if (value.contains('blitz')) return 120;
  if (value.contains('armageddon')) return 130;
  return 0;
}

DateTime _firstDate(Tour tour, List<Round> rounds, List<Games> games) {
  if (rounds.isNotEmpty) return rounds.first.startsAt ?? rounds.first.createdAt;
  final gameDates =
      games.map(_gameDate).where((date) => date != _epoch).toList()..sort();
  if (gameDates.isNotEmpty) return gameDates.first;
  return tour.dates.isEmpty ? tour.createdAt : tour.dates.first;
}

DateTime? _completionNotBefore(
  Iterable<Tour> tours, {
  required Iterable<Round> rounds,
  required Iterable<Games> games,
}) {
  DateTime? latest;
  for (final tour in tours) {
    if (tour.dates.isEmpty) continue;
    final listedEnd = tour.dates.last;
    // Broadcast `dates` are calendar days, normally encoded at midnight.
    // Waiting until the following day prevents a decided first leg from
    // becoming a terminal winner while another leg can still be published.
    final boundary =
        listedEnd.isUtc
            ? DateTime.utc(listedEnd.year, listedEnd.month, listedEnd.day + 1)
            : DateTime(listedEnd.year, listedEnd.month, listedEnd.day + 1);
    if (latest == null || boundary.isAfter(latest)) latest = boundary;
  }
  if (latest != null) return latest;

  // Some imported broadcasts have no calendar `dates`. In that case a
  // bounded grace window after the latest round/game evidence is conservative
  // enough for an unpublished extra leg, while still letting old completed
  // finals settle instead of remaining "in progress" forever.
  DateTime? latestEvidence;
  for (final round in rounds) {
    final value = round.startsAt ?? round.createdAt;
    if (latestEvidence == null || value.isAfter(latestEvidence)) {
      latestEvidence = value;
    }
  }
  for (final game in games) {
    final value = _gameDate(game);
    if (value == _epoch) continue;
    if (latestEvidence == null || value.isAfter(latestEvidence)) {
      latestEvidence = value;
    }
  }
  return latestEvidence?.add(const Duration(days: 7));
}

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime _gameDate(Games game) =>
    game.gameDay ?? game.dateStart ?? game.lastMoveTime ?? _epoch;

String _stageKey(List<String> tourIds, String logicalStageKey) {
  final ids = List<String>.from(tourIds)..sort();
  return 'stage:${ids.join('+')}:$logicalStageKey';
}

class _ResolvedRound {
  const _ResolvedRound(this.round, this.stage);

  final Round round;
  final LogicalKnockoutStage stage;
}

class _StageSeed {
  const _StageSeed({
    required this.key,
    required this.label,
    required this.semanticOrder,
    required this.chronologicalOrder,
    required this.completionNotBefore,
    required this.sourceTourIds,
    required this.rounds,
    required this.games,
  });

  final String key;
  final String label;
  final int semanticOrder;
  final DateTime chronologicalOrder;
  final DateTime? completionNotBefore;
  final List<String> sourceTourIds;
  final List<Round> rounds;
  final List<Games> games;

  List<String> get sourceRoundIds =>
      rounds.map((round) => round.id).toSet().toList();
}

class _StageSeedResult {
  const _StageSeedResult({
    required this.seeds,
    required this.ambiguousEvidence,
  });

  final List<_StageSeed> seeds;
  final bool ambiguousEvidence;
}

class _MatchBuildResult {
  const _MatchBuildResult({
    required this.matches,
    required this.discardedEvidence,
  });

  final List<KnockoutMatch> matches;
  final bool discardedEvidence;
}

class _EdgeInferenceResult {
  const _EdgeInferenceResult({
    required this.edges,
    required this.advancedBySourceMatch,
    required this.ambiguousEvidence,
  });

  final List<KnockoutEdge> edges;
  final Map<String, Set<String>> advancedBySourceMatch;
  final bool ambiguousEvidence;
}

class _ParticipantRegistry {
  _ParticipantRegistry(Iterable<Games> games) {
    final fideIdsByName = <String, Set<int>>{};
    final players = <Player>[];
    for (final game in games) {
      for (final player in game.players ?? const <Player>[]) {
        players.add(player);
        final name = _normalizedPlayerName(player.name);
        if (name.isEmpty || player.fideId <= 0) continue;
        fideIdsByName.putIfAbsent(name, () => {}).add(player.fideId);
      }
    }
    for (final entry in fideIdsByName.entries) {
      if (entry.value.length == 1) {
        _fideIdByName[entry.key] = entry.value.single;
      }
    }
    for (final player in players) {
      final id = idFor(player);
      if (id == null) continue;
      final current = _dataById[id];
      _dataById[id] =
          current == null
              ? _ParticipantData.fromPlayer(id, player)
              : current.merge(player);
    }
  }

  final Map<String, int> _fideIdByName = {};
  final Map<String, _ParticipantData> _dataById = {};

  String? idFor(Player player) {
    final name = _normalizedPlayerName(player.name);
    if (name.isEmpty || _isPlaceholderParticipantName(name)) return null;
    final fideId = player.fideId > 0 ? player.fideId : _fideIdByName[name];
    return fideId == null ? 'name:$name' : 'fide:$fideId';
  }

  BracketParticipant? participantFor(Player player) {
    final id = idFor(player);
    return id == null ? null : _dataById[id]?.participant;
  }
}

class _ParticipantData {
  const _ParticipantData({
    required this.id,
    required this.name,
    required this.fideId,
    required this.federation,
    required this.title,
    required this.rating,
  });

  factory _ParticipantData.fromPlayer(String id, Player player) =>
      _ParticipantData(
        id: id,
        name: _titleFreeDisplayName(player.name),
        fideId: player.fideId > 0 ? player.fideId : null,
        federation: player.fed.trim().isEmpty ? null : player.fed.trim(),
        title: player.title.trim().isEmpty ? null : player.title.trim(),
        rating: player.rating > 0 ? player.rating : null,
      );

  final String id;
  final String name;
  final int? fideId;
  final String? federation;
  final String? title;
  final int? rating;

  _ParticipantData merge(Player player) => _ParticipantData(
    id: id,
    name: name.isNotEmpty ? name : _titleFreeDisplayName(player.name),
    fideId: fideId ?? (player.fideId > 0 ? player.fideId : null),
    federation:
        federation ?? (player.fed.trim().isEmpty ? null : player.fed.trim()),
    title: title ?? (player.title.trim().isEmpty ? null : player.title.trim()),
    rating: rating ?? (player.rating > 0 ? player.rating : null),
  );

  BracketParticipant get participant => BracketParticipant(
    id: id,
    name: name,
    fideId: fideId,
    federation: federation,
    title: title,
    rating: rating,
  );
}

String _normalizedPlayerName(String name) =>
    _titleFreeDisplayName(
      name,
    ).toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r'\s+'), ' ').trim();

bool _isPlaceholderParticipantName(String name) {
  final normalized =
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9?]+'), ' ').trim();
  return normalized == '?' ||
      normalized == 'tbd' ||
      normalized == 'tba' ||
      normalized == 'unknown' ||
      normalized == 'unknown player' ||
      normalized == 'to be determined' ||
      normalized.startsWith('winner of ') ||
      normalized.startsWith('loser of ');
}

String _titleFreeDisplayName(String name) =>
    name
        .trim()
        .replaceFirst(
          RegExp(
            r'^(?:(?:GM|IM|FM|CM|WGM|WIM|WFM|WCM|NM|WNM)\.?\s+)+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
