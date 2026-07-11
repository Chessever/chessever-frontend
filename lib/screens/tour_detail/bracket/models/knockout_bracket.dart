import 'dart:collection';

import 'package:chessever2/repository/supabase/game/games.dart';

enum KnockoutStageState { upcoming, inProgress, completed }

class BracketParticipant {
  const BracketParticipant({
    required this.id,
    required this.name,
    this.fideId,
    this.federation,
    this.title,
    this.rating,
  });

  final String id;
  final String name;
  final int? fideId;
  final String? federation;
  final String? title;
  final int? rating;

  String get displayName {
    final participantTitle = title;
    return participantTitle == null || participantTitle.isEmpty
        ? name
        : '$participantTitle $name';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BracketParticipant && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class KnockoutMatch {
  KnockoutMatch({
    required this.key,
    required this.stageKey,
    required this.participant1,
    required this.participant2,
    required List<Games> games,
    required this.participant1Score,
    required this.participant2Score,
    required this.leader,
    required this.winner,
    required this.minimumBoardOrder,
    required this.isComplete,
    required this.isLive,
  }) : games = UnmodifiableListView(games);

  final String key;
  final String stageKey;
  final BracketParticipant participant1;
  final BracketParticipant participant2;
  final List<Games> games;
  final double participant1Score;
  final double participant2Score;
  final BracketParticipant? leader;
  final BracketParticipant? winner;
  final int? minimumBoardOrder;
  final bool isComplete;
  final bool isLive;

  bool get isTied => participant1Score == participant2Score;
  bool get hasUnfinishedGames => !isComplete;

  List<String> get sourceGameIds =>
      List.unmodifiable(games.map((game) => game.id));

  List<String> get sourceRoundIds =>
      List.unmodifiable(games.map((game) => game.roundId).toSet());

  List<String> get sourceTourIds =>
      List.unmodifiable(games.map((game) => game.tourId).toSet());

  bool containsParticipant(String participantId) =>
      participant1.id == participantId || participant2.id == participantId;

  BracketParticipant? participantById(String participantId) {
    if (participant1.id == participantId) return participant1;
    if (participant2.id == participantId) return participant2;
    return null;
  }

  KnockoutMatch copyWith({BracketParticipant? winner}) => KnockoutMatch(
    key: key,
    stageKey: stageKey,
    participant1: participant1,
    participant2: participant2,
    games: games,
    participant1Score: participant1Score,
    participant2Score: participant2Score,
    leader: leader,
    winner: winner ?? this.winner,
    minimumBoardOrder: minimumBoardOrder,
    isComplete: isComplete,
    isLive: isLive,
  );
}

class KnockoutStage {
  KnockoutStage({
    required this.key,
    required this.label,
    required List<String> sourceTourIds,
    required List<String> sourceRoundIds,
    required this.order,
    required this.state,
    required this.isLive,
    required List<KnockoutMatch> matches,
  }) : sourceTourIds = UnmodifiableListView(sourceTourIds),
       sourceRoundIds = UnmodifiableListView(sourceRoundIds),
       matches = UnmodifiableListView(matches);

  final String key;
  final String label;
  final List<String> sourceTourIds;
  final List<String> sourceRoundIds;
  final int order;
  final KnockoutStageState state;
  final bool isLive;
  final List<KnockoutMatch> matches;

  bool get isComplete => state == KnockoutStageState.completed;

  KnockoutStage copyWith({List<KnockoutMatch>? matches}) => KnockoutStage(
    key: key,
    label: label,
    sourceTourIds: sourceTourIds,
    sourceRoundIds: sourceRoundIds,
    order: order,
    state: state,
    isLive: isLive,
    matches: matches ?? this.matches,
  );
}

class KnockoutEdge {
  const KnockoutEdge({
    required this.sourceMatchKey,
    required this.destinationMatchKey,
    required this.participantId,
  });

  final String sourceMatchKey;
  final String destinationMatchKey;
  final String participantId;
}

class KnockoutBracket {
  KnockoutBracket({
    required List<KnockoutStage> stages,
    required List<KnockoutEdge> edges,
    required this.selectedStageKey,
    required this.currentStageKey,
    required this.isPartial,
  }) : stages = UnmodifiableListView(stages),
       edges = UnmodifiableListView(edges);

  final List<KnockoutStage> stages;
  final List<KnockoutEdge> edges;
  final String? selectedStageKey;
  final String? currentStageKey;
  final bool isPartial;

  bool get isEmpty => stages.every((stage) => stage.matches.isEmpty);

  KnockoutStage? stageByKey(String key) {
    for (final stage in stages) {
      if (stage.key == key) return stage;
    }
    return null;
  }

  KnockoutMatch? matchByKey(String key) {
    for (final stage in stages) {
      for (final match in stage.matches) {
        if (match.key == key) return match;
      }
    }
    return null;
  }
}
