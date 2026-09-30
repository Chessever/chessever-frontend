import 'dart:convert';

import 'package:chessever2/screens/feed/race/race_protocol.dart';
import 'package:chessever2/screens/my_profile/race_stats_provider.dart'
    show currentRaceStatsUserId, kRaceStatsPrefsKey, raceStatsPrefsKeyFor;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key of the device-wide Puzzle Race personal bests, used
/// only with no account signed in: each account keeps its own copy, and
/// `raceStatsPrefsKeyFor` in `lib/screens/my_profile/race_stats_provider.dart`
/// (which My Profile reads through) picks the key. One JSON object:
///
/// ```json
/// {"survivalBest": 31, "infiniteBest": 118, "racesPlayed": 12,
///  "bestStreak": 9, "flames": 240, "updatedAt": "2026-09-23T10:00:00.000Z"}
/// ```
///
/// `flames` came later: a copy without it reads 0, and every other key is
/// kept exactly as before.
const String kRaceStatsKey = kRaceStatsPrefsKey;

/// The stored personal bests.
@immutable
class RaceBests {
  const RaceBests({
    this.survivalBest = 0,
    this.infiniteBest = 0,
    this.racesPlayed = 0,
    this.bestStreak = 0,
    this.flames = 0,
  });

  static const empty = RaceBests();

  /// Reads the stored JSON. Never throws; anything unreadable is 0. Takes
  /// the snake_case spellings too, like the profile's reader.
  static RaceBests decode(String? raw) => fromMap(_decodeMap(raw));

  static RaceBests fromMap(Map<String, Object?> map) {
    int read(String camel, String snake) {
      final value = map[camel] ?? map[snake];
      final number = switch (value) {
        final num n => n,
        final String s => num.tryParse(s),
        _ => null,
      };
      if (number == null || !number.isFinite || number < 0) return 0;
      return number.floor();
    }

    return RaceBests(
      survivalBest: read('survivalBest', 'survival_best'),
      infiniteBest: read('infiniteBest', 'infinite_best'),
      racesPlayed: read('racesPlayed', 'races_played'),
      bestStreak: read('bestStreak', 'best_streak'),
      flames: read('flames', 'flames'),
    );
  }

  final int survivalBest;
  final int infiniteBest;
  final int racesPlayed;
  final int bestStreak;

  /// Flames earned on this device (for this account). A guest's only count;
  /// a signed-in player's stand-in until the service's own answers.
  final int flames;

  int bestFor(RaceMode mode) =>
      mode == RaceMode.survival ? survivalBest : infiniteBest;

  /// These bests with one finished race folded in.
  RaceBests withRace({
    required RaceMode mode,
    required int score,
    required int streak,
    int flames = 0,
  }) {
    final s = score < 0 ? 0 : score;
    final k = streak < 0 ? 0 : streak;
    return RaceBests(
      survivalBest: mode == RaceMode.survival && s > survivalBest
          ? s
          : survivalBest,
      infiniteBest: mode == RaceMode.infinite && s > infiniteBest
          ? s
          : infiniteBest,
      racesPlayed: racesPlayed + 1,
      bestStreak: k > bestStreak ? k : bestStreak,
      flames: this.flames + (flames < 0 ? 0 : flames),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RaceBests &&
      other.survivalBest == survivalBest &&
      other.infiniteBest == infiniteBest &&
      other.racesPlayed == racesPlayed &&
      other.bestStreak == bestStreak &&
      other.flames == flames;

  @override
  int get hashCode =>
      Object.hash(survivalBest, infiniteBest, racesPlayed, bestStreak, flames);
}

Map<String, Object?> _decodeMap(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final json = jsonDecode(raw);
    if (json is Map) return json.cast<String, Object?>();
  } catch (_) {
    // Unreadable: start over.
  }
  return {};
}

/// What recording one race changed.
@immutable
class RaceRecordOutcome {
  const RaceRecordOutcome({
    required this.before,
    required this.after,
    required this.newBest,
  });

  final RaceBests before;
  final RaceBests after;

  /// The score beat this mode's previous best (and is above zero).
  final bool newBest;
}

/// Where the bests live. Overridden in tests.
abstract interface class RaceStatsStore {
  Future<RaceBests> read();

  /// Folds one finished race in; [flames] is what the run earned.
  Future<RaceRecordOutcome> record({
    required RaceMode mode,
    required int score,
    required int bestStreak,
    int flames = 0,
  });
}

class PrefsRaceStatsStore implements RaceStatsStore {
  PrefsRaceStatsStore({DateTime Function()? clock, String? Function()? userId})
    : _clock = clock ?? DateTime.now,
      _userId = userId ?? currentRaceStatsUserId;

  final DateTime Function() _clock;

  /// Whose bests: asked on every read and record, so a sign-in as someone
  /// else mid-session moves to that account's bests.
  final String? Function() _userId;

  @override
  Future<RaceBests> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await raceStatsPrefsKeyFor(prefs, _userId());
      return RaceBests.decode(prefs.getString(key));
    } catch (error) {
      debugPrint('[Race] could not read bests: ${error.runtimeType}');
      return RaceBests.empty;
    }
  }

  /// Folds the race in and writes it back. Keys this app does not know are
  /// kept, so a newer reader's fields survive an older writer.
  @override
  Future<RaceRecordOutcome> record({
    required RaceMode mode,
    required int score,
    required int bestStreak,
    int flames = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await raceStatsPrefsKeyFor(prefs, _userId());
    final stored = _decodeMap(prefs.getString(key));
    final before = RaceBests.fromMap(stored);
    final after = before.withRace(
      mode: mode,
      score: score,
      streak: bestStreak,
      flames: flames,
    );
    final next = <String, Object?>{
      ...stored,
      'survivalBest': after.survivalBest,
      'infiniteBest': after.infiniteBest,
      'racesPlayed': after.racesPlayed,
      'bestStreak': after.bestStreak,
      'flames': after.flames,
      'updatedAt': _clock().toUtc().toIso8601String(),
    };
    // The snake_case spellings would shadow nothing but could go stale.
    for (final key in const [
      'survival_best',
      'infinite_best',
      'races_played',
      'best_streak',
    ]) {
      next.remove(key);
    }
    await prefs.setString(key, jsonEncode(next));
    return RaceRecordOutcome(
      before: before,
      after: after,
      newBest: score > 0 && score > before.bestFor(mode),
    );
  }
}
