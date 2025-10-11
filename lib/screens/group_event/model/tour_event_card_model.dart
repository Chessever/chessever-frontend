import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:equatable/equatable.dart';

enum TourEventCategory { live, ongoing, upcoming, completed }

class GroupEventCardModel extends Equatable {
  const GroupEventCardModel({
    required this.id,
    required this.title,
    required this.dates,
    required this.maxAvgElo,
    required this.timeUntilStart,
    required this.tourEventCategory,
    required this.timeControl,
    required this.endDate,
    required this.startDate,
  });

  final String id;
  final String title;
  final String dates;
  final int maxAvgElo;
  final String timeUntilStart;
  final TourEventCategory tourEventCategory;
  final String timeControl;
  final DateTime? endDate;
  final DateTime? startDate;

  factory GroupEventCardModel.fromGroupBroadcast(
    GroupBroadcast groupBroadcast,
    List<String> liveGroupIds,
  ) {
    final utcStart = groupBroadcast.dateStart;
    final utcEnd = groupBroadcast.dateEnd;

    return GroupEventCardModel(
      id: groupBroadcast.id,
      title: groupBroadcast.name,
      dates: TimeUtils.formatDateRange(utcStart, utcEnd),
      maxAvgElo: groupBroadcast.maxAvgElo ?? 0,
      timeUntilStart: TimeUtils.timeUntilStart(utcStart),
      tourEventCategory: getCategory(
        groupId: groupBroadcast.id,
        startDate: utcStart,
        endDate: utcEnd,
        liveGroupIds: liveGroupIds,
      ),
      timeControl: groupBroadcast.timeControl ?? '',
      endDate: utcEnd,
      startDate: utcStart,
    );
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
  List<Object?> get props => [
    id,
    title,
    dates,
    maxAvgElo,
    timeUntilStart,
    tourEventCategory,
    timeControl,
    endDate,
  ];
}
