import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/utils/board_feature_teaching_tracker.dart';
import 'package:chessever2/screens/chessboard/widgets/board_feature_teaching_host.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'support/contrast_audit.dart';

class _Store implements BoardFeatureTeachingStore {
  _Store({int visits = 2}) : value = {'visits': visits};
  Map<String, Object?> value;
  @override
  Future<Map<String, Object?>?> read() async => value;
  @override
  Future<void> write(Map<String, Object?> value) async => this.value = value;
}

void main() {
  for (final light in [false, true]) {
    for (final feature in BoardTeachingFeature.values) {
      testWidgets(
        '$feature: readable controls in ${light ? 'light' : 'dark'} theme, narrow phone and large text',
        (tester) async {
          tester.view.physicalSize = const Size(320, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var dismissed = 0;
          var disabled = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(1.6),
                      disableAnimations: true,
                    ),
                    child: BoardFeatureTeachingDialog(
                      feature: feature,
                      onDismiss: () => dismissed++,
                      onDontShowAgain: () => disabled++,
                    ),
                  );
                },
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(
            auditTextContrast(
              tester,
              fallbackGround: light
                  ? const Color(0xFFEEF6F5)
                  : const Color(0xFF111111),
            ),
            isEmpty,
          );
          expect(find.text('Got it').hitTestable(), findsOneWidget);
          expect(find.text("Don't show again").hitTestable(), findsOneWidget);
          for (final button in find.byType(TextButton).evaluate()) {
            expect(
              tester.getSize(find.byWidget(button.widget)).height,
              greaterThanOrEqualTo(48),
            );
          }
          await tester.tap(find.text('Got it'));
          await tester.tap(find.text("Don't show again"));
          expect(dismissed, 1);
          expect(disabled, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  late _Store store;
  late BoardFeatureTeachingTracker tracker;
  late Duration elapsed;
  late bool eligible;
  setUp(() {
    store = _Store();
    // Both persisted targets are due on this visit, independent of randomness.
    store.value['features'] = {
      'like': {'nextVisit': 3},
      'notationSwipe': {'nextVisit': 3},
    };
    tracker = BoardFeatureTeachingTracker(store);
    elapsed = Duration.zero;
    eligible = true;
  });

  Widget host({GlobalKey<NavigatorState>? navigatorKey}) => ProviderScope(
    overrides: [boardFeatureTeachingTrackerProvider.overrideWithValue(tracker)],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return BoardFeatureTeachingHost(
            elapsed: () => elapsed,
            isEligibleVisit: () => true,
            eligibleFeatures: () =>
                eligible ? BoardTeachingFeature.values.toSet() : {},
            child: Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {},
                  child: const Text('Next move'),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Future<void> engage(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next move'));
    }
    elapsed = const Duration(seconds: 30);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets(
    'nothing on entry or without engagement; one lesson after an idle pause',
    (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();
      expect(find.byType(BoardFeatureTeachingDialog), findsNothing);
      elapsed = const Duration(seconds: 30);
      await tester.pump(const Duration(seconds: 30));
      expect(find.byType(BoardFeatureTeachingDialog), findsNothing);
      elapsed = Duration.zero;
      await engage(tester);
      expect(find.byType(BoardFeatureTeachingDialog), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pump(const Duration(milliseconds: 300));
      elapsed = const Duration(minutes: 2);
      await tester.pump(const Duration(minutes: 2));
      expect(find.byType(BoardFeatureTeachingDialog), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets('first board visit stays quiet even after engagement', (
    tester,
  ) async {
    store.value['visits'] = 0;
    await tester.pumpWidget(host());
    await engage(tester);
    expect(find.byType(BoardFeatureTeachingDialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('ineligible moments defer instead of consuming the lesson', (
    tester,
  ) async {
    eligible = false;
    await tester.pumpWidget(host());
    await engage(tester);
    expect(find.byType(BoardFeatureTeachingDialog), findsNothing);
    eligible = true;
    elapsed += const Duration(seconds: 5);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BoardFeatureTeachingDialog), findsOneWidget);
    await tester.tap(find.text("Don't show again"));
    await tester.pump(const Duration(milliseconds: 300));
    final records = (store.value['features'] as Map).values.whereType<Map>();
    expect(records.where((value) => value['disabled'] == true).length, 1);
    await unmount(tester);
  });

  testWidgets('a held pointer and ongoing interaction delay teaching', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next move'));
    }
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Next move')),
    );
    elapsed = const Duration(seconds: 30);
    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(BoardFeatureTeachingDialog), findsNothing);
    await gesture.up();
    elapsed += const Duration(seconds: 4);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(BoardFeatureTeachingDialog), findsNothing);
    elapsed += const Duration(seconds: 5);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(BoardFeatureTeachingDialog), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'another route blocks teaching; backgrounding closes an open lesson',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(host(navigatorKey: navigator));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next move'));
      }
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other screen')),
        ),
      );
      elapsed = const Duration(seconds: 30);
      await tester.pump(const Duration(seconds: 30));
      expect(find.byType(BoardFeatureTeachingDialog), findsNothing);
      navigator.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 300));
      elapsed += const Duration(seconds: 5);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BoardFeatureTeachingDialog), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(BoardFeatureTeachingDialog), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await unmount(tester);
    },
  );

  testWidgets(
    'lessons expire and an open lesson is removed on route disposal',
    (tester) async {
      await tester.pumpWidget(host());
      await engage(tester);
      expect(find.byType(BoardFeatureTeachingDialog), findsOneWidget);
      elapsed += const Duration(seconds: 15);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BoardFeatureTeachingDialog), findsNothing);
      await unmount(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notation teaching stops after a real swipe, not a book-button toggle',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          boardFeatureTeachingTrackerProvider.overrideWithValue(tracker),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: boardAnalysisSwipePanelsForTesting(gameId: 'game'),
          ),
        ),
      );
      await tester.pump();
      container
          .read(boardExplorerToggleRequestProvider('game').notifier)
          .state++;
      await tester.pumpAndSettle();
      expect(store.value['features'], isNot(contains('learned')));
      expect(
        ((store.value['features'] as Map)['notationSwipe'] as Map)['learned'],
        isNot(true),
      );
      await tester.drag(find.text('Explorer fixture'), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(
        ((store.value['features'] as Map)['notationSwipe'] as Map)['learned'],
        isTrue,
      );
      await unmount(tester);
    },
  );

  testWidgets(
    'loading-to-content reparenting keeps one visit and engagement clock',
    (tester) async {
      final teachingKey = GlobalKey();
      var nested = false;
      Widget tree() {
        final teaching = BoardFeatureTeachingHost(
          key: teachingKey,
          elapsed: () => elapsed,
          isEligibleVisit: () => true,
          eligibleFeatures: () => BoardTeachingFeature.values.toSet(),
          child: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {},
                child: const Text('Next move'),
              ),
            ),
          ),
        );
        return ProviderScope(
          overrides: [
            boardFeatureTeachingTrackerProvider.overrideWithValue(tracker),
          ],
          child: MaterialApp(
            home: nested
                ? Padding(padding: EdgeInsets.zero, child: teaching)
                : teaching,
          ),
        );
      }

      await tester.pumpWidget(tree());
      await tester.pump();
      expect(store.value['visits'], 3);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next move'));
      }
      nested = true;
      await tester.pumpWidget(tree());
      await tester.pump();
      expect(store.value['visits'], 3);
      elapsed = const Duration(seconds: 30);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BoardFeatureTeachingDialog), findsOneWidget);
      await unmount(tester);
    },
  );
}
