import 'dart:convert';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// SharedPreferences key of the device-wide Puzzle Race personal bests, as
/// one JSON object:
///
/// ```json
/// {"survivalBest": 31, "infiniteBest": 118, "racesPlayed": 12, "bestStreak": 9,
///  "flames": 240}
/// ```
///
/// Only a session with no account at all reads and writes it now. Every
/// account keeps its own copy under [raceStatsPrefsKeyForUser], so a second
/// account signing in on the same phone never sees the first one's bests;
/// the first account to look after this change inherits this key once
/// ([raceStatsPrefsKeyFor]).
///
/// Written by the race feature (`PrefsRaceStatsStore`, or [recordPuzzleRace]);
/// read by My Profile through [raceStatsProvider]. The reader also takes
/// snake_case keys, and a missing, negative or non-numeric field reads as 0.
const String kRaceStatsPrefsKey = 'race_stats_v1';

/// Set once an account has inherited [kRaceStatsPrefsKey]. Keeps that
/// one-time hand-over from happening a second time for whoever signs in
/// next on this device.
const String kRaceStatsLegacyClaimedPrefsKey = 'race_stats_v1_legacy_claimed';

/// The key of one account's Puzzle Race bests on this device.
String raceStatsPrefsKeyForUser(String userId) =>
    '${kRaceStatsPrefsKey}_user_$userId';

/// The signed-in account's id (guests included: an anonymous account keeps
/// its id when it is upgraded), or null with no session, or when Supabase is
/// not initialised (tests).
String? currentRaceStatsUserId() {
  try {
    final id = Supabase.instance.client.auth.currentUser?.id;
    return id == null || id.isEmpty ? null : id;
  } catch (_) {
    return null;
  }
}

/// Where [userId]'s Puzzle Race bests live on this device.
///
/// With no account it is the device-wide [kRaceStatsPrefsKey]. An account
/// reads its own [raceStatsPrefsKeyForUser]; the first account to ask on this
/// device, and only that one, starts from a copy of what was recorded before
/// bests were kept per account. The legacy key is copied, never removed.
///
/// Both claim writes are issued before the first await, so they land in
/// SharedPreferences' in-memory cache together and a concurrent caller (the
/// profile reading while a race records) can never see the marker without
/// the copy.
Future<String> raceStatsPrefsKeyFor(
  SharedPreferences prefs,
  String? userId,
) async {
  if (userId == null || userId.isEmpty) return kRaceStatsPrefsKey;
  final own = raceStatsPrefsKeyForUser(userId);
  if (prefs.containsKey(own) ||
      prefs.containsKey(kRaceStatsLegacyClaimedPrefsKey)) {
    return own;
  }
  final legacy = prefs.get(kRaceStatsPrefsKey);
  final writes = <Future<bool>>[
    if (legacy is String && legacy.isNotEmpty) prefs.setString(own, legacy),
    prefs.setBool(kRaceStatsLegacyClaimedPrefsKey, true),
  ];
  try {
    await Future.wait(writes);
  } catch (error) {
    // The cache already holds the claim; the disk catches up on the next
    // write, or the hand-over simply runs again next launch.
    debugPrint(
      '[Race] could not persist bests hand-over: ${error.runtimeType}',
    );
  }
  return own;
}

/// The two Puzzle Race modes that keep a best score.
enum PuzzleRaceMode { survival, infinite }

@immutable
class RaceStats {
  const RaceStats({
    this.survivalBest = 0,
    this.infiniteBest = 0,
    this.racesPlayed = 0,
    this.bestStreak = 0,
    this.flames = 0,
  });

  final int survivalBest;
  final int infiniteBest;
  final int racesPlayed;
  final int bestStreak;

  /// Flames earned on this device for this account (added later; a copy
  /// without it reads 0).
  final int flames;

  static const empty = RaceStats();

  /// Nothing recorded yet: the profile shows "No races yet".
  bool get isEmpty =>
      racesPlayed == 0 &&
      survivalBest == 0 &&
      infiniteBest == 0 &&
      bestStreak == 0 &&
      flames == 0;

  /// Reads [kRaceStatsPrefsKey]'s value. Never throws: null, malformed JSON
  /// or a non-object reads as [empty].
  static RaceStats decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      return empty;
    }
    if (json is! Map) return empty;
    final map = json;
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

    return RaceStats(
      survivalBest: read('survivalBest', 'survival_best'),
      infiniteBest: read('infiniteBest', 'infinite_best'),
      racesPlayed: read('racesPlayed', 'races_played'),
      bestStreak: read('bestStreak', 'best_streak'),
      flames: read('flames', 'flames'),
    );
  }

  String encode() => jsonEncode({
    'survivalBest': survivalBest,
    'infiniteBest': infiniteBest,
    'racesPlayed': racesPlayed,
    'bestStreak': bestStreak,
    'flames': flames,
  });

  /// These stats with one finished race folded in.
  RaceStats withRace({
    required PuzzleRaceMode mode,
    required int score,
    required int streak,
    int flames = 0,
  }) {
    final s = score < 0 ? 0 : score;
    final k = streak < 0 ? 0 : streak;
    return RaceStats(
      survivalBest: mode == PuzzleRaceMode.survival && s > survivalBest
          ? s
          : survivalBest,
      infiniteBest: mode == PuzzleRaceMode.infinite && s > infiniteBest
          ? s
          : infiniteBest,
      racesPlayed: racesPlayed + 1,
      bestStreak: k > bestStreak ? k : bestStreak,
      flames: this.flames + (flames < 0 ? 0 : flames),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RaceStats &&
      other.survivalBest == survivalBest &&
      other.infiniteBest == infiniteBest &&
      other.racesPlayed == racesPlayed &&
      other.bestStreak == bestStreak &&
      other.flames == flames;

  @override
  int get hashCode =>
      Object.hash(survivalBest, infiniteBest, racesPlayed, bestStreak, flames);
}

/// The signed-in account's Puzzle Race personal bests on this device.
/// Auto-disposed, so every visit to My Profile reads what the last race
/// wrote; rebuilt when the account changes, so a sign-in as someone else
/// never shows the previous account's bests.
final raceStatsProvider = FutureProvider.autoDispose<RaceStats>((ref) async {
  // The auth stream drives rebuilds; the SDK's own user covers the frame
  // where the stream is still loading, so that frame cannot fall back to the
  // device-wide key.
  final userId =
      ref.watch(currentUserProvider.select((user) => user?.id)) ??
      currentRaceStatsUserId();
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = await raceStatsPrefsKeyFor(prefs, userId);
    final raw = prefs.get(key);
    return RaceStats.decode(raw is String ? raw : null);
  } catch (_) {
    return RaceStats.empty;
  }
});

/// Folds one finished race into the stored personal bests of [userId]
/// (default: the signed-in account). For the race feature; returns what is
/// now stored.
Future<RaceStats> recordPuzzleRace({
  required PuzzleRaceMode mode,
  required int score,
  required int streak,
  int flames = 0,
  String? userId,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await raceStatsPrefsKeyFor(
    prefs,
    userId ?? currentRaceStatsUserId(),
  );
  final raw = prefs.get(key);
  final next = RaceStats.decode(
    raw is String ? raw : null,
  ).withRace(mode: mode, score: score, streak: streak, flames: flames);
  // Written over what is stored, as the race's own store does: keys this
  // reader does not know (the race's `updatedAt`, a newer app's fields)
  // survive, and the snake_case spellings it replaces are dropped.
  Map<String, Object?> stored = const {};
  if (raw is String) {
    try {
      final json = jsonDecode(raw);
      if (json is Map) stored = json.cast<String, Object?>();
    } catch (_) {
      // Unreadable: start over.
    }
  }
  final merged = <String, Object?>{
    ...stored,
    ...(jsonDecode(next.encode()) as Map).cast<String, Object?>(),
  };
  for (final snake in const [
    'survival_best',
    'infinite_best',
    'races_played',
    'best_streak',
  ]) {
    merged.remove(snake);
  }
  await prefs.setString(key, jsonEncode(merged));
  return next;
}
