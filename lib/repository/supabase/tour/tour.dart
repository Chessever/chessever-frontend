import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/widgets/round_selector.dart';
import 'package:intl/intl.dart';

class TournamentPlayer {
  final String? federation;
  final String name;
  final String? title;
  final int? fideId;
  final int played;
  final int? rating;
  final int? ratingDiff;
  final double? score; // Added: Tournament score (e.g., 2.0, 1.5)
  final int? performance; // Added: Performance rating

  TournamentPlayer({
    this.federation,
    required this.name,
    this.title,
    this.fideId,
    required this.played,
    this.rating,
    this.ratingDiff,
    this.score,
    this.performance,
  });

  /// Creates a TournamentPlayer from JSON map
  factory TournamentPlayer.fromJson(Map<String, dynamic> json) {
    return TournamentPlayer(
      federation: json['fed'] as String?,
      name: json['name'] as String? ?? '',
      title: json['title'] as String?,
      fideId: json['fideId'] as int?,
      played: json['played'] as int? ?? 0,
      rating: json['rating'] as int?,
      ratingDiff: json['ratingDiff'] as int?,
      score: _parseScore(json['score']), // Handle both int and double
      performance: json['performance'] as int?,
    );
  }

  /// Helper method to parse score as double from various number types
  static double? _parseScore(dynamic score) {
    if (score == null) return null;
    if (score is double) return score;
    if (score is int) return score.toDouble();
    if (score is String) return double.tryParse(score);
    return null;
  }

  /// Converts TournamentPlayer to JSON map
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'name': name,
      'played': played,
    };

    if (federation != null) data['fed'] = federation;
    if (title != null) data['title'] = title;
    if (fideId != null) data['fideId'] = fideId;
    if (rating != null) data['rating'] = rating;
    if (ratingDiff != null) data['ratingDiff'] = ratingDiff;
    if (score != null) data['score'] = score;
    if (performance != null) data['performance'] = performance;

    return data;
  }

  /// Creates an empty TournamentPlayer with default values
  factory TournamentPlayer.empty() {
    return TournamentPlayer(
      name: '',
      played: 0,
    );
  }

  /// Checks if this is an empty/default player
  bool get isEmpty => name.isEmpty && played == 0;

  /// Gets display name with title if available
  String get displayName {
    if (title != null && title!.isNotEmpty) {
      return '$title $name';
    }
    return name;
  }

  /// Gets rating change as a formatted string with + or - sign
  String get ratingChangeString {
    if (ratingDiff == null) return '';
    if (ratingDiff! > 0) return '+$ratingDiff';
    return ratingDiff.toString();
  }

  /// Gets score as a formatted string (e.g., "2.0", "1.5")
  String get scoreString {
    if (score == null) return '';
    // Show one decimal place if not a whole number, otherwise show as integer
    return score! % 1 == 0
        ? score!.toInt().toString()
        : score!.toStringAsFixed(1);
  }

  /// Gets score percentage (score/played * 100)
  double? get scorePercentage {
    if (score == null || played == 0) return null;
    return (score! / played) * 100;
  }

  /// Gets score percentage as formatted string
  String get scorePercentageString {
    final percentage = scorePercentage;
    if (percentage == null) return '';
    return '${percentage.toStringAsFixed(1)}%';
  }

  /// Checks if player has a FIDE rating
  bool get hasRating => rating != null && rating! > 0;

  /// Checks if player has a title
  bool get hasTitle => title != null && title!.isNotEmpty;

  /// Checks if player has a score
  bool get hasScore => score != null;

  /// Checks if player has a performance rating
  bool get hasPerformance => performance != null && performance! > 0;

  /// Gets performance rating difference from current rating
  int? get performanceRatingDiff {
    if (performance == null || rating == null) return null;
    return performance! - rating!;
  }

  /// Gets performance rating difference as formatted string
  String get performanceRatingDiffString {
    final diff = performanceRatingDiff;
    if (diff == null) return '';
    if (diff > 0) return '+$diff';
    return diff.toString();
  }

  @override
  String toString() {
    return 'TournamentPlayer(name: $name, federation: $federation, title: $title, '
        'fideId: $fideId, played: $played, rating: $rating, ratingDiff: $ratingDiff, '
        'score: $score, performance: $performance)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TournamentPlayer &&
        other.federation == federation &&
        other.name == name &&
        other.title == title &&
        other.fideId == fideId &&
        other.played == played &&
        other.rating == rating &&
        other.ratingDiff == ratingDiff &&
        other.score == score &&
        other.performance == performance;
  }

  @override
  int get hashCode {
    return federation.hashCode ^
        name.hashCode ^
        title.hashCode ^
        fideId.hashCode ^
        played.hashCode ^
        rating.hashCode ^
        ratingDiff.hashCode ^
        score.hashCode ^
        performance.hashCode;
  }

  /// Creates a copy of this player with updated fields
  TournamentPlayer copyWith({
    String? federation,
    String? name,
    String? title,
    int? fideId,
    int? played,
    int? rating,
    int? ratingDiff,
    double? score,
    int? performance,
  }) {
    return TournamentPlayer(
      federation: federation ?? this.federation,
      name: name ?? this.name,
      title: title ?? this.title,
      fideId: fideId ?? this.fideId,
      played: played ?? this.played,
      rating: rating ?? this.rating,
      ratingDiff: ratingDiff ?? this.ratingDiff,
      score: score ?? this.score,
      performance: performance ?? this.performance,
    );
  }
}

// Example usage and helper functions:

/// Parses a list of tournament players from JSON
List<TournamentPlayer> parsePlayersFromJson(List<dynamic> jsonList) {
  return jsonList
      .map((json) => TournamentPlayer.fromJson(json as Map<String, dynamic>))
      .toList();
}

/// Filters players by minimum rating
List<TournamentPlayer> filterByMinRating(
  List<TournamentPlayer> players,
  int minRating,
) {
  return players
      .where((player) => player.hasRating && player.rating! >= minRating)
      .toList();
}

/// Filters players by minimum score
List<TournamentPlayer> filterByMinScore(
  List<TournamentPlayer> players,
  double minScore,
) {
  return players
      .where((player) => player.hasScore && player.score! >= minScore)
      .toList();
}

/// Groups players by federation
Map<String, List<TournamentPlayer>> groupByFederation(
  List<TournamentPlayer> players,
) {
  final Map<String, List<TournamentPlayer>> grouped = {};

  for (final player in players) {
    final fed = player.federation ?? 'Unknown';
    grouped.putIfAbsent(fed, () => []).add(player);
  }

  return grouped;
}

/// Sorts players by rating (highest first)
List<TournamentPlayer> sortByRating(List<TournamentPlayer> players) {
  final List<TournamentPlayer> sorted = List.from(players);
  sorted.sort((a, b) {
    // Players without ratings go to the end
    if (a.rating == null && b.rating == null) return 0;
    if (a.rating == null) return 1;
    if (b.rating == null) return -1;
    return b.rating!.compareTo(a.rating!);
  });
  return sorted;
}

/// Sorts players by score (highest first)
List<TournamentPlayer> sortByScore(List<TournamentPlayer> players) {
  final List<TournamentPlayer> sorted = List.from(players);
  sorted.sort((a, b) {
    // Players without scores go to the end
    if (a.score == null && b.score == null) return 0;
    if (a.score == null) return 1;
    if (b.score == null) return -1;
    return b.score!.compareTo(a.score!);
  });
  return sorted;
}

/// Sorts players by performance rating (highest first)
List<TournamentPlayer> sortByPerformance(List<TournamentPlayer> players) {
  final List<TournamentPlayer> sorted = List.from(players);
  sorted.sort((a, b) {
    // Players without performance ratings go to the end
    if (a.performance == null && b.performance == null) return 0;
    if (a.performance == null) return 1;
    if (b.performance == null) return -1;
    return b.performance!.compareTo(a.performance!);
  });
  return sorted;
}

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

class TourModel {
  final Tour tour;
  final RoundStatus roundStatus;

  TourModel({
    required this.tour,
    required this.roundStatus,
  });
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
  final List<TournamentPlayer> players; // Updated to use TournamentPlayer
  final List<String>? search;
  final String? groupBroadcastId;
  final int? avgElo;

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
    this.groupBroadcastId,
    this.avgElo,
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
      players: parsePlayersFromJson(json['players'] as List? ?? []),
      search: (json['search'] as List?)?.map((e) => e as String).toList(),
      groupBroadcastId: json['group_broadcast_id'] as String?,
      avgElo: json['avg_elo'] as int?,
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
      'players': players.map((player) => player.toJson()).toList(),
      'search': search,
      'group_broadcast_id': groupBroadcastId,
      'avg_elo': avgElo,
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

  // Get notable players list from info
  List<String> get notablePlayers => info.playersList;

  // PLAYER-RELATED METHODS

  /// Get players sorted by rating (highest first)
  List<TournamentPlayer> get playersByRating => sortByRating(players);

  /// Get players sorted by score (highest first)
  List<TournamentPlayer> get playersByScore => sortByScore(players);

  /// Get players sorted by performance (highest first)
  List<TournamentPlayer> get playersByPerformance => sortByPerformance(players);

  /// Get players grouped by federation
  Map<String, List<TournamentPlayer>> get playersByFederation =>
      groupByFederation(players);

  /// Get total number of players
  int get totalPlayers => players.length;

  /// Get number of rated players
  int get ratedPlayersCount => players.where((p) => p.hasRating).length;

  /// Get number of titled players
  int get titledPlayersCount => players.where((p) => p.hasTitle).length;

  /// Get number of players with scores
  int get playersWithScoreCount => players.where((p) => p.hasScore).length;

  /// Get number of players with performance ratings
  int get playersWithPerformanceCount =>
      players.where((p) => p.hasPerformance).length;

  /// Calculate average rating of all rated players
  double? get averageRating {
    final ratedPlayers = players.where((p) => p.hasRating).toList();
    if (ratedPlayers.isEmpty) return null;

    final sum = ratedPlayers.fold<int>(0, (sum, p) => sum + p.rating!);
    return sum / ratedPlayers.length;
  }

  /// Calculate average score of all players with scores
  double? get averageScore {
    final scoredPlayers = players.where((p) => p.hasScore).toList();
    if (scoredPlayers.isEmpty) return null;

    final sum = scoredPlayers.fold<double>(0, (sum, p) => sum + p.score!);
    return sum / scoredPlayers.length;
  }

  /// Calculate average performance rating of all players with performance
  double? get averagePerformance {
    final performancePlayers = players.where((p) => p.hasPerformance).toList();
    if (performancePlayers.isEmpty) return null;

    final sum = performancePlayers.fold<int>(
      0,
      (sum, p) => sum + p.performance!,
    );
    return sum / performancePlayers.length;
  }

  /// Get highest rated player
  TournamentPlayer? get highestRatedPlayer {
    final ratedPlayers = players.where((p) => p.hasRating).toList();
    if (ratedPlayers.isEmpty) return null;

    return ratedPlayers.reduce((a, b) => a.rating! > b.rating! ? a : b);
  }

  /// Get highest scoring player
  TournamentPlayer? get highestScoringPlayer {
    final scoredPlayers = players.where((p) => p.hasScore).toList();
    if (scoredPlayers.isEmpty) return null;

    return scoredPlayers.reduce((a, b) => a.score! > b.score! ? a : b);
  }

  /// Get player with highest performance
  TournamentPlayer? get bestPerformancePlayer {
    final performancePlayers = players.where((p) => p.hasPerformance).toList();
    if (performancePlayers.isEmpty) return null;

    return performancePlayers.reduce(
      (a, b) => a.performance! > b.performance! ? a : b,
    );
  }

  /// Get players from a specific federation
  List<TournamentPlayer> playersFromFederation(String federation) {
    return players.where((p) => p.federation == federation).toList();
  }

  /// Get players with specific title
  List<TournamentPlayer> playersWithTitle(String title) {
    return players.where((p) => p.title == title).toList();
  }

  /// Get players with rating in range
  List<TournamentPlayer> playersInRatingRange(int minRating, int maxRating) {
    return players
        .where(
          (p) =>
              p.hasRating && p.rating! >= minRating && p.rating! <= maxRating,
        )
        .toList();
  }

  /// Get players with score in range
  List<TournamentPlayer> playersInScoreRange(double minScore, double maxScore) {
    return players
        .where(
          (p) => p.hasScore && p.score! >= minScore && p.score! <= maxScore,
        )
        .toList();
  }

  /// Get federation statistics
  Map<String, int> get federationStats {
    final Map<String, int> stats = {};
    for (final player in players) {
      final fed = player.federation ?? 'Unknown';
      stats[fed] = (stats[fed] ?? 0) + 1;
    }
    return stats;
  }

  /// Get title statistics
  Map<String, int> get titleStats {
    final Map<String, int> stats = {};
    for (final player in players) {
      if (player.hasTitle) {
        final title = player.title!;
        stats[title] = (stats[title] ?? 0) + 1;
      }
    }
    return stats;
  }

  /// Search players by name (case insensitive)
  List<TournamentPlayer> searchPlayers(String query) {
    if (query.isEmpty) return players;

    final lowerQuery = query.toLowerCase();
    return players
        .where((p) => p.name.toLowerCase().contains(lowerQuery))
        .toList();
  }

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
