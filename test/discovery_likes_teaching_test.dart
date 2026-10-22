import 'package:chessever2/screens/chessboard/utils/board_feature_teaching_tracker.dart';
import 'package:chessever2/screens/chessboard/widgets/board_feature_teaching_host.dart';
import 'package:chessever2/screens/chessboard/widgets/discovery_likes_teaching.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class Store implements BoardFeatureTeachingStore {
  Map<String, Object?>? value;
  @override
  Future<Map<String, Object?>?> read() async => value;
  @override
  Future<void> write(Map<String, Object?> value) async => this.value = value;
}

void main() {
  late Store store;
  late BoardFeatureTeachingTracker tracker;
  late bool allowed;
  late int boardTaps;
  setUp(() {
    store = Store();
    tracker = BoardFeatureTeachingTracker(store);
    allowed = true;
    boardTaps = 0;
  });
  Widget app({
    bool likes = true,
    bool reduced = false,
    bool accessible = false,
    GlobalKey<NavigatorState>? navigator,
    double textScale = 1,
  }) {
    Widget host = BoardFeatureTeachingHost(
      isEligibleVisit: () => true,
      eligibleFeatures: () => {},
      canShowContextual: () => allowed,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: TextButton(
            onPressed: () => boardTaps++,
            child: const Text('Board control'),
          ),
        ),
      ),
    );
    if (likes) host = DiscoveryLikesTeachingScope(child: host);
    return ProviderScope(
      overrides: [
        boardFeatureTeachingTrackerProvider.overrideWithValue(tracker),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            accessibleNavigation: accessible,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: host,
      ),
    );
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets(
    'first opening reuses finger-heart demo, is dismissible and nonblocking',
    (tester) async {
      await tester.pumpWidget(app());
      await show(tester);
      expect(find.byType(DoubleTapHeartTeachingDemo), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DiscoveryLikesTeaching),
          matching: find.byType(ModalBarrier),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Board control'));
      expect(boardTaps, 1);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.byType(DoubleTapHeartTeachingDemo), findsNothing);
      expect(store.value!['discoveryLikesIntroduced'], true);
      await tester.pumpWidget(const SizedBox());
      tracker = BoardFeatureTeachingTracker(store);
      await tester.pumpWidget(app());
      await show(tester);
      expect(find.byType(DoubleTapHeartTeachingDemo), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('other entry points do not consume or show the lesson', (
    tester,
  ) async {
    await tester.pumpWidget(app(likes: false));
    await show(tester);
    expect(find.byType(DoubleTapHeartTeachingDemo), findsNothing);
    expect(store.value?['discoveryLikesIntroduced'], isNot(true));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'defers behind another tutorial and auto-dismisses after eight seconds',
    (tester) async {
      allowed = false;
      await tester.pumpWidget(app());
      await show(tester);
      expect(find.byType(DoubleTapHeartTeachingDemo), findsNothing);
      allowed = true;
      await show(tester);
      expect(find.byType(DoubleTapHeartTeachingDemo), findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
      expect(find.byType(DoubleTapHeartTeachingDemo), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'route cover closes only the lesson, never pops the covering route',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(navigator: nav));
      await show(tester);
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other route')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Other route'), findsOneWidget);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(DoubleTapHeartTeachingDemo), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('background dismisses and does not replay on resume', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await show(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byType(DoubleTapHeartTeachingDemo), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await show(tester);
    expect(find.byType(DoubleTapHeartTeachingDemo), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'reduced motion is static; accessible navigation retains dismissal',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(reduced: true, accessible: true, textScale: 1.6),
      );
      await show(tester);
      final finder = find.descendant(
        of: find.byType(DoubleTapHeartTeachingDemo),
        matching: find.byType(Transform),
      );
      final before = tester
          .widgetList<Transform>(finder)
          .map((w) => w.transform.toString())
          .toList();
      await tester.pump(const Duration(seconds: 12));
      expect(
        tester
            .widgetList<Transform>(finder)
            .map((w) => w.transform.toString())
            .toList(),
        before,
      );
      expect(find.byTooltip('Dismiss').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('finger actually presses twice before the heart appears', (
    tester,
  ) async {
    await tester.pumpWidget(app(accessible: true));
    await show(tester);
    final demo = find.byType(DoubleTapHeartTeachingDemo);
    final transforms = find.descendant(
      of: demo,
      matching: find.byType(Transform),
    );
    double handScale() =>
        tester.widget<Transform>(transforms.last).transform.entry(0, 0);
    await tester.pump(const Duration(milliseconds: 288));
    expect(handScale(), closeTo(0.82, 0.01));
    await tester.pump(const Duration(milliseconds: 192));
    expect(handScale(), closeTo(1, 0.01));
    await tester.pump(const Duration(milliseconds: 240));
    expect(handScale(), closeTo(0.82, 0.01));
    await tester.pump(const Duration(milliseconds: 480));
    final opacity = tester.widget<Opacity>(
      find.descendant(of: demo, matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });
}
