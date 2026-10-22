import 'package:chessever2/screens/chessboard/utils/board_feature_teaching_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

class Store implements BoardFeatureTeachingStore {
  Map<String, Object?>? value;
  @override
  Future<Map<String, Object?>?> read() async => value;
  @override
  Future<void> write(Map<String, Object?> value) async => this.value = value;
}

void main() {
  test(
    'first Likes opening teaches once, including a new tracker/restart',
    () async {
      final store = Store();
      var shown = 0;
      final tracker = BoardFeatureTeachingTracker(store);
      expect(
        await tracker.tryShowDiscoveryLikes(() {
          shown++;
          return true;
        }),
        true,
      );
      expect(
        await tracker.tryShowDiscoveryLikes(() {
          shown++;
          return true;
        }),
        false,
      );
      expect(
        await BoardFeatureTeachingTracker(store).tryShowDiscoveryLikes(() {
          shown++;
          return true;
        }),
        false,
      );
      expect(shown, 1);
    },
  );
  test('deferred presentation does not consume the first opening', () async {
    final tracker = BoardFeatureTeachingTracker(Store());
    expect(await tracker.tryShowDiscoveryLikes(() => false), false);
    expect(await tracker.tryShowDiscoveryLikes(() => true), true);
  });
  for (final flag in ['disabled', 'learned']) {
    test('respects existing like $flag state', () async {
      final store = Store()
        ..value = {
          'features': {
            'like': {flag: true},
          },
        };
      expect(
        await BoardFeatureTeachingTracker(
          store,
        ).tryShowDiscoveryLikes(() => true),
        false,
      );
    });
  }
  test(
    'concurrent first openings serialize and share teaching cooldown',
    () async {
      final tracker = BoardFeatureTeachingTracker(Store());
      final visit = await tracker.beginVisit();
      expect(
        await Future.wait([
          tracker.tryShowDiscoveryLikes(() => true),
          tracker.tryShowDiscoveryLikes(() => true),
        ]),
        [true, false],
      );
      expect(
        await tracker.tryShow(
          visit: visit,
          eligible: BoardTeachingFeature.values.toSet(),
          show: (_) => true,
        ),
        false,
      );
    },
  );
}
