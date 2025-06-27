import 'package:equatable/equatable.dart';

import '../../../repository/supabase/round/round.dart';

enum RoundStatus { completed, current, upcoming }

class GamesAppBarViewModel extends Equatable {
  GamesAppBarViewModel({
    required this.id,
    required this.name,
    required this.startsAt,
    required this.ongoing,
  });

  final String id;
  final String name;
  final DateTime? startsAt;
  final bool ongoing;

  factory GamesAppBarViewModel.fromTour(Round tour) {
    return GamesAppBarViewModel(
      id: tour.id,
      name: tour.name,
      startsAt: tour.startsAt,
      ongoing: tour.ongoing,
    );
  }

  RoundStatus get status {
    final now = DateTime.now();

    if (startsAt == null) return RoundStatus.upcoming;

    if (ongoing) {
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
  List<Object?> get props => [id, name, startsAt, ongoing];
}
