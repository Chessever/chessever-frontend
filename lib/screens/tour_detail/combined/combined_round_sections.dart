import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_ordering.dart';
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

  /// Scheduled start, falling back to creation time like web, then board
  /// activity for rounds not yet returned by the schedule.
  final DateTime? startsAt;

  /// Whether play is under way or over, as opposed to published pairings.
  final bool hasStarted;

  /// Every board has a result. False for a round with no boards yet.
  final bool isFullyPlayed;

  /// Position of the round inside its own category, oldest first.
  final int roundOrder;
}

/// Lays every category's rounds out as one list.
///
/// Combined only puts the same round of every category under one view; it
/// does not invent its own round order. Rounds are ordered by
/// [sortRoundsForDisplay], the rule a single category's Games tab uses, and
/// inside one round each category gets its own block, strongest first:
///
///   Group B, Round 8
///   Group C, Round 8
///   Group A, Round 8
///   Group B, Round 7
///   ...
///
/// "The same round" is the same round name ("Round 8") on the same day.
/// Categories are ranked by average rating; equally rated ones by the later
/// start, then picker order.
///
/// No board is listed twice: a category whose boards are copies of the other
/// categories' boards (an organizer's own combined section that nobody
/// flagged) is left out, see [findMirrorTourIds].
List<CombinedRoundSection> buildCombinedRoundSections({
  required List<CombinedCategory> categories,
  required Map<String, List<GamesTourModel>> gamesByTourId,
  required Map<String, List<Round>> roundsByTourId,
  required List<String> liveRoundIds,
  Set<String> pinnedGameIds = const <String>{},
  DateTime? now,
  bool includeEmptyRounds = false,
}) {
  final effectiveNow = now ?? DateTime.now();
  final ranked = List<CombinedCategory>.of(categories)
    ..sort(_compareCategories);
  final mirrorTourIds = findMirrorTourIds(
    tourIds: [for (final category in ranked) category.tourId],
    gamesByTourId: gamesByTourId,
    roundsByTourId: roundsByTourId,
  );

  // Every category's rounds, gathered by round. Categories are visited
  // strongest first, so each group already lists them in rank order.
  final sectionsByKey = <String, List<CombinedRoundSection>>{};
  for (final category in ranked) {
    if (mirrorTourIds.contains(category.tourId)) continue;
    final games = gamesByTourId[category.tourId] ?? const <GamesTourModel>[];
    if (!includeEmptyRounds && games.isEmpty) continue;

    final rounds = roundsByTourId[category.tourId] ?? const <Round>[];
    final roundsById = <String, Round>{
      for (final round in rounds) round.id: round,
    };
    final roundOrderById = <String, int>{
      for (var i = 0; i < rounds.length; i++) rounds[i].id: i,
    };

    final gamesByRoundId = <String, List<GamesTourModel>>{};
    for (final game in games) {
      (gamesByRoundId[game.roundId] ??= <GamesTourModel>[]).add(game);
    }

    if (includeEmptyRounds) {
      for (final round in rounds) {
        gamesByRoundId.putIfAbsent(round.id, () => <GamesTourModel>[]);
      }
    }
    if (gamesByRoundId.isEmpty) continue;
    final sections = <CombinedRoundSection>[];
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
      final startsAt =
          scheduled ?? known?.createdAt ?? _latestActivity(roundGames);
      final hasStarted =
          hasActivity ||
          liveRoundIds.contains(entry.key) ||
          (startsAt != null && !startsAt.isAfter(effectiveNow));

      final section = CombinedRoundSection(
        category: category,
        round: model,
        games: roundGames,
        startsAt: startsAt,
        hasStarted: hasStarted,
        isFullyPlayed:
            roundGames.isNotEmpty &&
            roundGames.every((game) => game.effectiveGameStatus.isFinished),
        // An unknown round is newer than the ones the schedule already has.
        roundOrder: roundOrderById[entry.key] ?? rounds.length,
      );
      sections.add(section);
    }
    // Two rounds of one category under one name: the later first.
    sections.sort((a, b) => b.roundOrder.compareTo(a.roundOrder));
    for (final section in sections) {
      (sectionsByKey[_roundKey(section)] ??= <CombinedRoundSection>[]).add(
        section,
      );
    }
  }

  // One stand-in per round, carrying what its categories say together, so
  // the regular round order decides where the round goes.
  final standIns = <GamesAppBarModel>[
    for (final entry in sectionsByKey.entries)
      _standInRound(entry.key, entry.value),
  ];
  final ordered = sortRoundsForDisplay(
    standIns,
    resolveDate: (round) => round.startsAt,
    hasGames: (round) =>
        sectionsByKey[round.id]!.any((section) => section.games.isNotEmpty),
    hasStartedActivity: (round) =>
        sectionsByKey[round.id]!.any((section) => section.hasStarted),
    isRoundFullyPlayed: (round) => sectionsByKey[round.id]!.every(
      (section) =>
          section.round.roundStatus == RoundStatus.completed ||
          section.isFullyPlayed,
    ),
    now: effectiveNow,
  );

  return <CombinedRoundSection>[
    for (final round in ordered) ...sectionsByKey[round.id]!,
  ];
}

/// Same round across categories: the same name ("Round 8", "round 8" and
/// "Round  8" agree) played on the same day. A side event that reuses the
/// names on another day (Total Chess's Blitz Tiebreak ran its Rounds 1-9
/// the day before the groups' Rounds 1-10) keeps rounds of its own.
String _roundKey(CombinedRoundSection section) {
  final name = section.round.name.trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  final start = (section.round.startsAt ?? section.startsAt)?.toUtc();
  if (start == null) return name;
  return '$name@${start.year}-${start.month}-${start.day}';
}

/// The round as the regular order sees it, from all its categories: the
/// earliest start, and the most active status any of them has.
GamesAppBarModel _standInRound(
  String key,
  List<CombinedRoundSection> sections,
) {
  DateTime? startsAt;
  for (final section in sections) {
    final start = section.round.startsAt;
    if (start != null && (startsAt == null || start.isBefore(startsAt))) {
      startsAt = start;
    }
  }
  bool any(RoundStatus status) =>
      sections.any((section) => section.round.roundStatus == status);
  final status = any(RoundStatus.live)
      ? RoundStatus.live
      : any(RoundStatus.ongoing)
      ? RoundStatus.ongoing
      : any(RoundStatus.upcoming)
      ? RoundStatus.upcoming
      : RoundStatus.completed;
  return GamesAppBarModel(
    id: key,
    name: sections.first.round.name,
    startsAt: startsAt,
    roundStatus: status,
    sourceRoundIds: [for (final section in sections) section.round.id],
  );
}

/// How far apart two rounds may start and still be the same sitting. An
/// organizer's copy of a round starts with the original, give or take the
/// seconds between two feeds; a replay or a tiebreak of the same pairing is
/// hours away.
const Duration _sameSittingWindow = Duration(minutes: 30);

/// Tours whose boards are copies of boards in the other tours.
///
/// Some organizers publish a section that repeats every board of the real
/// sections (Total Chess "Group Stage Combined"). The database flags those
/// and their names say so, and both are filtered before this runs. This is
/// the last line: it reads the boards themselves, so a mirror that was
/// neither flagged nor named still cannot put a game on the list twice.
///
/// Two boards are the same game when the same player has White, the same
/// player has Black, and their rounds start within half an hour of each
/// other. A tour is a mirror when most of its boards are such copies. A copy
/// and its original always accuse each other, so the tour with more boards
/// goes first: it is the one that gathers several sections. Removing it
/// clears the sections it repeated, and the check runs again until nothing
/// accuses anything.
@visibleForTesting
Set<String> findMirrorTourIds({
  required List<String> tourIds,
  required Map<String, List<GamesTourModel>> gamesByTourId,
  required Map<String, List<Round>> roundsByTourId,
}) {
  final boardsByTourId = <String, List<_Board>>{};
  for (final tourId in tourIds) {
    final games = gamesByTourId[tourId];
    if (games == null || games.length < 2) continue;
    final startsByRoundId = <String, DateTime?>{
      for (final round in roundsByTourId[tourId] ?? const <Round>[])
        round.id: round.startsAt,
    };
    boardsByTourId[tourId] = [
      for (final game in games)
        _Board(
          pairing:
              '${_playerKey(game.whitePlayer.name)}|'
              '${_playerKey(game.blackPlayer.name)}',
          startsAt: startsByRoundId[game.roundId],
          roundSlug: game.roundSlug,
        ),
    ];
  }
  if (boardsByTourId.length < 2) return const <String>{};

  final mirrors = <String>{};
  while (true) {
    final remaining = [
      for (final tourId in tourIds)
        if (boardsByTourId.containsKey(tourId) && !mirrors.contains(tourId))
          tourId,
    ];
    if (remaining.length < 2) break;

    final boardsByPairing = <String, List<(String, _Board)>>{};
    for (final tourId in remaining) {
      for (final board in boardsByTourId[tourId]!) {
        (boardsByPairing[board.pairing] ??= <(String, _Board)>[]).add((
          tourId,
          board,
        ));
      }
    }

    String? worst;
    var worstSize = 0;
    // Later in the list loses a tie, so of two identical tours the first in
    // rank order stays.
    for (final tourId in remaining.reversed) {
      final boards = boardsByTourId[tourId]!;
      var copies = 0;
      for (final board in boards) {
        final candidates = boardsByPairing[board.pairing]!;
        if (candidates.any(
          (other) => other.$1 != tourId && board.isSameGameAs(other.$2),
        )) {
          copies++;
        }
      }
      if (copies * 2 > boards.length && boards.length > worstSize) {
        worst = tourId;
        worstSize = boards.length;
      }
    }
    if (worst == null) break;
    mirrors.add(worst);
  }
  return mirrors;
}

class _Board {
  const _Board({
    required this.pairing,
    required this.startsAt,
    required this.roundSlug,
  });

  final String pairing;
  final DateTime? startsAt;
  final String? roundSlug;

  bool isSameGameAs(_Board other) {
    final a = startsAt;
    final b = other.startsAt;
    if (a != null && b != null) {
      return a.difference(b).abs() <= _sameSittingWindow;
    }
    // No schedule to compare: the copy keeps the round's own name.
    return roundSlug != null && roundSlug == other.roundSlug;
  }
}

/// A copy comes from the same feed as its original, so the name is spelled
/// the same; only case and stray spaces are evened out.
String _playerKey(String name) => name.trim().toLowerCase();

/// Undated rounds sink below dated ones in either direction.
int _compareDates(DateTime? a, DateTime? b, {required bool latestFirst}) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return latestFirst ? b.compareTo(a) : a.compareTo(b);
}

/// Strongest category first; unrated categories after rated ones. Equal
/// ratings: the category that starts later, then picker order.
int _compareCategories(CombinedCategory a, CombinedCategory b) {
  final byRating = (b.avgElo ?? -1).compareTo(a.avgElo ?? -1);
  if (byRating != 0) return byRating;
  final byStart = _compareDates(a.startsAt, b.startsAt, latestFirst: true);
  return byStart != 0 ? byStart : a.order.compareTo(b.order);
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
