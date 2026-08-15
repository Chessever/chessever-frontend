import 'package:chessever2/utils/date_time_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Remaining time at which a board clock starts resolving one tenth of a
/// second. One digit — not three-digit milliseconds, which overflow the chip.
const _subSecondWindow = Duration(seconds: 30);

/// The 1 Hz [dateTimeProvider] can only place the remaining time to the nearest
/// second, so the fine ticker is armed a second early. Without that lead-in the
/// reveal could fire up to a second after the real 30.0 s crossing.
const _subSecondArmWindow = Duration(seconds: 31);

/// Spring for the tenths reveal. No bounce on purpose: a digit that overshoots
/// and settles back reads as a glitch rather than as motion.
const _subSecondReveal = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 300),
);

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
    this.showSubSecond = false,
  });

  final String? moveTime; // Legacy: for chessboard screen with PGN parsing
  final int?
  clockSeconds; // Primary source: time in seconds from last_clock fields
  final int
  clockCentiseconds; // Fallback source: raw database clock in centiseconds
  final DateTime? lastMoveTime;
  final bool isActive;
  final TextStyle style;

  /// Opt-in tenth-of-a-second digit, revealed once the *running* clock drops
  /// under [_subSecondWindow]. Only the focused board rows pass this; every
  /// other [AtomicCountdownText] (game cards, explorer, switcher minis) stays
  /// on whole seconds so the extra glyph cannot overflow those chips.
  final bool showSubSecond;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine which time source to use: clockSeconds (primary), moveTime (secondary), clockCentiseconds (fallback)
    final useClockSeconds = clockSeconds != null;
    final useCalculatedTime =
        !useClockSeconds && moveTime != null && moveTime!.isNotEmpty;
    final hasCentisecondClock = clockCentiseconds > 0;
    final hasAnyClockSource =
        useClockSeconds || useCalculatedTime || hasCentisecondClock;

    if (!hasAnyClockSource) {
      return Text('--:--', style: style);
    }

    final staticLabel = _staticLabel(useClockSeconds, useCalculatedTime);

    // Board player rows own the whole running/stopped cycle so the tenths can
    // animate *out* when the turn passes, instead of being cut off by a widget
    // swap. Everything below this branch is the untouched shared behaviour.
    if (showSubSecond && lastMoveTime != null) {
      return _SubSecondCountdownText(
        totalSeconds: _resolveTotalSeconds(useClockSeconds, useCalculatedTime),
        lastMoveTime: lastMoveTime!,
        isActive: isActive,
        style: style,
        staticLabel: staticLabel,
      );
    }

    // Only watch dateTimeProvider if clock is actively counting down
    if (!isActive || lastMoveTime == null) {
      return Text(staticLabel, style: style);
    }

    // Atomic rebuild - only this Text widget rebuilds every second
    final displayTime = ref.watch(
      dateTimeProvider.select((timeAsync) {
        final currentTime = timeAsync.valueOrNull;
        if (currentTime == null) {
          return staticLabel;
        }

        // Calculate elapsed time since lastMoveTime (when the previous player finished their move)
        // This is how long the current player has been thinking on their turn
        final elapsedSeconds =
            currentTime.difference(lastMoveTime!).inSeconds.abs();

        final totalSeconds = _resolveTotalSeconds(
          useClockSeconds,
          useCalculatedTime,
        );

        // Calculate remaining time: total time minus elapsed time since last move
        final remainingSeconds = totalSeconds - elapsedSeconds;

        // Ensure time doesn't go below 0
        final clampedSeconds = remainingSeconds < 0 ? 0 : remainingSeconds;

        // Format the remaining time
        final remainingTime = _formatTimeFromSeconds(clampedSeconds);

        // Convert to hh:mm:ss format if over 1 hour
        return _formatTimeWithHours(remainingTime);
      }),
    );

    return Text(displayTime, style: style);
  }

  /// The clock as it reads when nothing is counting down: the newest snapshot
  /// from whichever source is available.
  String _staticLabel(bool useClockSeconds, bool useCalculatedTime) {
    if (useClockSeconds) {
      return _formatTimeWithHours(_formatTimeFromSeconds(clockSeconds!));
    }
    if (useCalculatedTime) {
      return _formatTimeWithHours(moveTime!);
    }
    return _formatTimeWithHours(_formatTimeFromMs(clockCentiseconds * 10));
  }

  /// Seconds on this player's clock at [lastMoveTime], from the highest
  /// priority source that has a usable value.
  int _resolveTotalSeconds(bool useClockSeconds, bool useCalculatedTime) {
    if (useClockSeconds) {
      // Primary source: Use clock seconds directly
      return clockSeconds!;
    }
    if (useCalculatedTime) {
      // Secondary source: Parse calculated moveTime
      final parsed = _parseTimeToSeconds(moveTime!);
      // If parsing fails, fallback to clock centiseconds
      return parsed == 0 ? (clockCentiseconds / 100).floor() : parsed;
    }
    // Fallback source: Use raw clock centiseconds (convert to seconds)
    return (clockCentiseconds / 100).floor();
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
        final minutes =
            minuteMatch != null ? int.parse(minuteMatch.group(1)!) : 0;

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
  /// Output is h:mm:ss (hours unpadded to save width) with minutes and
  /// seconds always 2 digits, or mm:ss when under an hour.
  static String _formatTimeWithHours(String timeString) {
    if (timeString.contains('h')) {
      return timeString; // "1h23m" style from ChessClockExtension
    }

    final timeParts = timeString.split(':');

    try {
      if (timeParts.length == 3) {
        // Normalize HH:MM:SS: strip hour zero-pad, keep mm/ss at 2 digits
        final hours = int.parse(timeParts[0]);
        final minutes = int.parse(timeParts[1]);
        final seconds = int.parse(timeParts[2]);
        return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      }

      if (timeParts.length != 2) {
        return timeString; // Return original if not in expected format
      }

      final minutes = int.parse(timeParts[0]);
      final seconds = int.parse(timeParts[1]);

      // If less than 60 minutes, return as MM:SS (always 2-digit padded)
      if (minutes < 60) {
        return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      }

      // Convert to h:mm:ss format
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;

      return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } catch (e) {
      return timeString; // Return original if parsing fails
    }
  }
}

/// The board screen's clock: whole seconds like everywhere else, plus one
/// tenth digit that springs in for the last [_subSecondWindow] of a *running*
/// clock.
///
/// Hours, minutes, seconds, and the tenth are all floored off the same
/// remaining-millisecond value, so `.0` always rolls into the next second the
/// same way `00` seconds roll into the next minute and `00` minutes roll into
/// the next hour. The fraction is tied to the running clock on purpose: every
/// clock source the app has (`last_clock_*`, the move-40 bonus, PGN `[%clk]`)
/// is whole-second granular, so the digit is only meaningful as the continuous
/// countdown since `lastMoveTime`. A stopped clock has no fraction to show —
/// printing `.0` there would be invented precision — so the digit hands off
/// between the two rows as the turn changes rather than blinking in place.
class _SubSecondCountdownText extends ConsumerWidget {
  const _SubSecondCountdownText({
    required this.totalSeconds,
    required this.lastMoveTime,
    required this.isActive,
    required this.style,
    required this.staticLabel,
  });

  final int totalSeconds;
  final DateTime lastMoveTime;
  final bool isActive;
  final TextStyle style;
  final String staticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var label = staticLabel;
    var tenths = 0;
    var inWindow = false;

    if (isActive) {
      final coarseNow = ref.watch(dateTimeProvider).valueOrNull;
      if (coarseNow != null) {
        // Above the window this is the exact arithmetic the shared clock uses,
        // so the board row and a card showing the same game never disagree.
        final elapsedSeconds = coarseNow.difference(lastMoveTime).inSeconds.abs();
        final coarseRemaining = totalSeconds - elapsedSeconds;
        label = AtomicCountdownText._formatTimeWithHours(
          AtomicCountdownText._formatTimeFromSeconds(
            coarseRemaining < 0 ? 0 : coarseRemaining,
          ),
        );

        if (coarseRemaining <= _subSecondArmWindow.inSeconds) {
          final fineNow =
              ref.watch(subSecondTimeProvider).valueOrNull ?? coarseNow;
          final elapsedMs =
              fineNow.difference(lastMoveTime).inMilliseconds.abs();
          final rawRemainingMs = totalSeconds * 1000 - elapsedMs;
          final remainingMs = rawRemainingMs < 0 ? 0 : rawRemainingMs;

          if (remainingMs < _subSecondWindow.inMilliseconds) {
            inWindow = true;
            // Inside the window the seconds are floored off the same millisecond
            // reading as the tenths, so `00:12` and `.4` can never contradict
            // each other. The one-off handover from the coarse value only ever
            // steps the clock down, never back up.
            label = AtomicCountdownText._formatTimeWithHours(
              AtomicCountdownText._formatTimeFromSeconds(remainingMs ~/ 1000),
            );
            // One digit (0–9), not `remainingMs % 1000` (milliseconds).
            tenths = (remainingMs % 1000) ~/ 100;
          }
        }
      }
    }

    // Same size and the same tabular figures as the clock, dimmed a step. The
    // fraction has to read as subordinate to the seconds without introducing a
    // second type size (which would drag a second baseline into the row) or a
    // colour that belongs to nothing else on screen.
    final fractionColor = (style.color ?? DefaultTextStyle.of(context).style.color)
        ?.withValues(alpha: 0.62);

    return Semantics(
      label: inWindow ? '$label.$tenths' : label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: style),
          SingleMotionBuilder(
            motion: _subSecondReveal,
            value: inWindow ? 1.0 : 0.0,
            builder: (context, t, child) {
              if (t <= 0.001) return const SizedBox.shrink();
              final progress = t.clamp(0.0, 1.0);
              // At rest the digit carries no clip at all, so a glyph's side
              // bearing can never be shaved by the box that reveals it.
              if (progress >= 0.999) return child!;
              return ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Opacity(opacity: progress, child: child),
                ),
              );
            },
            child: Text('.$tenths', style: style.copyWith(color: fractionColor)),
          ),
        ],
      ),
    );
  }
}
