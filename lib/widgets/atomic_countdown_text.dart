import 'package:chessever2/utils/date_time_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Atomic countdown text widget that only rebuilds the text itself every second
/// This prevents parent widgets from rebuilding unnecessarily
/// Uses calculated moveTime as primary source, clock centiseconds as fallback
class AtomicCountdownText extends ConsumerWidget {
  const AtomicCountdownText({
    super.key,
    required this.moveTime,
    required this.clockCentiseconds,
    required this.lastMoveTime,
    required this.isActive,
    required this.style,
  });

  final String? moveTime; // Primary source: calculated from chessBoardState.moveTimes
  final int clockCentiseconds; // Fallback source: raw database clock
  final DateTime? lastMoveTime;
  final bool isActive;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine which time source to use: moveTime (primary) or clockCentiseconds (fallback)
    final useCalculatedTime = moveTime != null && moveTime!.isNotEmpty;

    // Debug logging for time source selection
    // print('⏰ AtomicCountdownText DEBUG: useCalculatedTime=$useCalculatedTime, moveTime=$moveTime, clockCentiseconds=$clockCentiseconds, isActive=$isActive, lastMoveTime=$lastMoveTime');

    // Only watch dateTimeProvider if clock is actively counting down
    if (!isActive || lastMoveTime == null) {
      if (useCalculatedTime) {
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
        if (useCalculatedTime) {
          return _formatTimeWithHours(moveTime!);
        } else {
          final staticTime = _formatTimeFromMs(clockCentiseconds * 10);
          return _formatTimeWithHours(staticTime);
        }
      }

      // Calculate elapsed time since lastMoveTime (when current player's turn started)
      final elapsedMs = currentTime.difference(lastMoveTime!).inMilliseconds.abs();

      int totalMs;
      if (useCalculatedTime) {
        // Primary source: Parse calculated moveTime and apply real-time deduction
        totalMs = _parseTimeToMs(moveTime!);
        if (totalMs == 0) {
          // If parsing fails, fallback to clock centiseconds
          totalMs = clockCentiseconds * 10;
        }
      } else {
        // Fallback source: Use raw clock centiseconds (convert to milliseconds)
        totalMs = clockCentiseconds * 10;
      }

      // print('⏰ REAL-TIME CALC: elapsedMs=${elapsedMs}ms (${(elapsedMs/1000).toStringAsFixed(1)}s), totalMs=${totalMs}ms, source=${useCalculatedTime ? "PGN" : "DB"}');

      // Calculate remaining time: total time minus elapsed time since last move
      final remainingMs = totalMs - elapsedMs;

      // Ensure time doesn't go below 0
      final clampedMs = remainingMs < 0 ? 0 : remainingMs;

      // Format the remaining time
      final remainingTime = _formatTimeFromMs(clampedMs);

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

  /// Parses various time formats to milliseconds
  /// Supports: MM:SS, HH:MM:SS, H:MM:SS, 1h23m formats
  static int _parseTimeToMs(String timeString) {
    try {
      // Handle 1h23m format
      if (timeString.contains('h') && timeString.contains('m')) {
        final hourMatch = RegExp(r'(\d+)h').firstMatch(timeString);
        final minuteMatch = RegExp(r'(\d+)m').firstMatch(timeString);

        final hours = hourMatch != null ? int.parse(hourMatch.group(1)!) : 0;
        final minutes = minuteMatch != null ? int.parse(minuteMatch.group(1)!) : 0;

        return (hours * 3600 + minutes * 60) * 1000;
      }

      // Handle HH:MM:SS or MM:SS format
      final timeParts = timeString.split(':');
      if (timeParts.length == 2) {
        // MM:SS format
        final minutes = int.parse(timeParts[0]);
        final seconds = int.parse(timeParts[1]);
        return (minutes * 60 + seconds) * 1000;
      } else if (timeParts.length == 3) {
        // HH:MM:SS format
        final hours = int.parse(timeParts[0]);
        final minutes = int.parse(timeParts[1]);
        final seconds = int.parse(timeParts[2]);
        return (hours * 3600 + minutes * 60 + seconds) * 1000;
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