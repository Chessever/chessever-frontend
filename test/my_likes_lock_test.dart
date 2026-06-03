import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed "now": Wed 2026-06-03 14:30 local. The free window is the last 7
  // calendar days (today + 6 prior), i.e. liked-at on/after 2026-05-28 is open.
  final now = DateTime(2026, 6, 3, 14, 30);

  bool locked(
    DateTime likedAt, {
    bool isSubscribed = false,
    bool subscriptionLoading = false,
  }) {
    return isLikedGameLocked(
      likedAt,
      isSubscribed: isSubscribed,
      subscriptionLoading: subscriptionLoading,
      now: now,
    );
  }

  group('isLikedGameLocked — free user 7-day window', () {
    test('liked just now (today) is open', () {
      expect(locked(DateTime(2026, 6, 3, 9, 0)), isFalse);
    });

    test('liked late today is open regardless of time of day', () {
      expect(locked(DateTime(2026, 6, 3, 23, 59)), isFalse);
    });

    test('liked yesterday is open', () {
      expect(locked(DateTime(2026, 6, 2, 1, 0)), isFalse);
    });

    test('liked exactly 6 days ago (window edge) is open', () {
      expect(locked(DateTime(2026, 5, 28, 23, 0)), isFalse);
    });

    test('liked 7 days ago is locked', () {
      expect(locked(DateTime(2026, 5, 27, 23, 0)), isTrue);
    });

    test('liked 8 days ago is locked', () {
      expect(locked(DateTime(2026, 5, 26, 12, 0)), isTrue);
    });

    test('liked long ago is locked', () {
      expect(locked(DateTime(2025, 1, 1)), isTrue);
    });
  });

  group('isLikedGameLocked — premium and loading bypass', () {
    test('premium user is never locked, even for very old likes', () {
      expect(
        locked(DateTime(2020, 1, 1), isSubscribed: true),
        isFalse,
      );
    });

    test('while subscription is loading nothing is locked (no flash)', () {
      expect(
        locked(DateTime(2020, 1, 1), subscriptionLoading: true),
        isFalse,
      );
    });
  });
}
