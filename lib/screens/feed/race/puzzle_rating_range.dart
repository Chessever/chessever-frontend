import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The puzzle difficulty a player picked, shared by the Puzzle Race lobby
/// (where a race starts: [PuzzleRatingRange.min]) and the Feed's casual
/// puzzles (drawn from the whole band).
///
/// Device-local and per install. Nothing here is trusted by the server: a race
/// room still judges every move itself, this only chooses where the ladder
/// starts.
@immutable
class PuzzleRatingRange {
  const PuzzleRatingRange(this.min, this.max)
    : assert(min >= kPuzzleRatingFloor),
      assert(max <= kPuzzleRatingCeiling),
      assert(min < max);

  final int min;
  final int max;

  /// The preset this range matches exactly, if any.
  PuzzleRatingPreset? get preset {
    for (final p in PuzzleRatingPreset.values) {
      if (p.range == this) return p;
    }
    return null;
  }

  PuzzleRatingRange copyWith({int? min, int? max}) =>
      PuzzleRatingRange(min ?? this.min, max ?? this.max);

  @override
  bool operator ==(Object other) =>
      other is PuzzleRatingRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => '$min–$max';
}

/// Lowest and highest ratings the puzzle catalogue serves (gamebase buckets
/// are 50 points wide and Lichess ratings stop around 3300).
const int kPuzzleRatingFloor = 400;
const int kPuzzleRatingCeiling = 3200;

/// Snap step for custom ranges: one gamebase rating bucket.
const int kPuzzleRatingStep = 50;

/// Smallest band a custom range may be, so the ladder never runs dry.
const int kPuzzleRatingMinSpan = 200;

enum PuzzleRatingPreset {
  beginner('Beginner', PuzzleRatingRange(600, 1000)),
  club('Club', PuzzleRatingRange(1000, 1500)),
  strong('Strong', PuzzleRatingRange(1500, 2000)),
  expert('Expert', PuzzleRatingRange(2000, 2500)),
  master('Master', PuzzleRatingRange(2500, 3000));

  const PuzzleRatingPreset(this.label, this.range);

  final String label;
  final PuzzleRatingRange range;
}

/// What a first-time player gets: the old fixed race start (800) sits inside
/// it, so nobody is surprised on day one.
const PuzzleRatingRange kDefaultPuzzleRatingRange = PuzzleRatingRange(
  800,
  1400,
);

const String kPuzzleRatingRangePrefsKey = 'puzzle_rating_range_v1';

/// Clamps and snaps any pair into a valid range (floor/ceiling, 50-point
/// steps, at least [kPuzzleRatingMinSpan] wide).
PuzzleRatingRange normalizePuzzleRatingRange(int min, int max) {
  int snap(int v) =>
      ((v / kPuzzleRatingStep).round() * kPuzzleRatingStep)
          .clamp(kPuzzleRatingFloor, kPuzzleRatingCeiling)
          .toInt();
  var lo = snap(min < max ? min : max);
  var hi = snap(min < max ? max : min);
  if (hi - lo < kPuzzleRatingMinSpan) {
    hi = lo + kPuzzleRatingMinSpan;
    if (hi > kPuzzleRatingCeiling) {
      hi = kPuzzleRatingCeiling;
      lo = hi - kPuzzleRatingMinSpan;
    }
  }
  return PuzzleRatingRange(lo, hi);
}

final puzzleRatingRangeProvider =
    NotifierProvider<PuzzleRatingRangeNotifier, PuzzleRatingRange>(
      PuzzleRatingRangeNotifier.new,
    );

class PuzzleRatingRangeNotifier extends Notifier<PuzzleRatingRange> {
  @override
  PuzzleRatingRange build() {
    _restore();
    return kDefaultPuzzleRatingRange;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kPuzzleRatingRangePrefsKey);
      final parsed = decodePuzzleRatingRange(raw);
      if (parsed != null && parsed != state) state = parsed;
    } catch (_) {
      // A missing or unreadable preference keeps the default.
    }
  }

  Future<void> set(PuzzleRatingRange range) async {
    final next = normalizePuzzleRatingRange(range.min, range.max);
    if (next == state) return;
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPuzzleRatingRangePrefsKey, '${next.min}-${next.max}');
    } catch (_) {
      // Keeps working for this session even if it cannot be saved.
    }
  }

  Future<void> choose(PuzzleRatingPreset preset) => set(preset.range);
}

/// `"1000-1500"` → range; anything else → null.
@visibleForTesting
PuzzleRatingRange? decodePuzzleRatingRange(String? raw) {
  if (raw == null) return null;
  final parts = raw.split('-');
  if (parts.length != 2) return null;
  final lo = int.tryParse(parts[0].trim());
  final hi = int.tryParse(parts[1].trim());
  if (lo == null || hi == null) return null;
  return normalizePuzzleRatingRange(lo, hi);
}
