import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';

/// One block of the Combined list: a single round of a single category.
@immutable
class CombinedRoundSection {
  const CombinedRoundSection({
    required this.category,
    required this.round,
    required this.games,
    required this.startsAt,
    required this.hasStarted,
    required this.isFullyPlayed,
    required this.roundOrder,
  });

  final CombinedCategory category;

  /// The real round. Its id is unique across categories, so it doubles as
  /// the section id and keeps fold state in step with the single-category
  /// view of the same round.
  final GamesAppBarModel round;

  /// Pinned boards first, then board order.
  final List<GamesTourModel> games;

  /// When the round was played: its scheduled start, or the latest activity
  /// of its boards when the schedule is missing.
  final DateTime? startsAt;

  /// Whether play is under way or over, as opposed to published pairings.
  final bool hasStarted;
  final bool isFullyPlayed;

  /// Position of the round inside its own category, oldest first.
  final int roundOrder;
}

/// Lays every category's rounds out as one list.
///
/// Product order (Trello "Combined"):
///
/// 1. Whatever started latest is on top, so the rounds being played now lead
///    and yesterday's follow.
/// 2. Rounds that started together, which is the normal case for parallel
///    groups, read strongest category first (highest average rating), then
///    in picker order.
/// 3. Rounds not started yet close the list, soonest first. While nothing is
///    being played anywhere, each category's next round moves to the top
///    instead: its pairings are the next thing to watch.
List<CombinedRoundSection> buildCombinedRoundSections({
  required List<CombinedCategory> categories,
  required Map<String, List<GamesTourModel>> gamesByTourId,
  required Map<String, List<Round>> roundsByTourId,
  required List<String> liveRoundIds,
  Set<String> pinnedGameIds = const <String>{},
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final started = <CombinedRoundSection>[];
  final upcoming = <CombinedRoundSection>[];

  for (final category in categories) {
    final games = gamesByTourId[category.tourId];
    if (games == null || games.isEmpty) continue;

    final rounds = roundsByTourId[category.tourId] ?? const <Round>[];
    final roundOrderById = <String, int>{
      for (var i = 0; i < rounds.length; i++) rounds[i].id: i,
    };
    final roundsById = <String, Round>{
      for (final round in rounds) round.id: round,
    };

    final gamesByRoundId = <String, List<GamesTourModel>>{};
    for (final game in games) {
      (gamesByRoundId[game.roundId] ??= <GamesTourModel>[]).add(game);
    }

    for (final entry in gamesByRoundId.entries) {
      final roundGames = _orderBoards(entry.value, pinnedGameIds);
      final known = roundsById[entry.key];
      final model = known != null
          ? GamesAppBarModel.fromRound(known, liveRoundIds)
          : GamesAppBarModel(
              id: entry.key,
              name: _roundNameFromSlug(roundGames.first.roundSlug),
              startsAt: null,
              roundStatus: RoundStatus.ongoing,
              sourceRoundIds: <String>[entry.key],
            );

      final hasActivity = roundGames.any(
        (game) => game.hasStarted || game.effectiveGameStatus.isFinished,
      );
      final scheduled = model.startsAt;
      final hasStarted =
          hasActivity ||
          liveRoundIds.contains(entry.key) ||
          (scheduled != null && !scheduled.isAfter(effectiveNow));

      final section = CombinedRoundSection(
        category: category,
        round: model,
        games: roundGames,
        startsAt: scheduled ?? _latestActivity(roundGames),
        hasStarted: hasStarted,
        isFullyPlayed: roundGames.every(
          (game) => game.effectiveGameStatus.isFinished,
        ),
        // An unknown round is newer than the ones the schedule already has.
        roundOrder: roundOrderById[entry.key] ?? rounds.length,
      );
      (hasStarted ? started : upcoming).add(section);
    }
  }

  started.sort(_compareStarted);
  upcoming.sort(_compareUpcoming);

  final somethingIsBeingPlayed = started.any(
    (section) => !section.isFullyPlayed,
  );
  if (somethingIsBeingPlayed || upcoming.isEmpty) {
    return <CombinedRoundSection>[...started, ...upcoming];
  }

  // Between rounds: every category's next round leads.
  final nextByTourId = <String, CombinedRoundSection>{};
  for (final section in upcoming) {
    nextByTourId.putIfAbsent(section.category.tourId, () => section);
  }
  final next = nextByTourId.values.toSet();
  return <CombinedRoundSection>[
    ...upcoming.where(next.contains),
    ...started,
    ...upcoming.where((section) => !next.contains(section)),
  ];
}

int _compareStarted(CombinedRoundSection a, CombinedRoundSection b) {
  final byStart = _compareDates(a.startsAt, b.startsAt, latestFirst: true);
  if (byStart != 0) return byStart;
  final byCategory = _compareCategories(a.category, b.category);
  if (byCategory != 0) return byCategory;
  // Same category, same start: the later round is the newer one.
  return b.roundOrder.compareTo(a.roundOrder);
}

int _compareUpcoming(CombinedRoundSection a, CombinedRoundSection b) {
  final byStart = _compareDates(a.startsAt, b.startsAt, latestFirst: false);
  if (byStart != 0) return byStart;
  final byCategory = _compareCategories(a.category, b.category);
  if (byCategory != 0) return byCategory;
  return a.roundOrder.compareTo(b.roundOrder);
}

/// Undated rounds sink below dated ones in either direction.
int _compareDates(DateTime? a, DateTime? b, {required bool latestFirst}) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return latestFirst ? b.compareTo(a) : a.compareTo(b);
}

/// Strongest category first; unrated categories after rated ones.
int _compareCategories(CombinedCategory a, CombinedCategory b) {
  final byRating = (b.avgElo ?? -1).compareTo(a.avgElo ?? -1);
  return byRating != 0 ? byRating : a.order.compareTo(b.order);
}

List<GamesTourModel> _orderBoards(
  List<GamesTourModel> games,
  Set<String> pinnedGameIds,
) {
  final indexed = <(int, GamesTourModel)>[
    for (var i = 0; i < games.length; i++) (i, games[i]),
  ];
  indexed.sort((a, b) {
    final aPinned = pinnedGameIds.contains(a.$2.gameId);
    final bPinned = pinnedGameIds.contains(b.$2.gameId);
    if (aPinned != bPinned) return aPinned ? -1 : 1;
    final aBoard = a.$2.boardNr;
    final bBoard = b.$2.boardNr;
    if (aBoard != null && bBoard != null && aBoard != bBoard) {
      return aBoard.compareTo(bBoard);
    }
    if (aBoard == null && bBoard != null) return 1;
    if (aBoard != null && bBoard == null) return -1;
    // Keep the source order for boards the feed did not number.
    return a.$1.compareTo(b.$1);
  });
  return List<GamesTourModel>.unmodifiable([
    for (final entry in indexed) entry.$2,
  ]);
}

DateTime? _latestActivity(List<GamesTourModel> games) {
  DateTime? latest;
  for (final game in games) {
    final candidate = game.lastMoveTime ?? game.bucketDate;
    if (candidate == null) continue;
    if (latest == null || candidate.isAfter(latest)) latest = candidate;
  }
  return latest;
}

/// "round-3" reads "Round 3" until the schedule supplies the real name.
String _roundNameFromSlug(String? slug) {
  final words = (slug ?? '')
      .split(RegExp(r'[-_\s]+'))
      .where((word) => word.isNotEmpty);
  if (words.isEmpty) return 'Round';
  return words
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
