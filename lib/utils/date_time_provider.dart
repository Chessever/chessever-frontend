import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provides a stream of DateTime values that updates every second
/// Used for real-time countdown timers in chess games
final dateTimeProvider = StreamProvider<DateTime>((ref) async* {
  // Emit the current time immediately
  yield DateTime.now();

  // Then emit every second
  await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
    yield DateTime.now();
  }
});

/// Fine-grained tick used only while a *running* board clock is inside the
/// last-30-seconds window, where the focused board row resolves one tenth of
/// a second.
///
/// Deliberately `autoDispose`: the periodic timer exists only while some clock
/// is actually asking for the tenth, so the rest of the app — every game card,
/// every idle clock — stays on the 1 Hz [dateTimeProvider]. 50 ms keeps the
/// displayed tenth at most half a tenth stale.
final subSecondTimeProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();

  await for (final _ in Stream.periodic(const Duration(milliseconds: 50))) {
    yield DateTime.now();
  }
});

/// Helper extension for calculating time differences for chess clocks
extension ChessClockExtension on DateTime {
  /// Calculates remaining time given a clock duration in milliseconds
  /// and returns formatted time string (MM:SS)
  String calculateRemainingTime(int clockMs, DateTime? lastMoveTime) {
    if (lastMoveTime == null) {
      // If no last move time, return the static clock time
      return _formatTime(clockMs);
    }

    // Calculate elapsed time since last move
    final elapsedMs = difference(lastMoveTime).inMilliseconds.abs();

    // Calculate remaining time
    final remainingMs = clockMs - elapsedMs;

    // Ensure time doesn't go below 0
    final clampedMs = remainingMs < 0 ? 0 : remainingMs;

    return _formatTime(clampedMs);
  }

  /// Formats milliseconds to MM:SS format
  static String _formatTime(int milliseconds) {
    if (milliseconds <= 0) {
      return '00:00';
    }

    final totalSeconds = (milliseconds / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    // Handle display for very long games (over 99 minutes)
    if (minutes > 99) {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return '${hours}h${remainingMinutes.toString().padLeft(2, '0')}m';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
