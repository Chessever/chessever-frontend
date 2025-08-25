import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

enum TourEventCategory {
  live,
  ongoing,
  upcoming,
  completed,
}

class GroupEventCardModel extends Equatable {
  const GroupEventCardModel({
    required this.id,
    required this.title,
    required this.dates,
    required this.maxAvgElo,
    required this.timeUntilStart,
    required this.tourEventCategory,
    required this.timeControl,
    required this.startDate,
    required this.endDate,

  });

  final String id;
  final String title;
  final String dates;
  final DateTime? startDate;
  final DateTime? endDate;
  final int maxAvgElo;
  final String timeUntilStart;
  final TourEventCategory tourEventCategory;
  final String timeControl;

  factory GroupEventCardModel.fromGroupBroadcast(
    GroupBroadcast groupBroadcast,
    List<String> liveGroupIds,
  ) {
    return GroupEventCardModel(
      id: groupBroadcast.id,
      title: groupBroadcast.name,
      dates: convertDates(groupBroadcast.dateStart, groupBroadcast.dateEnd),
      startDate: groupBroadcast.dateStart,
      endDate: groupBroadcast.dateEnd,
      maxAvgElo: groupBroadcast.maxAvgElo ?? 0,
      timeUntilStart: getTimeUntilStart(groupBroadcast.dateStart),
      tourEventCategory: getCategory(
        groupId: groupBroadcast.id,
        startDate: groupBroadcast.dateStart,
        endDate: groupBroadcast.dateEnd,
        liveGroupIds: liveGroupIds,
      ),
      timeControl: groupBroadcast.timeControl ?? '',
    );
  }

  static String convertDates(DateTime? startDateTime, DateTime? endDateTime) {
    if (startDateTime != null && endDateTime != null) {
      if (startDateTime.month == endDateTime.month) {
        return "${DateFormat('MMM d').format(startDateTime)} - ${DateFormat('d, yyyy').format(endDateTime)}";
      } else if (startDateTime.year == endDateTime.year) {
        return "${DateFormat('MMM d').format(startDateTime)} - ${DateFormat('d MMM, yyyy').format(endDateTime)}";
      } else {
        return "${DateFormat('MMM d, yyyy').format(startDateTime)} - ${DateFormat('MMM d, yyyy').format(endDateTime)}";
      }
    } else if (startDateTime != null) {
      return DateFormat('MMM d, yyyy').format(startDateTime);
    } else if (endDateTime != null) {
      return DateFormat('MMM d, yyyy').format(endDateTime);
    } else {
      return "";
    }
  }

  static String getTimeUntilStart(DateTime? startDateTime) {
    if (startDateTime == null) {
      return "";
    }

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

  static TourEventCategory getCategory({
    required String groupId,
    required DateTime? startDate,
    required DateTime? endDate,
    required List<String> liveGroupIds,
  }) {
    // Check if it's a live event first (highest priority)
    if (liveGroupIds.contains(groupId)) {
      return TourEventCategory.live;
    }

    final now = DateTime.now();

    // If we have both start and end dates
    if (startDate != null && endDate != null) {
      // Handle invalid date range (end before start)
      if (endDate.isBefore(startDate)) {
        // Treat as completed if end date is in the past
        return endDate.isBefore(now)
            ? TourEventCategory.completed
            : TourEventCategory.upcoming;
      }

      // Normal case: valid date range
      if (now.isBefore(startDate)) {
        return TourEventCategory.upcoming;
      } else if (now.isAfter(endDate)) {
        return TourEventCategory.completed;
      } else {
        return TourEventCategory.ongoing;
      }
    }

    // If we only have start date
    if (startDate != null) {
      return now.isBefore(startDate)
          ? TourEventCategory.upcoming
          : TourEventCategory.completed; // Changed from ongoing to completed
    }

    // If we only have end date
    if (endDate != null) {
      return now.isAfter(endDate)
          ? TourEventCategory.completed
          : TourEventCategory.ongoing;
    }

    // No date information available - default to completed
    return TourEventCategory.completed;
  }

  @override
  // TODO: implement props
  List<Object?> get props => throw UnimplementedError();
}
