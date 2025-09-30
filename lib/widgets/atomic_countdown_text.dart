import 'package:chessever2/utils/date_time_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Atomic countdown text widget that only rebuilds the text itself every second
/// This prevents parent widgets from rebuilding unnecessarily
/// Uses clock seconds as primary source, moveTime/centiseconds as fallback
class AtomicCountdownText extends ConsumerWidget {
  const AtomicCountdownText({
    super.key,
    this.moveTime,
    this.clockSeconds,
    required this.clockCentiseconds,
    required this.lastMoveTime,
    required this.isActive,
    required this.style,
  });

  final String? moveTime; // Legacy: for chessboard screen with PGN parsing
  final int? clockSeconds; // Primary source: time in seconds from last_clock fields
  final int clockCentiseconds; // Fallback source: raw database clock in centiseconds
  final DateTime? lastMoveTime;
  final bool isActive;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine which time source to use: clockSeconds (primary), moveTime (secondary), clockCentiseconds (fallback)
    final useClockSeconds = clockSeconds != null;
    final useCalculatedTime = !useClockSeconds && moveTime != null && moveTime!.isNotEmpty;

    // Only watch dateTimeProvider if clock is actively counting down
    if (!isActive || lastMoveTime == null) {
      if (useClockSeconds) {
        final staticTime = _formatTimeFromSeconds(clockSeconds!);
        return Text(_formatTimeWithHours(staticTime), style: style);
      } else if (useCalculatedTime) {
        return Text(_formatTimeWithHours(moveTime!), style: style);
      } else {
        final staticTime = _formatTimeFromMs(clockCentiseconds * 10);
        return Text(_formatTimeWithHours(staticTime), style: style);
      }
    }

    // Atomic rebuild - only this Text widget rebuilds every second
    final displayTime = ref.watch(dateTimeProvider.select((timeAsync) {
      final currentTime = timeAsync.valueOrNull;
      if (currentTime == null) {
        if (useClockSeconds) {
          final staticTime = _formatTimeFromSeconds(clockSeconds!);
          return _formatTimeWithHours(staticTime);
        } else if (useCalculatedTime) {
          return _formatTimeWithHours(moveTime!);
        } else {
          final staticTime = _formatTimeFromMs(clockCentiseconds * 10);
          return _formatTimeWithHours(staticTime);
        }
      }

      // Calculate elapsed time since lastMoveTime (when the previous player finished their move)
      // This is how long the current player has been thinking on their turn
      final elapsedSeconds = currentTime.difference(lastMoveTime!).inSeconds.abs();

      int totalSeconds;
      if (useClockSeconds) {
        // Primary source: Use clock seconds directly
        totalSeconds = clockSeconds!;
      } else if (useCalculatedTime) {
        // Secondary source: Parse calculated moveTime
        totalSeconds = _parseTimeToSeconds(moveTime!);
        if (totalSeconds == 0) {
          // If parsing fails, fallback to clock centiseconds
          totalSeconds = (clockCentiseconds / 100).floor();
        }
      } else {
        // Fallback source: Use raw clock centiseconds (convert to seconds)
        totalSeconds = (clockCentiseconds / 100).floor();
      }

      // Calculate remaining time: total time minus elapsed time since last move
      final remainingSeconds = totalSeconds - elapsedSeconds;

      // Ensure time doesn't go below 0
      final clampedSeconds = remainingSeconds < 0 ? 0 : remainingSeconds;

      // Format the remaining time
      final remainingTime = _formatTimeFromSeconds(clampedSeconds);

      // Convert to hh:mm:ss format if over 1 hour
      return _formatTimeWithHours(remainingTime);
    }));

    return Text(displayTime, style: style);
  }

  /// Formats milliseconds to MM:SS format
  static String _formatTimeFromMs(int milliseconds) {
    if (milliseconds <= 0) {
      return '00:00';
    }

    final totalSeconds = (milliseconds / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Formats seconds to MM:SS format
  static String _formatTimeFromSeconds(int totalSeconds) {
    if (totalSeconds <= 0) {
      return '00:00';
    }

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Parses various time formats to seconds
  /// Supports: MM:SS, HH:MM:SS, H:MM:SS, 1h23m formats
  static int _parseTimeToSeconds(String timeString) {
    try {
      // Handle 1h23m format
      if (timeString.contains('h') && timeString.contains('m')) {
        final hourMatch = RegExp(r'(\d+)h').firstMatch(timeString);
        final minuteMatch = RegExp(r'(\d+)m').firstMatch(timeString);

        final hours = hourMatch != null ? int.parse(hourMatch.group(1)!) : 0;
        final minutes = minuteMatch != null ? int.parse(minuteMatch.group(1)!) : 0;

        return hours * 3600 + minutes * 60;
      }

      // Handle HH:MM:SS or MM:SS format
      final timeParts = timeString.split(':');
      if (timeParts.length == 2) {
        // MM:SS format
        final minutes = int.parse(timeParts[0]);
        final seconds = int.parse(timeParts[1]);
        return minutes * 60 + seconds;
      } else if (timeParts.length == 3) {
        // HH:MM:SS format
        final hours = int.parse(timeParts[0]);
        final minutes = int.parse(timeParts[1]);
        final seconds = int.parse(timeParts[2]);
        return hours * 3600 + minutes * 60 + seconds;
      }
    } catch (e) {
      // Return 0 if parsing fails
    }
    return 0;
  }

  /// Formats time string to include hours if over 60 minutes
  /// Input can be either MM:SS or HH:MM:SS format, or already formatted time from ChessClockExtension
  static String _formatTimeWithHours(String timeString) {
    // If it's already in the correct format or contains 'h' (like "1h23m"), return as is
    if (timeString.contains('h') || timeString.contains(':') && timeString.split(':').length == 3) {
      return timeString;
    }

    // Parse MM:SS format
    final timeParts = timeString.split(':');
    if (timeParts.length != 2) {
      return timeString; // Return original if not in expected format
    }

    try {
      final minutes = int.parse(timeParts[0]);
      final seconds = int.parse(timeParts[1]);

      // If less than 60 minutes, return as MM:SS
      if (minutes < 60) {
        return timeString;
      }

      // Convert to HH:MM:SS format
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;

      return '${hours.toString().padLeft(2, '0')}:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } catch (e) {
      return timeString; // Return original if parsing fails
    }
  }
}