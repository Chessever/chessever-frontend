import 'dart:convert';
import 'dart:math';

import 'package:chessever2/screens/chessboard/utils/board_feature_teaching_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryTeachingStore implements BoardFeatureTeachingStore {
  Map<String, Object?>? value;
  bool fail = false;
  Map<String, Object?>? _copy(Map<String, Object?>? value) => value == null
      ? null
      : Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
  @override
  Future<Map<String, Object?>?> read() async {
    if (fail) throw StateError('Unavailable');
    return _copy(value);
  }

  @override
  Future<void> write(Map<String, Object?> value) async {
    if (fail) throw StateError('Unavailable');
    this.value = _copy(value);
  }
}

class FirstTeachingRandom implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryTeachingStore store;
  late DateTime now;
  late BoardFeatureTeachingTracker tracker;
  late List<BoardTeachingFeature> shown;

  setUp(() {
    store = MemoryTeachingStore();
    now = DateTime.utc(2026, 10, 15);
    tracker = BoardFeatureTeachingTracker(
      store,
      random: FirstTeachingRandom(),
      now: () => now,
    );
    shown = [];
  });

  Future<int> visits(int count) async {
    var visit = 0;
    for (var i = 0; i < count; i++) {
      visit = await tracker.beginVisit();
    }
    return visit;
  }

  Future<bool> prompt(
    int visit, {
    Set<BoardTeachingFeature>? eligible,
    bool display = true,
  }) => tracker.tryShow(
    visit: visit,
    eligible: eligible ?? BoardTeachingFeature.values.toSet(),
    show: (feature) {
      if (display) shown.add(feature);
      return display;
    },
  );

  test(
    'first visits never prompt, repeated checks do not reroll or consume a target',
    () async {
      for (var visit = 1; visit <= 2; visit++) {
        expect(await tracker.beginVisit(), visit);
        for (var attempt = 0; attempt < 10; attempt++) {
          expect(await prompt(visit), isFalse);
        }
      }
      expect(await prompt(await tracker.beginVisit()), isTrue);
      expect(await prompt(3), isFalse);
      expect(shown, [BoardTeachingFeature.like]);
    },
  );

  test(
    'random targets persist across process restarts and stay in visits 3–5',
    () async {
      final targets = <int>{};
      for (var seed = 0; seed < 20; seed++) {
        final storage = MemoryTeachingStore();
        var instance = BoardFeatureTeachingTracker(
          storage,
          random: Random(seed),
        );
        await instance.beginVisit();
        final features = storage.value!['features'] as Map;
        final target = (features['like'] as Map)['nextVisit'] as int;
        targets.add(target);
        instance = BoardFeatureTeachingTracker(storage, random: Random(1000));
        await instance.beginVisit();
        expect(
          ((storage.value!['features'] as Map)['like'] as Map)['nextVisit'],
          target,
        );
      }
      expect(targets, {3, 4, 5});
    },
  );

  test(
    'failed presentation and ineligible contexts preserve the lesson',
    () async {
      final visit = await visits(3);
      expect(await prompt(visit, eligible: {}), isFalse);
      expect(await prompt(visit, display: false), isFalse);
      expect(await prompt(visit), isTrue);
    },
  );

  test('both lessons share seven days, including across restarts', () async {
    expect(await prompt(await visits(3)), isTrue);
    now = now.add(const Duration(days: 6, hours: 23));
    tracker = BoardFeatureTeachingTracker(
      store,
      random: FirstTeachingRandom(),
      now: () => now,
    );
    final visit = await visits(5);
    expect(await prompt(visit), isFalse);
    now = now.add(const Duration(hours: 1));
    expect(await prompt(visit), isTrue);
    expect(shown, [
      BoardTeachingFeature.like,
      BoardTeachingFeature.notationSwipe,
    ]);
  });

  test(
    'at most two exposures per feature, at least fourteen days apart',
    () async {
      const eligible = {BoardTeachingFeature.like};
      expect(await prompt(await visits(3), eligible: eligible), isTrue);
      final nextVisit = await visits(4);
      now = now.add(const Duration(days: 13));
      expect(await prompt(nextVisit, eligible: eligible), isFalse);
      now = now.add(const Duration(days: 1));
      expect(await prompt(nextVisit, eligible: eligible), isTrue);
      now = now.add(const Duration(days: 90));
      expect(await prompt(await visits(20), eligible: eligible), isFalse);
      expect(shown.length, 2);
    },
  );

  test('using a feature or opting out suppresses it permanently', () async {
    await tracker.markLearned(BoardTeachingFeature.like);
    await tracker.disable(BoardTeachingFeature.notationSwipe);
    final visit = await visits(8);
    expect(await prompt(visit), isFalse);
    tracker = BoardFeatureTeachingTracker(
      store,
      random: FirstTeachingRandom(),
      now: () => now,
    );
    now = now.add(const Duration(days: 90));
    expect(await prompt(await visits(8)), isFalse);
  });

  test('learning during a deferred check wins before presentation', () async {
    final visit = await visits(3);
    await Future.wait([
      tracker.markLearned(BoardTeachingFeature.like),
      prompt(visit, eligible: {BoardTeachingFeature.like}),
    ]);
    expect(shown, isEmpty);
  });

  test('concurrent boards can only show one lesson', () async {
    final visit = await visits(3);
    final results = await Future.wait([prompt(visit), prompt(visit)]);
    expect(results.where((value) => value).length, 1);
  });

  test(
    'old Swipe/Pinch teaching and like reminders use the same budget',
    () async {
      final visit = await visits(3);
      await tracker.recordOtherTeaching();
      expect(await prompt(visit), isFalse);
      expect(await tracker.tryShowLikeReminder(() => true), isFalse);
      now = now.add(const Duration(days: 7));
      final nextVisit = await visits(1);
      expect(await tracker.tryShowLikeReminder(() => true), isTrue);
      expect(await prompt(nextVisit), isFalse);
    },
  );

  test('legacy dates, opt-outs and exposure count are preserved', () async {
    store.value = {
      'lastShown': now.millisecondsSinceEpoch,
      'features': {
        'like': {'disabled': true},
        'notationSwipe': {'shown': 1, 'lastShown': now.millisecondsSinceEpoch},
      },
    };
    final visit = await visits(5);
    expect(await prompt(visit), isFalse);
    now = now.add(const Duration(days: 14));
    expect(await prompt(visit), isTrue);
    expect(shown, [BoardTeachingFeature.notationSwipe]);
    now = now.add(const Duration(days: 90));
    expect(await prompt(await visits(10)), isFalse);
  });

  test('storage failure is quiet and does not leave the queue stuck', () async {
    store.fail = true;
    expect(await tracker.beginVisit(), 0);
    expect(await prompt(3), isFalse);
    store.fail = false;
    expect(await prompt(await visits(3)), isTrue);
  });

  test('clock moving backwards cannot bypass a cooldown', () async {
    expect(await prompt(await visits(3)), isTrue);
    now = now.subtract(const Duration(days: 30));
    expect(await prompt(await visits(10)), isFalse);
  });

  test(
    'migrates the actual removed walkthrough keys without resetting opt-outs',
    () async {
      SharedPreferences.setMockInitialValues({
        'like_walkthrough_dont_show': true,
        'like_walkthrough_shown_date': now
            .subtract(const Duration(days: 9))
            .millisecondsSinceEpoch,
        'explorer_panel_walkthrough_shown_date': now
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch,
        'swipable_walkthrough_shown_date': now.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      final progress = AppDatabaseBoardFeatureTeachingStore.progressFromLegacy(
        prefs,
      );
      expect(progress['lastShown'], now.millisecondsSinceEpoch);
      final features = progress['features'] as Map;
      expect((features['like'] as Map)['disabled'], isTrue);
      expect((features['like'] as Map)['shown'], 1);
      expect((features['notationSwipe'] as Map)['shown'], 1);
      expect(
        (features['notationSwipe'] as Map)['lastShown'],
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      );
    },
  );
}
