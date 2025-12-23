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

    // Debug: log round start times
    print('📅 Round "${round.name}" startsAt: $startsAt (from DB: ${round.startsAt})');

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

    if (startsAt == null) return RoundStatus.upcoming;

    if (liveRound.isNotEmpty && liveRound.contains(currentId)) {
      return RoundStatus.live;
    }

    if (startsAt.isBefore(now) || startsAt.isAtSameMomentAs(now)) {
      if (startsAt.day == now.day &&
          startsAt.month == now.month &&
          startsAt.year == now.year) {
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
