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
}

/// Orders real source rounds like the web Combined view: overlapping source
/// schedules stay in one block, including their future pairings. Inside each
/// block, played rounds come newest first, then future rounds soonest first,
/// with knockout stage and source rating breaking ties.
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

  final schedules = <_CombinedSourceSchedule>[];
  for (final category in ranked) {
    if (mirrorTourIds.contains(category.tourId)) continue;
    final games = gamesByTourId[category.tourId];
    if (games == null || games.isEmpty) continue;

    final rounds = roundsByTourId[category.tourId] ?? const <Round>[];
    final roundsById = <String, Round>{
      for (final round in rounds) round.id: round,
    };

    final gamesByRoundId = <String, List<GamesTourModel>>{};
    for (final game in games) {
      (gamesByRoundId[game.roundId] ??= <GamesTourModel>[]).add(game);
    }

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
      );
      sections.add(section);
    }
    // Read the whole source schedule, including rounds without games yet.
    // Missing pairings must not split parallel groups into separate blocks.
    final dates = [
      for (final round in rounds) round.startsAt ?? round.createdAt,
      for (final section in sections)
        if (!roundsById.containsKey(section.round.id))
          section.startsAt ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ]..sort();
    schedules.add(
      _CombinedSourceSchedule(
        first: dates.first,
        last: dates.last,
        sections: sections,
      ),
    );
  }
  schedules.sort((a, b) => a.first.compareTo(b.first));

  // Like web combinedRounds, merge overlapping intervals transitively. Source
  // ids own these schedules; matching labels or round numbers do not.
  final blocks = <_CombinedSourceSchedule>[];
  for (final schedule in schedules) {
    if (blocks.isNotEmpty && !schedule.first.isAfter(blocks.last.last)) {
      final previous = blocks.last;
      if (schedule.last.isAfter(previous.last)) previous.last = schedule.last;
      previous.sections.addAll(schedule.sections);
    } else {
      blocks.add(schedule);
    }
  }
  for (final block in blocks) {
    block.sections.sort(_compareSections);
  }
  blocks.sort((a, b) => _compareSections(a.sections.first, b.sections.first));
  return [for (final block in blocks) ...block.sections];
}

class _CombinedSourceSchedule {
  _CombinedSourceSchedule({
    required this.first,
    required this.last,
    required this.sections,
  });

  final DateTime first;
  DateTime last;
  final List<CombinedRoundSection> sections;
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

/// Same precedence as web `combinedRounds`; future pairings never cover play.
int _compareSections(CombinedRoundSection a, CombinedRoundSection b) {
  final byFuture = (a.hasStarted ? 0 : 1).compareTo(b.hasStarted ? 0 : 1);
  if (byFuture != 0) return byFuture;
  final byStart = _compareDates(
    a.startsAt,
    b.startsAt,
    latestFirst: a.hasStarted,
  );
  if (byStart != 0) return byStart;
  final byStage = _stageRank(a).compareTo(_stageRank(b));
  if (byStage != 0) return byStage;
  final byRating = (b.category.avgElo ?? -1).compareTo(a.category.avgElo ?? -1);
  if (byRating != 0) return byRating;
  final byTour = a.category.tourId.compareTo(b.category.tourId);
  return byTour != 0 ? byTour : a.round.id.compareTo(b.round.id);
}

int _stageRank(CombinedRoundSection section) =>
    _namedStageRank(section.round.name) ??
    _namedStageRank(section.category.sourceName ?? section.category.label) ??
    0x7fffffff;

// Match the web stage precedence; generic "Round 2" is not a knockout stage.
int? _namedStageRank(String name) {
  bool matches(String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(name);
  if (matches(r'\bgrand[\s-]*finals?\b')) return 1;
  if (matches(r'\b(?:3rd|third)[\s-]*place\b|\bbronze\b')) return 3;
  if (matches(r'\bsemi[\s-]*finals?\b')) return 4;
  if (matches(r'\bquarter[\s-]*finals?\b')) return 8;
  final field = RegExp(
    r'\b(?:round of|last)\s+(\d+)\b|\bro(\d+)\b',
    caseSensitive: false,
  ).firstMatch(name);
  if (field != null) {
    final size = int.tryParse(field.group(1) ?? field.group(2)!);
    return size != null && size > 0 ? size : null;
  }
  return matches(r'\bfinals?\b') ? 2 : null;
}

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
