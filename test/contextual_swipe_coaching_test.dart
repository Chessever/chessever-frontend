import 'dart:async';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/chessboard/contextual_swipe_coaching.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late ContextualSwipeCoaching coaching;
  late Route<void> caller;
  late Route<void> board;
  final day = DateTime(2026, 10, 21, 23, 59);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = (await SharedPreferencesService.instance.initialize())!;
  });
  setUp(() async {
    await prefs.clear();
    coaching = ContextualSwipeCoaching();
    caller = MaterialPageRoute<void>(builder: (_) => const SizedBox());
  });

  SwipeCoachingVisit open(String game, {Object list = 'list'}) {
    board = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    final visit = coaching.begin(
      board: board,
      caller: caller,
      listIdentity: (caller, list),
      gameId: game,
    );
    coaching.didPush(board, caller);
    return visit;
  }

  void back() => coaching.didPop(board, caller);
  SwipeCoachingVisit pattern() {
    open('one');
    back();
    open('two');
    back();
    return open('three');
  }

  Future<bool> claim(SwipeCoachingVisit visit, {DateTime? now}) =>
      coaching.claim(visit, ready: () => true, now: now ?? day);

  test(
    'first and second opens never coach; third distinct Back cycle does',
    () async {
      final first = open('one');
      expect(await claim(first), isFalse);
      back();
      final second = open('two');
      expect(await claim(second), isFalse);
      back();
      expect(await claim(open('three')), isTrue);
    },
  );
  test('repeated game IDs do not advance the pattern', () async {
    open('one');
    back();
    open('one');
    back();
    expect(await claim(open('two')), isFalse);
  });
  test(
    'opening without Back resets instead of phantom-counting preloads',
    () async {
      open('one');
      open('two');
      open('three');
      expect(await claim(open('four')), isFalse);
    },
  );
  test('different stable list identity resets', () async {
    open('one');
    back();
    open('two');
    back();
    expect(await claim(open('three', list: 'different')), isFalse);
  });
  test('equivalent recreated list key retains sequence', () async {
    open('one', list: ('tour', 'round'));
    back();
    open('two', list: ('tour', 'round'));
    back();
    expect(await claim(open('three', list: ('tour', 'round'))), isTrue);
  });
  test('unrelated navigation and return cancels prior list sequence', () async {
    open('one');
    back();
    open('two');
    back();
    final unrelated = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    coaching.didPush(unrelated, caller);
    coaching.didPop(unrelated, caller);
    expect(await claim(open('three')), isFalse);
  });
  test('route replacement and removal cancel visits', () async {
    var visit = pattern();
    coaching.didReplace(newRoute: caller, oldRoute: board);
    expect(await claim(visit), isFalse);
    visit = pattern();
    coaching.didRemove(board, caller);
    expect(await claim(visit), isFalse);
  });
  test('pop/disposal during asynchronous claim prevents display', () async {
    final visit = pattern();
    final pending = claim(visit);
    back();
    expect(await pending, isFalse);
  });
  test(
    'readiness prevents reservation until board and swipe neighbors ready',
    () async {
      final visit = pattern();
      expect(
        await coaching.claim(visit, ready: () => false, now: day),
        isFalse,
      );
      expect(prefs.getString(swipeCoachingDayKey), isNull);
      expect(await claim(visit), isTrue);
    },
  );
  test('rebuild checks and concurrent claims show once', () async {
    final visit = pattern();
    expect(await Future.wait([claim(visit), claim(visit)]), [true, false]);
    expect(await claim(visit), isFalse);
  });
  test(
    'daily cap survives new coordinator and requires new pattern next day',
    () async {
      expect(await claim(pattern()), isTrue);
      coaching = ContextualSwipeCoaching();
      expect(
        await claim(open('one'), now: day.add(const Duration(minutes: 2))),
        isFalse,
      );
      back();
      open('two');
      back();
      expect(await claim(open('three')), isFalse);
      back();
      expect(
        await claim(pattern(), now: day.add(const Duration(minutes: 2))),
        isTrue,
      );
    },
  );
  test(
    'UTC instants cap by device-local date rather than elapsed 24 hours',
    () async {
      final instant = DateTime.utc(2026, 10, 22, 1);
      final local = instant.toLocal();
      expect(await claim(pattern(), now: instant), isTrue);
      expect(
        prefs.getString(swipeCoachingDayKey),
        '${local.year}-${local.month}-${local.day}',
      );
      coaching = ContextualSwipeCoaching();
      expect(
        await claim(
          pattern(),
          now: DateTime(local.year, local.month, local.day, 23, 59),
        ),
        isFalse,
      );
      back();
      expect(
        await claim(
          pattern(),
          now: DateTime(local.year, local.month, local.day + 1),
        ),
        isTrue,
      );
    },
  );

  test('legacy seen-once does not suppress new behavior', () async {
    await prefs.setInt(
      'swipable_walkthrough_shown_date',
      day.millisecondsSinceEpoch,
    );
    expect(await claim(pattern()), isTrue);
  });
  for (final key in [swipeCoachingDisabledKey, swipeCoachingLearnedKey]) {
    test('preserves persistent $key', () async {
      await prefs.setBool(key, true);
      expect(await claim(pattern()), isFalse);
    });
  }
  for (final learned in [false, true]) {
    test(
      'device-local ${learned ? 'learned' : 'opt-out'} survives restart',
      () async {
        await coaching.disable(learned: learned);
        coaching = ContextualSwipeCoaching();
        expect(
          await claim(pattern(), now: day.add(const Duration(days: 4))),
          isFalse,
        );
        expect(
          prefs.getBool(
            learned ? swipeCoachingLearnedKey : swipeCoachingDisabledKey,
          ),
          isTrue,
        );
      },
    );
  }

  testWidgets('real Navigator Back alone advances the same-list sequence', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [coaching],
        home: const Text('list'),
      ),
    );
    caller = ModalRoute.of(tester.element(find.text('list')))!;
    for (final id in ['one', 'two', 'three']) {
      final visit = open(id);
      unawaited(navigator.currentState!.push(board));
      await tester.pumpAndSettle();
      expect(await claim(visit), id == 'three');
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('only successful manual game drag learns, not jumps or bounce', (
    tester,
  ) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    final gesture = SwipeLearningGesture();
    var page = 0;
    var learned = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (gesture.observe(n, 'game$page')) learned++;
            return false;
          },
          child: PageView(
            controller: controller,
            onPageChanged: (value) => page = value,
            children: const [Text('one'), Text('two'), Text('three')],
          ),
        ),
      ),
    );
    controller.jumpToPage(1);
    await tester.pumpAndSettle();
    unawaited(
      controller.animateToPage(
        0,
        duration: const Duration(milliseconds: 50),
        curve: Curves.linear,
      ),
    );
    await tester.pumpAndSettle();
    expect(learned, 0);
    // Tutorial-style fractional jump forward/back does not supply dragDetails.
    controller.position.jumpTo(80);
    controller.jumpToPage(0);
    await tester.pumpAndSettle();
    expect(learned, 0);
    await tester.drag(find.byType(PageView), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(learned, 0);
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(page, 1);
    expect(learned, 1);
  });
}
