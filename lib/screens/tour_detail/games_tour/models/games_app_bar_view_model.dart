import 'package:equatable/equatable.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/utils/time_utils.dart';

enum RoundStatus { completed, ongoing, live, upcoming }

class GamesAppBarViewModel {
  const GamesAppBarViewModel({
    required this.gamesAppBarModels,
    required this.selectedId,
    this.userSelectedId = false,
  });

  final String selectedId;
  final bool userSelectedId;
  final List<GamesAppBarModel> gamesAppBarModels;
}

class GamesAppBarModel extends Equatable {
  const GamesAppBarModel({
    required this.id,
    required this.name,
    required this.startsAt,
    required this.roundStatus,
  });

  final String id;
  final String name;
  final DateTime? startsAt;
  final RoundStatus roundStatus;

  factory GamesAppBarModel.fromRound(Round round, List<String> liveRound) {
    final utcStart = round.startsAt;
    final startsAt = TimeUtils.toLocal(utcStart);

    return GamesAppBarModel(
      id: round.id,
      name: round.name,
      startsAt: startsAt,
      roundStatus: status(
        currentId: round.id,
        startsAt: startsAt,
        liveRound: liveRound,
      ),
    );
  }

  static RoundStatus status({
    required DateTime? startsAt,
    required String currentId,
    required List<String> liveRound,
  }) {
    final now = DateTime.now();

    if (liveRound.isNotEmpty && liveRound.contains(currentId)) {
      return RoundStatus.live;
    }

    if (startsAt == null) return RoundStatus.upcoming;

    if (startsAt.isBefore(now) || startsAt.isAtSameMomentAs(now)) {
      // Day-boundary fix: a round that started at 23:50 must not flip to
      // `completed` at local midnight while still in progress. Use a rolling
      // 24h window instead of same-calendar-day. Backend `liveRound`
      // membership (checked above) is the authoritative live signal; this
      // ongoing/completed classification is a fallback for rounds that the
      // backend has dropped from `live_round_ids` but that are still within
      // a plausible play window for any time control.
      // See docs/superpowers/specs/2026-05-29-realtime-live-games-implementation-plan.md
      // change #4.
      final hoursSinceStart = now.difference(startsAt).inHours;
      if (hoursSinceStart < 24) {
        return RoundStatus.ongoing;
      } else {
        return RoundStatus.completed;
      }
    } else {
      return RoundStatus.upcoming;
    }
  }

  /// ✅ Added copyWith method
  GamesAppBarModel copyWith({
    String? id,
    String? name,
    DateTime? startsAt,
    RoundStatus? roundStatus,
  }) {
    return GamesAppBarModel(
      id: id ?? this.id,
      name: name ?? this.name,
      startsAt: startsAt ?? this.startsAt,
      roundStatus: roundStatus ?? this.roundStatus,
    );
  }

  String get formattedStartDate => TimeUtils.formatSingleDate(startsAt);

  /// Formatted date for round dropdown: "29 Dec 2025, 17:00 UTC"
  String get formattedRoundDateTime => TimeUtils.formatRoundDateTime(startsAt);

  @override
  List<Object?> get props => [id, name, startsAt, roundStatus];
}
