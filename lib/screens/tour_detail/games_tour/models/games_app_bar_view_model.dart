import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../../repository/supabase/round/round.dart';
import '../../../../utils/time_utils.dart';

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

    if (startsAt == null) return RoundStatus.upcoming;

    // Check if this round is currently live
    if (liveRound.isNotEmpty && liveRound.contains(currentId)) {
      return RoundStatus.live;
    }

    // Check if round has started
    if (startsAt.isBefore(now) || startsAt.isAtSameMomentAs(now)) {
      // If it's the same day as start, consider it ongoing
      if (startsAt.day == now.day &&
          startsAt.month == now.month &&
          startsAt.year == now.year) {
        return RoundStatus.ongoing;
      } else {
        // Started on a previous day, so completed
        return RoundStatus.completed;
      }
    } else {
      // Round hasn't started yet
      return RoundStatus.upcoming;
    }
  }

  String get formattedStartDate => TimeUtils.formatSingleDate(startsAt);

  @override
  List<Object?> get props => [id, name, startsAt];
}
