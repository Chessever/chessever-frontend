import 'package:chessever2/screens/chessboard/utils/stream_scroll_coaching.dart';
import 'package:chessever2/screens/chessboard/utils/live_stream_coachmark.dart';
import 'package:flutter_test/flutter_test.dart';

class Store implements LiveStreamCoachmarkStore {
  bool seen = false;
  @override
  Future<bool> hasSeen() async => seen;
  @override
  Future<void> markSeen() async => seen = true;
}

Future<void> down(
  StreamScrollCoachingController coach, {
  bool user = true,
  bool allowed = true,
}) async {
  coach.startGesture(userDriven: user);
  coach.updateGesture(50);
  await coach.endGesture(allowed: allowed);
}

void main() {
  test(
    'programmatic scrolling, hidden pages and competing tutorials do not count',
    () async {
      final coach = StreamScrollCoachingController(Store());
      await down(coach);
      coach.setActive(true);
      await down(coach, user: false);
      await down(coach, user: false);
      await down(coach, allowed: false);
      await down(coach);
      expect(coach.showing, isFalse);
      await down(coach);
      expect(coach.showing, isTrue);
      coach.dispose();
    },
  );
  test(
    'OK suppresses this visit; switching away resets count and eligibility',
    () async {
      final coach = StreamScrollCoachingController(Store());
      coach.setActive(true);
      await down(coach);
      await down(coach);
      coach.acknowledge();
      await down(coach);
      await down(coach);
      expect(coach.showing, isFalse);
      coach.setActive(false);
      coach.setActive(true);
      await down(coach);
      expect(coach.showing, isFalse);
      await down(coach);
      expect(coach.showing, isTrue);
      coach.dispose();
    },
  );
  test(
    'dont show again persists across controller lifetimes and stops pulse',
    () async {
      final store = Store();
      final coach = StreamScrollCoachingController(store)..setActive(true);
      await down(coach);
      await down(coach);
      await coach.disable();
      expect(coach.showing, isFalse);
      expect(coach.pulsing, isFalse);
      coach.dispose();
      final next = StreamScrollCoachingController(store)..setActive(true);
      await down(next);
      await down(next);
      expect(next.showing, isFalse);
      next.dispose();
    },
  );
  test('an async eligibility change cancels presentation', () async {
    final coach = StreamScrollCoachingController(Store())..setActive(true);
    await down(coach);
    coach.startGesture(userDriven: true);
    coach.updateGesture(50);
    await coach.endGesture(stillAllowed: () => false);
    expect(coach.showing, isFalse);
    coach.dispose();
  });
  test(
    'second distinct downward drag triggers, not repeated updates or up',
    () async {
      final coach = StreamScrollCoachingController(Store());
      coach.setActive(true);
      coach.startGesture(userDriven: true);
      for (var i = 0; i < 10; i++) {
        coach.updateGesture(10);
      }
      await coach.endGesture();
      expect(coach.showing, isFalse);
      coach.startGesture(userDriven: true);
      coach.updateGesture(-100);
      await coach.endGesture();
      expect(coach.showing, isFalse);
      coach.startGesture(userDriven: true);
      coach.updateGesture(40);
      await coach.endGesture();
      expect(coach.showing, isTrue);
      coach.dispose();
    },
  );
}
