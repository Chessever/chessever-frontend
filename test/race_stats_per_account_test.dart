import 'dart:convert';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/screens/feed/race/race_protocol.dart';
import 'package:chessever2/screens/feed/race/race_stats_store.dart';
import 'package:chessever2/screens/my_profile/race_stats_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = 'user-alice';
const _bob = 'user-bob';

String _legacy() => jsonEncode({
  'survivalBest': 31,
  'infiniteBest': 118,
  'racesPlayed': 12,
  'bestStreak': 9,
});

const _legacyStats = RaceStats(
  survivalBest: 31,
  infiniteBest: 118,
  racesPlayed: 12,
  bestStreak: 9,
);

Future<RaceStats> _profileStats(String? userId) async {
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(
        userId == null
            ? null
            : AppUser(id: userId, email: null, createdAt: DateTime(2026)),
      ),
    ],
  );
  addTearDown(container.dispose);
  final sub = container.listen(raceStatsProvider.future, (_, _) {});
  return sub.read();
}

void main() {
  group('Puzzle Race bests are kept per account', () {
    test('the first account inherits the device bests once; the next '
        'account starts empty', () async {
      SharedPreferences.setMockInitialValues({kRaceStatsPrefsKey: _legacy()});

      expect(await _profileStats(_alice), _legacyStats);
      expect(await _profileStats(_bob), RaceStats.empty);
      // Alice keeps hers after Bob looked.
      expect(await _profileStats(_alice), _legacyStats);

      // The device-wide key is copied, never removed.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kRaceStatsPrefsKey), _legacy());
    });

    test("a race lands only in the racer's bests", () async {
      SharedPreferences.setMockInitialValues({});
      var signedIn = _alice;
      final store = PrefsRaceStatsStore(userId: () => signedIn);

      await store.record(mode: RaceMode.survival, score: 20, bestStreak: 6);
      signedIn = _bob;
      await store.record(mode: RaceMode.infinite, score: 55, bestStreak: 4);

      expect(
        await _profileStats(_alice),
        const RaceStats(survivalBest: 20, racesPlayed: 1, bestStreak: 6),
      );
      expect(
        await _profileStats(_bob),
        const RaceStats(infiniteBest: 55, racesPlayed: 1, bestStreak: 4),
      );
      expect(
        await PrefsRaceStatsStore(userId: () => _bob).read(),
        const RaceBests(infiniteBest: 55, racesPlayed: 1, bestStreak: 4),
      );
    });

    test('a race recorded before anyone looked still inherits the device '
        'bests', () async {
      SharedPreferences.setMockInitialValues({kRaceStatsPrefsKey: _legacy()});
      final outcome = await PrefsRaceStatsStore(
        userId: () => _alice,
      ).record(mode: RaceMode.survival, score: 40, bestStreak: 3);

      expect(outcome.newBest, isTrue);
      expect(outcome.before.survivalBest, 31);
      expect(
        await _profileStats(_alice),
        const RaceStats(
          survivalBest: 40,
          infiniteBest: 118,
          racesPlayed: 13,
          bestStreak: 9,
        ),
      );
    });

    test('with no account the device-wide key is used as before', () async {
      SharedPreferences.setMockInitialValues({kRaceStatsPrefsKey: _legacy()});
      expect(await _profileStats(null), _legacyStats);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kRaceStatsLegacyClaimedPrefsKey), isFalse);
    });
  });
}
