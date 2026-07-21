import 'package:chessever2/screens/library/miniatures/miniatures_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed "now": Wed 2026-06-03 14:30 local. Free users may open only games
  // whose wall-clock day is Today (2026-06-03); yesterday and older are locked.
  final now = DateTime(2026, 6, 3, 14, 30);

  bool locked(
    DateTime? gameDate, {
    bool isSubscribed = false,
    bool subscriptionLoading = false,
  }) {
    return isMiniatureGameLocked(
      gameDate,
      isSubscribed: isSubscribed,
      subscriptionLoading: subscriptionLoading,
      now: now,
    );
  }

  /// Build a UTC-midnight date matching how Miniatures store bare PGN days.
  DateTime utcDay(int year, int month, int day) =>
      DateTime.utc(year, month, day);

  group('isMiniatureGameLocked — free user Today-only window', () {
    test('game dated today (UTC midnight) is open', () {
      expect(locked(utcDay(2026, 6, 3)), isFalse);
    });

    test('game dated today with a non-midnight timestamp is open', () {
      expect(locked(DateTime.utc(2026, 6, 3, 23, 59)), isFalse);
    });

    test('game dated yesterday is locked', () {
      expect(locked(utcDay(2026, 6, 2)), isTrue);
    });

    test('game dated two days ago is locked', () {
      expect(locked(utcDay(2026, 6, 1)), isTrue);
    });

    test('game dated long ago is locked', () {
      expect(locked(utcDay(2020, 1, 1)), isTrue);
    });

    test('missing / null date is locked', () {
      expect(locked(null), isTrue);
    });
  });

  group('isMiniatureGameLocked — premium and loading bypass', () {
    test('premium user is never locked, even for very old games', () {
      expect(locked(utcDay(2020, 1, 1), isSubscribed: true), isFalse);
    });

    test('premium user is not locked for missing date', () {
      expect(locked(null, isSubscribed: true), isFalse);
    });

    test('while subscription is loading nothing is locked (no flash)', () {
      expect(locked(utcDay(2020, 1, 1), subscriptionLoading: true), isFalse);
    });

    test('loading bypass also covers missing date', () {
      expect(locked(null, subscriptionLoading: true), isFalse);
    });
  });
}
