import 'package:chessever2/screens/standings/utils/scorecard_name_actions.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryCoachmarkStore implements ScorecardNameCoachmarkStore {
  bool seen = false;
  bool throwOnRead = false;
  int writes = 0;

  @override
  Future<bool> hasSeen() async {
    if (throwOnRead) throw StateError('storage unavailable');
    return seen;
  }

  @override
  Future<void> markSeen() async {
    seen = true;
    writes += 1;
  }
}

void main() {
  group('ScorecardNameCoachmarkTracker', () {
    test('persists only after the coachmark is displayed', () async {
      final store = _MemoryCoachmarkStore();
      final tracker = ScorecardNameCoachmarkTracker(store);

      expect(await tracker.claim(), isTrue);
      expect(store.writes, 0);

      await tracker.markShown();

      expect(store.writes, 1);
      expect(await tracker.claim(), isFalse);
    });

    test('allows only one concurrent coachmark reservation', () async {
      final store = _MemoryCoachmarkStore();
      final tracker = ScorecardNameCoachmarkTracker(store);

      final results = await Future.wait([tracker.claim(), tracker.claim()]);

      expect(results.where((claimed) => claimed), hasLength(1));
      expect(store.writes, 0);
    });

    test(
      'releases an undisplayed reservation for the next active page',
      () async {
        final store = _MemoryCoachmarkStore();
        final tracker = ScorecardNameCoachmarkTracker(store);

        expect(await tracker.claim(), isTrue);
        tracker.release();
        expect(await tracker.claim(), isTrue);
        expect(store.writes, 0);
      },
    );

    test('does not show after a previous session marked it seen', () async {
      final store = _MemoryCoachmarkStore()..seen = true;
      final tracker = ScorecardNameCoachmarkTracker(store);

      expect(await tracker.claim(), isFalse);
      expect(store.writes, 0);
    });

    test('fails closed when coaching storage is unavailable', () async {
      final store = _MemoryCoachmarkStore()..throwOnRead = true;
      final tracker = ScorecardNameCoachmarkTracker(store);

      expect(await tracker.claim(), isFalse);
      expect(store.writes, 0);
    });
  });

  group('displayScorecardNameCoachmark', () {
    test(
      'does not consume coaching when the page deactivates during load',
      () async {
        final store = _MemoryCoachmarkStore();
        final tracker = ScorecardNameCoachmarkTracker(store);

        expect(
          await displayScorecardNameCoachmark(
            tracker: tracker,
            isEligible: () => false,
            showTooltip: () => true,
          ),
          isFalse,
        );
        expect(store.writes, 0);

        expect(
          await displayScorecardNameCoachmark(
            tracker: tracker,
            isEligible: () => true,
            showTooltip: () => true,
          ),
          isTrue,
        );
        expect(store.writes, 1);
      },
    );

    test('retries when the tooltip state is not available', () async {
      final store = _MemoryCoachmarkStore();
      final tracker = ScorecardNameCoachmarkTracker(store);

      expect(
        await displayScorecardNameCoachmark(
          tracker: tracker,
          isEligible: () => true,
          showTooltip: () => false,
        ),
        isFalse,
      );
      expect(store.writes, 0);

      expect(
        await displayScorecardNameCoachmark(
          tracker: tracker,
          isEligible: () => true,
          showTooltip: () => true,
        ),
        isTrue,
      );
      expect(store.writes, 1);
    });
  });
}
