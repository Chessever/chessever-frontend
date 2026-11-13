import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_display_rounds.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
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
/// Combined only puts the same round of every category under one view; it
/// does not invent its own round order.
///
/// 1. Each category's rounds are ordered as its own Games tab orders them
///    ([selectGamesTourDisplayRounds]): the next round on top once the
///    latest one is fully played, played rounds latest first, the other
///    future rounds at the bottom.
/// 2. Categories that play the same rounds are merged round by round, the
///    strongest category first inside a round:
///
///      Group B, Round 8
///      Group C, Round 8
///      Group A, Round 8
///      Group B, Round 7
///      ...
///
///    "The same round" is the same round name ("Round 8") on the same day.
/// 3. Categories that share no round are separate blocks, and a block's
///    rounds always stay together: the Group Stage's Rounds 1-10 are never
///    split by the Blitz Tiebreak played the day before. Blocks still being
///    played come first (latest started first), then the finished ones, see
///    [_orderBlocks].
///
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
}) {
  final effectiveNow = now ?? DateTime.now();
  final ranked = List<CombinedCategory>.of(categories)
    ..sort(_compareCategories);
  final mirrorTourIds = findMirrorTourIds(
    tourIds: [for (final category in ranked) category.tourId],
    gamesByTourId: gamesByTourId,
    roundsByTourId: roundsByTourId,
  );

  // Every category's rounds, gathered by round name. Categories are visited
  // strongest first, so each group already lists them in rank order.
  final sectionsByCategory = <List<CombinedRoundSection>>[];
  for (final category in ranked) {
    if (mirrorTourIds.contains(category.tourId)) continue;
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

    final categorySections = <CombinedRoundSection>[];
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
      categorySections.add(
        CombinedRoundSection(
          category: category,
          round: model,
          games: roundGames,
          startsAt: scheduled ?? _latestActivity(roundGames),
          hasStarted:
              hasActivity ||
              liveRoundIds.contains(entry.key) ||
              (scheduled != null && !scheduled.isAfter(effectiveNow)),
          isFullyPlayed: roundGames.every(
            (game) => game.effectiveGameStatus.isFinished,
          ),
          // An unknown round is newer than the ones the schedule already has.
          roundOrder: roundOrderById[entry.key] ?? rounds.length,
        ),
      );
    }
    sectionsByCategory.add(categorySections);
  }

  // Each category's rounds in the order its own Games tab shows them: the
  // same selectGamesTourDisplayRounds call, category by category. Pooling
  // every category into one call breaks: that order sorts "Round N" by its
  // number alone, so a side event's Round 4 (Total Chess's Blitz Tiebreak,
  // Nov 10) lands beside the groups' Round 4 (Nov 12).
  final orderedByCategory = <List<CombinedRoundSection>>[
    for (final sections in sectionsByCategory)
      _inRegularOrder(sections, effectiveNow),
  ];

  // Categories that play the same rounds form one block; a category that
  // shares no round with the others is a block of its own.
  final blocks = <_Block>[
    for (final members in _blockMembers(orderedByCategory))
      _Block(
        _mergeByRound([for (final index in members) orderedByCategory[index]]),
        isOpen: _hasMoreToPlay(
          [for (final index in members) orderedByCategory[index]],
          roundsByTourId,
          effectiveNow,
        ),
      ),
  ];

  return <CombinedRoundSection>[
    for (final block in _orderBlocks(blocks)) ...block.sections,
  ];
}

/// Categories whose rounds are shown as one uninterrupted run of rounds.
class _Block {
  _Block(this.sections, {required this.isOpen});

  /// Round by round, in display order.
  final List<CombinedRoundSection> sections;

  /// Something is still to be played here: an unfinished round, or one the
  /// schedule has yet to start.
  final bool isOpen;

  late final bool hasStarted = sections.any(
    (section) => !_isPairingOnly(section),
  );

  /// When its latest played round started.
  late final DateTime? latestStart = _extremeStart(
    sections.where((section) => !_isPairingOnly(section)),
    latest: true,
  );

  late final DateTime? earliestStart = _extremeStart(sections, latest: false);
}

DateTime? _extremeStart(
  Iterable<CombinedRoundSection> sections, {
  required bool latest,
}) {
  DateTime? result;
  for (final section in sections) {
    final start = section.startsAt;
    if (start == null) continue;
    if (result == null ||
        (latest ? start.isAfter(result) : start.isBefore(result))) {
      result = start;
    }
  }
  return result;
}

/// Which categories (by index, strongest first) belong together: those that
/// share a round, directly or through another category. Blocks come out in
/// the order of their strongest category.
List<List<int>> _blockMembers(List<List<CombinedRoundSection>> byCategory) {
  final members = <List<int>>[];
  final keys = <Set<String>>[];
  for (var index = 0; index < byCategory.length; index++) {
    if (byCategory[index].isEmpty) continue;
    final own = {
      for (final section in byCategory[index]) combinedRoundKey(section),
    };
    int? target;
    for (var block = 0; block < members.length; block++) {
      if (!keys[block].any(own.contains)) continue;
      if (target == null) {
        target = block;
        continue;
      }
      // This category links two blocks that were apart until now.
      members[target].addAll(members[block]);
      keys[target].addAll(keys[block]);
      members.removeAt(block);
      keys.removeAt(block);
      block--;
    }
    if (target == null) {
      members.add(<int>[index]);
      keys.add(own);
    } else {
      members[target].add(index);
      keys[target].addAll(own);
    }
  }
  for (final block in members) {
    block.sort();
  }
  return members;
}

/// Merges the display orders of one block's categories, strongest category
/// first. A round another category already listed joins it; a new round goes
/// right after the previous round of its own category, or, when nothing of
/// its category is placed yet, by date among the rounds already there.
List<CombinedRoundSection> _mergeByRound(
  List<List<CombinedRoundSection>> orderedByCategory,
) {
  final keys = <String>[];
  final sectionsByKey = <String, List<CombinedRoundSection>>{};
  final dateByKey = <String, DateTime?>{};
  final futureKeys = <String>{};
  for (final sections in orderedByCategory) {
    int? previous;
    for (final section in sections) {
      final key = combinedRoundKey(section);
      final existing = keys.indexOf(key);
      if (existing >= 0) {
        previous = existing;
      } else {
        final at = previous != null
            ? previous + 1
            : _positionByDate(keys, dateByKey, futureKeys, section.startsAt);
        keys.insert(at, key);
        dateByKey[key] = section.startsAt;
        if (_isPairingOnly(section)) futureKeys.add(key);
        previous = at;
      }
      (sectionsByKey[key] ??= <CombinedRoundSection>[]).add(section);
    }
  }
  return <CombinedRoundSection>[for (final key in keys) ...sectionsByKey[key]!];
}

/// Whether these categories still have something to play: a round on the
/// list that is not over, or a round the schedule starts later (its pairings
/// may not be out yet).
bool _hasMoreToPlay(
  List<List<CombinedRoundSection>> byCategory,
  Map<String, List<Round>> roundsByTourId,
  DateTime now,
) {
  for (final sections in byCategory) {
    for (final section in sections) {
      final isOver =
          section.round.roundStatus == RoundStatus.completed ||
          section.isFullyPlayed;
      if (!isOver) return true;
    }
    final schedule =
        roundsByTourId[sections.first.category.tourId] ?? const <Round>[];
    if (schedule.any((round) => round.startsAt?.isAfter(now) ?? false)) {
      return true;
    }
  }
  return false;
}

/// The order of the blocks, the single-category rule one level up:
///
/// 1. Blocks being played (started, with more to play), latest started first.
/// 2. With none of those, the next block to start leads, as a category's
///    next round does once its latest round is fully played.
/// 3. Finished blocks, latest started first.
/// 4. Blocks not started yet, soonest first.
List<_Block> _orderBlocks(List<_Block> blocks) {
  if (blocks.length < 2) return blocks;
  final rank = <_Block, int>{
    for (var i = 0; i < blocks.length; i++) blocks[i]: i,
  };
  int byRank(_Block a, _Block b) => rank[a]!.compareTo(rank[b]!);
  int latestFirst(_Block a, _Block b) {
    final byStart = _compareDates(
      a.latestStart,
      b.latestStart,
      latestFirst: true,
    );
    return byStart != 0 ? byStart : byRank(a, b);
  }

  final inPlay = blocks.where((b) => b.hasStarted && b.isOpen).toList()
    ..sort(latestFirst);
  final finished = blocks.where((b) => b.hasStarted && !b.isOpen).toList()
    ..sort(latestFirst);
  final upcoming = blocks.where((b) => !b.hasStarted).toList()
    ..sort((a, b) {
      final byStart = _compareDates(
        a.earliestStart,
        b.earliestStart,
        latestFirst: false,
      );
      return byStart != 0 ? byStart : byRank(a, b);
    });
  final promoted = inPlay.isEmpty && upcoming.isNotEmpty
      ? upcoming.removeAt(0)
      : null;
  return <_Block>[...inPlay, ?promoted, ...finished, ...upcoming];
}

/// One category's [sections] in the order its Games tab shows its rounds,
/// with the same inputs the regular grouping builds
/// (gamesTourGroupedProvider): only boards with a move or a result count as
/// played, and an open round whose boards are all unplayed pairings is a
/// pairing-only round. So at most the next round is promoted to the top
/// (when the latest round is fully played) and the other future rounds sit
/// at the bottom.
List<CombinedRoundSection> _inRegularOrder(
  List<CombinedRoundSection> sections,
  DateTime now,
) {
  final byRoundId = <String, CombinedRoundSection>{
    for (final section in sections) section.round.id: section,
  };
  final rounds = [for (final section in sections) section.round];
  final ordered = selectGamesTourDisplayRounds(
    rounds: rounds,
    effectiveRounds: rounds,
    gamesByRound: {
      for (final section in sections) section.round.id: section.games,
    },
    upcomingPairingRoundIds: {
      for (final section in sections)
        if (_isPairingOnly(section)) section.round.id,
    },
    isSearchMode: false,
    isMultiStageKnockout: false,
    now: now,
  );
  return [for (final round in ordered) byRoundId[round.id]!];
}

/// An open round with no board the regular list would show as played.
bool _isPairingOnly(CombinedRoundSection section) =>
    section.round.roundStatus != RoundStatus.completed &&
    !section.games.any(isEventBoardGameVisible);

/// Where a round with nothing of its own category placed yet goes: above the
/// first played round that started before it. Future rounds at the bottom
/// stay the bottom, so a side event played earlier lands above them.
int _positionByDate(
  List<String> keys,
  Map<String, DateTime?> dateByKey,
  Set<String> futureKeys,
  DateTime? date,
) {
  var tail = keys.length;
  while (tail > 0 && futureKeys.contains(keys[tail - 1])) {
    tail--;
  }
  if (date == null) return tail;
  for (var i = 0; i < tail; i++) {
    if (futureKeys.contains(keys[i])) continue;
    final other = dateByKey[keys[i]];
    if (other == null || other.isBefore(date)) return i;
  }
  return tail;
}

/// Same round across categories: the same name ("Round 8", "round 8" and
/// "Round  8" agree) played on the same day. A side event that reuses the
/// names on another day (Total Chess's Blitz Tiebreak ran its Rounds 1-9
/// the day before the groups' Rounds 1-10) keeps rounds of its own.
String combinedRoundKey(CombinedRoundSection section) {
  final name = section.round.name.trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  final start = section.startsAt?.toUtc();
  if (start == null) return name;
  return '$name@${start.year}-${start.month}-${start.day}';
}

/// The round as the regular order sees it, from all its categories: the
/// earliest start, and the most active status any of them has.
GamesAppBarModel combinedStandInRound(
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
