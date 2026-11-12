import '../../repository/supabase/game/games.dart';
import 'watch_models.dart';

/// One block of an event's list: a single round of a single section, with
/// the boards it has published. The same block the phone's Combined view
/// shows, laid out by the same rules, so the wrist and the phone read an
/// event in one order.
class WatchSection {
  const WatchSection({
    required this.tour,
    required this.label,
    required this.round,
    required this.games,
    required this.startsAt,
    required this.hasStarted,
    required this.isFullyPlayed,
    required this.roundOrder,
  });

  final WatchTour tour;

  /// The section as the phone's picker names it ("Group A", "Masters").
  final String label;
  final WatchRound round;

  /// Board order: numbered boards first, unnumbered ones after in feed order.
  final List<Games> games;

  /// When the round was played: its schedule, or the latest move on its
  /// boards when the schedule is missing.
  final DateTime? startsAt;

  /// Play is under way or over, as opposed to published pairings.
  final bool hasStarted;
  final bool isFullyPlayed;

  /// Position of the round inside its own section, oldest first.
  final int roundOrder;

  /// The round id, unique across sections.
  String get id => round.id;

  /// Team matches when this is a team round, else null.
  List<WatchTeamMatch>? get matches => watchTeamMatches(games);

  int get playing => games.where(watchGameIsPlaying).length;
}

/// Lays every section's rounds out as one list, the phone's Combined order:
///
/// 1. The strongest section first (highest average rating; unrated last).
///    Equally rated sections: the one that starts later first, then feed
///    order.
/// 2. Inside a section, the round that started latest first, then the
///    rounds still to come, soonest first. While none of the section's
///    boards is being played and a round is still to come, that next round
///    leads instead: its pairings are the next thing to watch there.
/// 3. Only rounds with boards get a block.
///
/// No board is listed twice: an organiser's own combined section, flagged by
/// the database or named so (when real sections exist beside it), is left
/// out, and so is any section whose boards are copies of the others' (see
/// [watchMirrorTourIds]).
List<WatchSection> watchEventSections({
  required List<WatchTour> tours,
  required List<WatchRound> rounds,
  required List<Games> games,
  required DateTime now,
  String? eventName,
}) {
  final real = [
    for (final tour in tours)
      if (!tour.isMirror &&
          !watchIsCombinedLabel(name: tour.name, slug: tour.slug))
        tour,
  ];
  final source = real.isEmpty ? tours : real;
  final order = {for (var i = 0; i < source.length; i++) source[i].id: i};
  final ranked = List<WatchTour>.of(source)
    ..sort((a, b) {
      final byRating = (b.avgElo ?? -1).compareTo(a.avgElo ?? -1);
      if (byRating != 0) return byRating;
      final byStart = _compareDates(a.startsAt, b.startsAt, latestFirst: true);
      return byStart != 0 ? byStart : order[a.id]!.compareTo(order[b.id]!);
    });

  // A round names its tour; one that does not (an older feed) is still
  // matched to its boards by id.
  final roundsByTour = <String, List<WatchRound>>{};
  final roundById = <String, WatchRound>{};
  for (final round in rounds) {
    roundById[round.id] = round;
    (roundsByTour[round.tourId] ??= []).add(round);
  }
  final gamesByTour = <String, List<Games>>{};
  for (final game in games) {
    (gamesByTour[game.tourId] ??= []).add(game);
  }
  final mirrors = watchMirrorTourIds(
    tourIds: [for (final tour in ranked) tour.id],
    gamesByTour: gamesByTour,
    roundsByTour: roundsByTour,
  );

  final sections = <WatchSection>[];
  for (final tour in ranked) {
    if (mirrors.contains(tour.id)) continue;
    final tourGames = gamesByTour[tour.id];
    if (tourGames == null || tourGames.isEmpty) continue;
    final schedule = roundsByTour[tour.id] ?? roundsByTour[''] ?? const [];
    final roundOrder = {
      for (var i = 0; i < schedule.length; i++) schedule[i].id: i,
    };
    final byRound = <String, List<Games>>{};
    for (final game in tourGames) {
      (byRound[game.roundId] ??= []).add(game);
    }
    final label = watchCategoryLabel(tour.name, groupName: eventName);
    final started = <WatchSection>[];
    final upcoming = <WatchSection>[];
    for (final entry in byRound.entries) {
      final boards = _orderBoards(entry.value);
      final round =
          roundById[entry.key] ??
          WatchRound(
            id: entry.key,
            name: _roundNameFromSlug(boards.first.roundSlug),
            tourId: tour.id,
          );
      final scheduled = round.startsAt;
      final hasStarted =
          boards.any(watchGameHasStarted) ||
          (scheduled != null && !scheduled.isAfter(now));
      final section = WatchSection(
        tour: tour,
        label: label,
        round: round,
        games: boards,
        startsAt: scheduled ?? _latestActivity(boards),
        hasStarted: hasStarted,
        isFullyPlayed: boards.every(watchGameIsFinished),
        // An unknown round is newer than the ones the schedule has.
        roundOrder: roundOrder[entry.key] ?? schedule.length,
      );
      (hasStarted ? started : upcoming).add(section);
    }
    started.sort(_compareStarted);
    upcoming.sort(_compareUpcoming);
    final playing = started.any((s) => s.playing > 0);
    if (!playing && upcoming.isNotEmpty) {
      sections.add(upcoming.removeAt(0));
    }
    sections
      ..addAll(started)
      ..addAll(upcoming);
  }
  return sections;
}

/// How far apart two rounds may start and still be the same sitting. An
/// organiser's copy of a round starts with the original, give or take the
/// seconds between two feeds; a replay or a tiebreak is hours away.
const Duration _sameSittingWindow = Duration(minutes: 30);

/// Sections whose boards are copies of boards in the other sections.
///
/// Two boards are the same game when the same player has White, the same
/// player has Black, and their rounds start within half an hour of each
/// other (or, unscheduled, carry the same round name). A section is a copy
/// when most of its boards are such copies. A copy and its original accuse
/// each other, so the section with more boards goes first: it is the one
/// that gathers several sections. Removing it clears what it repeated, and
/// the check runs again until nothing accuses anything.
Set<String> watchMirrorTourIds({
  required List<String> tourIds,
  required Map<String, List<Games>> gamesByTour,
  required Map<String, List<WatchRound>> roundsByTour,
}) {
  final boardsByTour = <String, List<_Board>>{};
  for (final tourId in tourIds) {
    final games = gamesByTour[tourId];
    if (games == null || games.length < 2) continue;
    final starts = {
      for (final round in roundsByTour[tourId] ?? const <WatchRound>[])
        round.id: round.startsAt,
    };
    boardsByTour[tourId] = [
      for (final game in games)
        _Board(
          pairing:
              '${_playerKey(game.players?.elementAtOrNull(0)?.name)}|'
              '${_playerKey(game.players?.elementAtOrNull(1)?.name)}',
          startsAt: starts[game.roundId],
          roundSlug: game.roundSlug,
        ),
    ];
  }
  if (boardsByTour.length < 2) return const {};

  final mirrors = <String>{};
  while (true) {
    final remaining = [
      for (final tourId in tourIds)
        if (boardsByTour.containsKey(tourId) && !mirrors.contains(tourId))
          tourId,
    ];
    if (remaining.length < 2) break;
    final byPairing = <String, List<(String, _Board)>>{};
    for (final tourId in remaining) {
      for (final board in boardsByTour[tourId]!) {
        (byPairing[board.pairing] ??= []).add((tourId, board));
      }
    }
    String? worst;
    var worstSize = 0;
    // Later in the list loses a tie, so of two identical sections the first
    // in rank order stays.
    for (final tourId in remaining.reversed) {
      final boards = boardsByTour[tourId]!;
      var copies = 0;
      for (final board in boards) {
        if (byPairing[board.pairing]!.any(
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
  final String roundSlug;

  bool isSameGameAs(_Board other) {
    final a = startsAt;
    final b = other.startsAt;
    if (a != null && b != null) {
      return a.difference(b).abs() <= _sameSittingWindow;
    }
    return roundSlug.isNotEmpty && roundSlug == other.roundSlug;
  }
}

String _playerKey(String? name) => (name ?? '').trim().toLowerCase();

int _compareStarted(WatchSection a, WatchSection b) {
  final byStart = _compareDates(a.startsAt, b.startsAt, latestFirst: true);
  if (byStart != 0) return byStart;
  return b.roundOrder.compareTo(a.roundOrder);
}

int _compareUpcoming(WatchSection a, WatchSection b) {
  final byStart = _compareDates(a.startsAt, b.startsAt, latestFirst: false);
  if (byStart != 0) return byStart;
  return a.roundOrder.compareTo(b.roundOrder);
}

/// Undated rounds sink below dated ones in either direction.
int _compareDates(DateTime? a, DateTime? b, {required bool latestFirst}) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return latestFirst ? b.compareTo(a) : a.compareTo(b);
}

List<Games> _orderBoards(List<Games> games) {
  final indexed = [for (var i = 0; i < games.length; i++) (i, games[i])];
  indexed.sort((a, b) {
    final aBoard = a.$2.boardNr;
    final bBoard = b.$2.boardNr;
    if (aBoard != null && bBoard != null && aBoard != bBoard) {
      return aBoard.compareTo(bBoard);
    }
    if (aBoard == null && bBoard != null) return 1;
    if (aBoard != null && bBoard == null) return -1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

DateTime? _latestActivity(List<Games> games) {
  DateTime? latest;
  for (final game in games) {
    final candidate = game.lastMoveTime;
    if (candidate == null) continue;
    if (latest == null || candidate.isAfter(latest)) latest = candidate;
  }
  return latest;
}

/// "round-3" reads "Round 3" until the schedule supplies the real name.
String _roundNameFromSlug(String slug) {
  final words = slug.split(RegExp(r'[-_\s]+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return 'Round';
  return words
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

/// What the event list is made of, in order: a section heading whenever the
/// section changes (only when the event has more than one), a round heading,
/// then the round's boards, each team match introduced by its match card.
/// Every item is one Digital Crown step.
sealed class WatchFeedItem {
  const WatchFeedItem(this.section);
  final WatchSection section;
  String get id;
}

class WatchCategoryItem extends WatchFeedItem {
  const WatchCategoryItem(super.section, {required this.rounds});

  /// How many rounds of this section the list holds.
  final int rounds;
  @override
  String get id => 'category-${section.tour.id}';
}

class WatchRoundItem extends WatchFeedItem {
  const WatchRoundItem(super.section);
  @override
  String get id => 'round-${section.id}';
}

class WatchMatchItem extends WatchFeedItem {
  const WatchMatchItem(super.section, this.match);
  final WatchTeamMatch match;
  @override
  String get id => 'match-${section.id}-${match.key}';
}

class WatchBoardItem extends WatchFeedItem {
  const WatchBoardItem(super.section, this.game, {this.match});
  final Games game;
  final WatchTeamMatch? match;
  @override
  String get id => 'board-${game.id}';
}

List<WatchFeedItem> watchFeedItems(List<WatchSection> sections) {
  final tourIds = {for (final section in sections) section.tour.id};
  final roundsPerTour = <String, int>{};
  for (final section in sections) {
    roundsPerTour[section.tour.id] = (roundsPerTour[section.tour.id] ?? 0) + 1;
  }
  final items = <WatchFeedItem>[];
  String? lastTour;
  for (final section in sections) {
    if (tourIds.length > 1 && section.tour.id != lastTour) {
      items.add(
        WatchCategoryItem(section, rounds: roundsPerTour[section.tour.id]!),
      );
    }
    lastTour = section.tour.id;
    items.add(WatchRoundItem(section));
    final matches = section.matches;
    if (matches == null) {
      items.addAll([
        for (final game in section.games) WatchBoardItem(section, game),
      ]);
      continue;
    }
    final inMatch = <String>{};
    for (final match in matches) {
      items.add(WatchMatchItem(section, match));
      for (final game in match.games) {
        inMatch.add(game.id);
        items.add(WatchBoardItem(section, game, match: match));
      }
    }
    // Boards without teams still belong to the round.
    items.addAll([
      for (final game in section.games)
        if (!inMatch.contains(game.id)) WatchBoardItem(section, game),
    ]);
  }
  return items;
}
