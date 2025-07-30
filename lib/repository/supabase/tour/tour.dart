// models/tour.dart
import 'package:intl/intl.dart';

class _TourInfo {
  final String? tc; // Time control (e.g., "90 min + 30 sec / move")
  final String? fideTc; // FIDE time control category (standard, rapid, blitz)
  final String? format; // Tournament format (e.g., "9-round Swiss")
  final String? players; // Notable players (comma-separated string)
  final String? website; // Tournament website
  final String? location; // Tournament location
  final String? timeZone; // Time zone
  final String? standings; // Standings URL

  const _TourInfo({
    this.tc,
    this.fideTc,
    this.format,
    this.players,
    this.website,
    this.location,
    this.timeZone,
    this.standings,
  });

  factory _TourInfo.fromJson(Map<String, dynamic> json) {
    return _TourInfo(
      tc: json['tc'] as String?,
      fideTc: json['fideTc'] as String?,
      format: json['format'] as String?,
      players: json['players'] as String?,
      website: json['website'] as String?,
      location: json['location'] as String?,
      timeZone: json['timeZone'] as String?,
      standings: json['standings'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (tc != null) 'tc': tc,
      if (fideTc != null) 'fideTc': fideTc,
      if (format != null) 'format': format,
      if (players != null) 'players': players,
      if (website != null) 'website': website,
      if (location != null) 'location': location,
      if (timeZone != null) 'timeZone': timeZone,
      if (standings != null) 'standings': standings,
    };
  }

  // Helper method to get players as a list
  List<String> get playersList {
    if (players == null || players!.isEmpty) return [];
    return players!.split(', ').map((p) => p.trim()).toList();
  }

  @override
  String toString() {
    return 'TourInfo(format: $format, tc: $tc, location: $location)';
  }
}

class Tour {
  final String id;
  final String name;
  final String slug;
  final _TourInfo info;
  final DateTime createdAt;
  final String url;
  final int tier;
  final List<DateTime> dates;
  final String? image;
  final List<Map<String, dynamic>>
  players; // This appears to be empty in your data
  final List<String>? search;

  Tour({
    required this.id,
    required this.name,
    required this.slug,
    required this.info,
    required this.createdAt,
    required this.url,
    required this.tier,
    required this.dates,
    this.image,
    required this.players,
    this.search,
  });

  factory Tour.fromJson(Map<String, dynamic> json) {
    return Tour(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      info: _TourInfo.fromJson(json['info'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
      url: json['url'] as String,
      tier: json['tier'] as int,
      dates:
          (json['dates'] as List)
              .map((date) => DateTime.parse(date as String))
              .toList(),
      image: json['image'] as String?,
      players:
          (json['players'] as List)
              .map((player) => player as Map<String, dynamic>)
              .toList(),
      search: (json['search'] as List?)?.map((e) => e as String).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'info': info.toJson(),
      'created_at': createdAt.toIso8601String(),
      'url': url,
      'tier': tier,
      'dates': dates.map((date) => date.toIso8601String()).toList(),
      'image': image,
      'players': players,
      'search': search,
    };
  }

  // Format time until start
  static String timeUntilStart(List<DateTime> dates) {
    if (dates.isEmpty) {
      return "Starts in 3 days"; // Fallback
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

  // Get time until start for this tournament
  String get timeUntilStartString => timeUntilStart(dates);

  // Format start date as "Jun 21"
  String get startDateFormatted {
    if (dates.isEmpty) return '';
    return DateFormat('MMM d').format(dates.first);
  }

  String get dateRangeFormatted {
    if (dates.isEmpty) return '';
    if (dates.length == 1) {
      return DateFormat('MMM d, yyyy').format(dates.first);
    }

    final startDate = dates.first;
    final endDate = dates.last;

    // Same year
    if (startDate.year == endDate.year) {
      // Same month
      if (startDate.month == endDate.month) {
        final startDay = DateFormat('MMM d').format(startDate);
        final endDay = DateFormat('d').format(endDate);
        final year = DateFormat('yyyy').format(startDate);
        return '$startDay - $endDay, $year';
      }
      // Different month, same year
      else {
        final start = DateFormat('MMM d').format(startDate);
        final end = DateFormat('MMM d').format(endDate);
        final year = DateFormat('yyyy').format(startDate);
        return '$start - $end, $year';
      }
    }
    // Different year
    else {
      final start = DateFormat('MMM d, yyyy').format(startDate);
      final end = DateFormat('MMM d, yyyy').format(endDate);
      return '$start - $end';
    }
  }

  // Get tournament duration in days
  int get durationInDays {
    if (dates.length < 2) return 1;
    return dates.last.difference(dates.first).inDays + 1;
  }

  // Check if tournament is single day
  bool get isSingleDay => dates.length == 1 || durationInDays == 1;

  // Get notable players list
  List<String> get notablePlayers => info.playersList;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Tour && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

// Extension for better date comparison
extension DateTimeExtension on DateTime {
  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }
}
