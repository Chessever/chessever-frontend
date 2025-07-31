import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

enum TourEventCategory { live, upcoming, completed }

class TourEventCardModel extends Equatable {
  const TourEventCardModel({
    required this.id,
    required this.title,
    required this.dates,
    required this.maxAvgElo,
    required this.timeUntilStart,
    required this.tourEventCategory,
    required this.timeControl,
  });

  final String id;
  final String title;
  final String dates;
  final int maxAvgElo;
  final String timeUntilStart;
  final TourEventCategory tourEventCategory;
  final String timeControl;

  factory TourEventCardModel.fromGroupBroadcast(GroupBroadcast groupBroadcast) {
    return TourEventCardModel(
      id: groupBroadcast.id,
      title: groupBroadcast.name,
      dates: convertDates(groupBroadcast.dateStart, groupBroadcast.dateEnd),
      maxAvgElo: groupBroadcast.maxAvgElo ?? 0,
      timeUntilStart: getTimeUntilStart(groupBroadcast.dateStart),
      tourEventCategory: getCategory(groupBroadcast.dateStart),
      timeControl: groupBroadcast.timeControl ?? '',
    );
  }

  static String convertDates(DateTime? startDateTime, DateTime? endDateTime) {
    if (startDateTime != null && endDateTime != null) {
      return "${DateFormat('MMM d').format(startDateTime)} - ${DateFormat('d,yyyy').format(endDateTime)}";
    } else {
      //todo: Fix this
      return "10 Jan 2024";
    }
  }

  static String getTimeUntilStart(DateTime? startDateTime) {
    if (startDateTime == null) {
      return "";
    }

    final now = DateTime.now();

    // If the start time has already passed
    if (startDateTime!.isBefore(now)) {
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
          return "In $minutes minute${minutes == 1 ? '' : 's'}";
        }
        return "In $hours hour${hours == 1 ? '' : 's'}";
      } else if (days == 1) {
        return "In 1 day";
      } else {
        return "In $days days";
      }
    } else if (days < 365) {
      // Between 30 days and 365 days - show in months
      final months = (days / 30).round();
      return "In $months month${months == 1 ? '' : 's'}";
    } else {
      // More than 365 days - show in years
      final years = (days / 365).round();
      return "In $years year${years == 1 ? '' : 's'}";
    }
  }

  static TourEventCategory getCategory(DateTime? startDate) {
    if (startDate != null) {
      final now = DateTime.now();

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
