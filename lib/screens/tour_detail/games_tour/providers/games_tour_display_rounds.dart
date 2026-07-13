import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// Selects and orders the rounds actually painted by the regular Games list.
///
/// Keep this as the single source of truth for the renderer and every scroll
/// consumer. In particular, populated synthetic knockout stages stay visible
/// even when their coarse status is `upcoming`.
List<GamesAppBarModel> selectGamesTourDisplayRounds({
  required List<GamesAppBarModel> rounds,
  required List<GamesAppBarModel> effectiveRounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  required Set<String> upcomingPairingRoundIds,
  required bool isSearchMode,
  required bool isMultiStageKnockout,
  String? selectedRoundId,
  bool userSelected = false,
  DateTime? now,
}) {
  final sourceRounds =
      (isSearchMode ? effectiveRounds : rounds)
          .where((round) => !upcomingPairingRoundIds.contains(round.id))
          .toList();

  final isPreConfigured = sourceRounds.every((round) => round.startsAt != null);
  final hasLiveOrOngoing = sourceRounds.any(
    (round) =>
        round.roundStatus == RoundStatus.live ||
        round.roundStatus == RoundStatus.ongoing,
  );
  final hasCompleted = sourceRounds.any(
    (round) => round.roundStatus == RoundStatus.completed,
  );
  final allAreUpcoming = sourceRounds.every(
    (round) =>
        round.roundStatus == RoundStatus.upcoming ||
        (gamesByRound[round.id]?.isEmpty ?? true),
  );

  final visibleRounds =
      sourceRounds.where((round) {
        final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
        if (roundGames.isEmpty) return false;
        if (isSearchMode || isMultiStageKnockout || isPreConfigured) {
          return true;
        }
        if (userSelected && round.id == selectedRoundId) return true;
        if (allAreUpcoming) return true;
        if (hasLiveOrOngoing) {
          return round.roundStatus != RoundStatus.upcoming;
        }
        if (hasCompleted && round.roundStatus == RoundStatus.upcoming) {
          final upcomingRounds =
              sourceRounds
                  .where(
                    (candidate) =>
                        candidate.roundStatus == RoundStatus.upcoming &&
                        (gamesByRound[candidate.id]?.isNotEmpty ?? false),
                  )
                  .toList()
                ..sort(_compareRoundsByStartAscending);
          return upcomingRounds.isNotEmpty &&
              upcomingRounds.first.id == round.id;
        }
        return round.roundStatus != RoundStatus.upcoming;
      }).toList();

  final upcomingPairingRounds =
      effectiveRounds
          .where((round) => upcomingPairingRoundIds.contains(round.id))
          .toList();
  GamesAppBarModel? topPairingRound;
  if (upcomingPairingRounds.isNotEmpty) {
    final next = upcomingPairingRounds.first;
    final startsAt = next.startsAt;
    if (startsAt != null &&
        startsAt.difference(now ?? DateTime.now()) < const Duration(hours: 1)) {
      topPairingRound = next;
    }
  }

  return List<GamesAppBarModel>.unmodifiable(<GamesAppBarModel>[
    if (topPairingRound != null) topPairingRound,
    ...visibleRounds,
    ...upcomingPairingRounds.where((round) => round != topPairingRound),
  ]);
}

int _compareRoundsByStartAscending(
  GamesAppBarModel left,
  GamesAppBarModel right,
) {
  final leftStart = left.startsAt;
  final rightStart = right.startsAt;
  if (leftStart == null && rightStart == null) {
    return left.name.compareTo(right.name);
  }
  if (leftStart == null) return 1;
  if (rightStart == null) return -1;
  final start = leftStart.compareTo(rightStart);
  return start != 0 ? start : left.name.compareTo(right.name);
}
