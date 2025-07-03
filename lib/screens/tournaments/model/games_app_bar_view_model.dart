import 'package:equatable/equatable.dart';

import '../../../repository/supabase/round/round.dart';

enum RoundStatus { completed, current, upcoming }

class GamesAppBarViewModel {
  const GamesAppBarViewModel({
    required this.gamesAppBarModels,
    required this.selectedId,
  });

  final String selectedId;
  final List<GamesAppBarModel> gamesAppBarModels;
}

class GamesAppBarModel extends Equatable {
  const GamesAppBarModel({
    required this.id,
    required this.name,
    required this.startsAt,
  });

  final String id;
  final String name;
  final DateTime? startsAt;

  factory GamesAppBarModel.fromRound(Round round) {
    return GamesAppBarModel(
      id: round.id,
      name: round.name,
      startsAt: round.startsAt,
    );
  }

  RoundStatus get status {
    final now = DateTime.now();

    if (startsAt == null) return RoundStatus.upcoming;

    if (startsAt?.day == DateTime.now().day) {
      return RoundStatus.current;
    } else if (startsAt!.isBefore(now)) {
      return RoundStatus.completed;
    } else {
      return RoundStatus.upcoming;
    }
  }

  // Helper method to get formatted date string
  String get formattedStartDate {
    if (startsAt == null) return 'TBD';

    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${startsAt!.day} ${months[startsAt!.month - 1]} ${startsAt!.year}';
  }

  @override
  List<Object?> get props => [id, name, startsAt];
}
