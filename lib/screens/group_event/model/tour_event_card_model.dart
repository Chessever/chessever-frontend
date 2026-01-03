import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:equatable/equatable.dart';

enum TourEventCategory { live, ongoing, upcoming, completed }

enum EventSource {
  lichessBroadcast,  // From group_broadcasts (Lichess events)
  communityEvent,    // From calendar_events (external sources)
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
    required this.endDate,
    required this.startDate,
    this.location,
    this.searchTerms = const [],
    this.eventSource = EventSource.lichessBroadcast,
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
  final String? location;
  final List<String> searchTerms;
  final EventSource eventSource;

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
        groupName: groupBroadcast.name,
        startDate: utcStart,
        endDate: utcEnd,
        liveGroupIds: liveGroupIds,
      ),
      timeControl: _formatTimeControl(groupBroadcast.timeControl),
      endDate: utcEnd,
      startDate: utcStart,
      searchTerms: groupBroadcast.search,
      eventSource: EventSource.lichessBroadcast,
    );
  }

  factory GroupEventCardModel.fromCalendarEvent(
    CalendarEvent calendarEvent,
  ) {
    final utcStart = calendarEvent.startDate;
    final utcEnd = calendarEvent.endDate;

    // Use event name as ID for calendar events (name is primary key in DB)
    // Replace special characters to ensure valid ID format
    final sanitizedName = calendarEvent.name
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w\-]'), '')
        .toLowerCase();
    final eventId = 'cal_event_$sanitizedName';

    return GroupEventCardModel(
      id: eventId,
      title: calendarEvent.name,
      dates: TimeUtils.formatDateRange(utcStart, utcEnd),
      maxAvgElo: 0, // Calendar events don't have ELO ratings
      timeUntilStart: TimeUtils.timeUntilStart(utcStart),
      tourEventCategory: getCategory(
        groupId: eventId,
        startDate: utcStart,
        endDate: utcEnd,
        liveGroupIds: [], // Calendar events are never "live"
      ),
      timeControl: _formatTimeControl(calendarEvent.timeControl),
      endDate: utcEnd,
      startDate: utcStart,
      location: calendarEvent.location,
      searchTerms: const [],
      eventSource: EventSource.communityEvent,
    );
  }

  static TourEventCategory getCategory({
    required String groupId,
    String? groupName,
    required DateTime? startDate,
    required DateTime? endDate,
    required List<String> liveGroupIds,
  }) {
    // Check if it's a live event first (highest priority)
    // Settings may store either IDs or names, so check both
    if (liveGroupIds.contains(groupId) ||
        (groupName != null && liveGroupIds.contains(groupName))) {
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
    location,
    searchTerms,
    eventSource,
  ];

  static String _formatTimeControl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Standard';

    final lower = raw.toLowerCase();
    if (lower.contains('bullet')) return 'Bullet';
    if (lower.contains('blitz')) return 'Blitz';
    if (lower.contains('rapid')) return 'Rapid';
    if (lower.contains('classic') || lower.contains('standard')) {
      return 'Standard';
    }

    final trimmed = raw.trim();
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }
}
