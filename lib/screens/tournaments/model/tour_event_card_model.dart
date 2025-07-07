import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

enum TourEventCategory { live, upcoming, completed }

class TourEventCardModel extends Equatable {
  const TourEventCardModel({
    required this.id,
    required this.title,
    required this.dates,
    required this.location,
    required this.playerCount,
    required this.elo,
    required this.timeUntilStart,
    required this.tourEventCategory,
  });

  final String id;
  final String title;
  final String dates;
  final String location;
  final int playerCount;
  final int elo;
  final String timeUntilStart;
  final TourEventCategory tourEventCategory;

  factory TourEventCardModel.fromTour(Tour tour) {
    return TourEventCardModel(
      id: tour.id,
      title: tour.name,
      dates: convertDates(tour.dates),
      location: tour.info.location ?? tour.name.split(' ').first,
      playerCount: tour.players.length,
      elo: tour.tier,
      timeUntilStart: getTimeUntilStart(tour.dates),
      tourEventCategory: getCategory(tour.dates, tour.info.location ?? ""),
    );
  }

  static String convertDates(List<DateTime> dates) {
    if (dates.isNotEmpty) {
      final startDateTime = dates.first;
      final endDateTime = dates.last;
      return "${DateFormat('MMM d').format(startDateTime)} - ${DateFormat('d,yyyy').format(endDateTime)}";
    } else {
      //todo: Fix this
      return "10 Jan 2024";
    }
  }

  static String getTimeUntilStart(List<DateTime> dates) {
    if (dates.isEmpty) {
      return "Starts in 3 days";
    }

    final startDateTime = dates.first;
    final now = DateTime.now();

    // If the start time has already passed
    if (startDateTime.isBefore(now)) {
      return "Started";
    }

    final difference = startDateTime.difference(now);
    final days = difference.inDays;

    if (days < 30) {
      // Less than 30 days - show in days
      if (days == 0) {
        final hours = difference.inHours;
        if (hours == 0) {
          final minutes = difference.inMinutes;
          return "Starts in $minutes minute${minutes == 1 ? '' : 's'}";
        }
        return "Starts in $hours hour${hours == 1 ? '' : 's'}";
      } else if (days == 1) {
        return "Starts in 1 day";
      } else {
        return "Starts in $days days";
      }
    } else if (days < 365) {
      // Between 30 days and 365 days - show in months
      final months = (days / 30).round();
      return "Starts in $months month${months == 1 ? '' : 's'}";
    } else {
      // More than 365 days - show in years
      final years = (days / 365).round();
      return "Starts in $years year${years == 1 ? '' : 's'}";
    }
  }

  static TourEventCategory getCategory(List<DateTime> dates, String location) {
    if (dates.isNotEmpty) {
      final now = DateTime.now();
      final startDate = dates.first;

      if (startDate.isAfter(now)) {
        return TourEventCategory.upcoming;
      } else if (startDate.year == DateTime.now().year &&
          startDate.month == DateTime.now().month &&
          startDate.day == DateTime.now().day) {
        return TourEventCategory.live;
      } else {
        return TourEventCategory.completed;
      }
    }

    return TourEventCategory.completed;
  }

  @override
  // TODO: implement props
  List<Object?> get props => throw UnimplementedError();
}
