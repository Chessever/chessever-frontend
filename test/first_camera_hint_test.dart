import 'dart:async';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/utils/live_stream_coachmark.dart';
import 'package:chessever2/screens/chessboard/utils/stream_scroll_coaching.dart';
import 'package:chessever2/screens/chessboard/widgets/board_feature_teaching_host.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/stream_scroll_coaching_host.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class Settings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
}

class Store implements LiveStreamCoachmarkStore {
  Store({this.seen = false, this.pending});
  bool seen;
  Completer<bool>? pending;
  @override
  Future<bool> hasSeen() async => pending == null ? seen : pending!.future;
  @override
  Future<void> markSeen() async => seen = true;
}

class Harness {
  Harness({Store? store}) : store = store ?? Store() {
    tracker = LiveStreamCoachmarkTracker(this.store);
  }
  final Store store;
  late LiveStreamCoachmarkTracker tracker;
  final scroll = StreamScrollCoachingController(Store());
  final navigator = GlobalKey<NavigatorState>();
  bool allowed = true, active = true, visible = true, hasVideo = true;
  bool reduced = false;
  int toggles = 0;
  Widget app() => ProviderScope(
    overrides: [
      engineSettingsProviderNew.overrideWith(Settings.new),
      engineDepthStatusProvider.overrideWithValue(null),
      streamScrollCoachingProvider('phone-game').overrideWith((ref) => scroll),
    ],
    child: MaterialApp(
      navigatorKey: navigator,
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: BoardFeatureTeachingHost(
              isEligibleVisit: () => false,
              eligibleFeatures: () => {},
              canShowContextual: () => allowed,
              child: Builder(
                builder: (context) => Scaffold(
                  body: StreamScrollCoachingHost(
                    gameId: 'phone-game',
                    active: active && visible && hasVideo,
                    canShow: () =>
                        BoardFeatureTeachingHost.allowsContextual(context),
                    child: ListView(children: const [SizedBox(height: 3000)]),
                  ),
                  bottomNavigationBar: ChessBoardBottomNavBar(
                    gameIndex: 0,
                    coachingGameId: 'phone-game',
                    isActivePage: active,
                    videoVisible: visible,
                    onVideoToggle: hasVideo ? () => toggles++ : null,
                    onLeftMove: () {},
                    onRightMove: () {},
                    onFlip: () {},
                    canMoveForward: true,
                    canMoveBackward: true,
                    showEngineAnalysis: false,
                    showUnseenMoveBadge: false,
                    liveStreamCoachmarkTracker: tracker,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

const hint = 'Tap the camera to hide the stream.';
final camera = find.byKey(const ValueKey('board_video_toggle'));
Animation<double> pulse(WidgetTester tester) => tester
    .widget<ScaleTransition>(find.byKey(const ValueKey('video_camera_pulse')))
    .scale;

void main() {
  testWidgets('no-stream page teardown never creates a late ticker', (tester) async {
    final h = Harness()..hasVideo = false;
    await tester.pumpWidget(h.app());
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    expect(h.store.seen, isFalse);
  });

  test(
    'first-ever and restore retain their distinct existing persistence keys',
    () {
      expect(
        AppDatabaseLiveStreamCoachmarkStore.storageKey,
        'live_stream_toggle_coachmark_v1',
      );
      expect(
        AppDatabaseLiveStreamCoachmarkStore.restoreStorageKey,
        'live_stream_restore_coachmark_v1',
      );
    },
  );

  testWidgets('real phone ID shows above tappable camera; pulse ends at 2.5s', (
    tester,
  ) async {
    final h = Harness();
    await tester.pumpWidget(h.app());
    await tester.pump();
    expect(find.text(hint), findsOneWidget);
    expect(
      tester.getRect(find.text(hint)).bottom,
      lessThan(tester.getRect(camera).top),
    );
    expect(camera.hitTestable(), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(pulse(tester).value, greaterThan(1));
    await tester.pump(const Duration(milliseconds: 2249));
    expect(pulse(tester).status, AnimationStatus.forward);
    await tester.pump(const Duration(milliseconds: 1));
    expect(pulse(tester).value, 1);
    expect(pulse(tester).status, AnimationStatus.dismissed);
    expect(find.text(hint), findsOneWidget);
    await tester.tap(camera);
    await tester.pump();
    expect(h.toggles, 1);
    expect(find.text(hint), findsNothing);
    await tester.pumpWidget(const SizedBox());
    // New tracker + tree simulates restart; no reset of the stored seen key.
    final restarted = Harness(store: h.store);
    await tester.pumpWidget(restarted.app());
    await tester.pump();
    expect(find.text(hint), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reduced motion keeps a static highlight and close suppresses repeat',
    (tester) async {
      final h = Harness()..reduced = true;
      await tester.pumpWidget(h.app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(hint), findsOneWidget);
      expect(pulse(tester).value, 1);
      expect(pulse(tester).status, AnimationStatus.dismissed);
      await tester.tap(
        find.byKey(const ValueKey('close_live_stream_coachmark')),
      );
      await tester.pump();
      h.visible = false;
      await tester.pumpWidget(h.app());
      h.visible = true;
      await tester.pumpWidget(h.app());
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(hint), findsNothing);
      expect(h.store.seen, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'tutorial blocker delays without consuming; scroll lesson never overlaps',
    (tester) async {
      final h = Harness()..allowed = false;
      await tester.pumpWidget(h.app());
      await tester.pump();
      expect(find.text(hint), findsNothing);
      expect(h.store.seen, isFalse);
      h.allowed = true;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump();
      expect(find.text(hint), findsOneWidget);
      // Real outer scroller: two downward gestures while camera copy is visible.
      for (var i = 0; i < 2; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -100));
        await tester.pump();
      }
      expect(find.text('OK'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('close_live_stream_coachmark')),
      );
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -100));
        await tester.pump();
      }
      await tester.pump();
      expect(find.text('OK'), findsOneWidget);
      expect(find.text(hint), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(h.scroll.pulsing, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(h.scroll.pulsing, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'first hint waits for scroll lesson and its acknowledgement pulse',
    (tester) async {
      final h = Harness()..allowed = false;
      await tester.pumpWidget(h.app());
      await tester.pump();
      h.scroll.showing = true;
      h.scroll.pulsing = true;
      h.allowed = true;
      await tester.pumpWidget(h.app());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(hint), findsNothing);
      h.scroll.acknowledge();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1999));
      expect(find.text(hint), findsNothing);
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pump();
      expect(find.text(hint), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing/hidden stream and inactive page do not consume first hint',
    (tester) async {
      final h = Harness()..hasVideo = false;
      await tester.pumpWidget(h.app());
      await tester.pump();
      expect(h.store.seen, isFalse);
      h.hasVideo = true;
      h.visible = false;
      await tester.pumpWidget(h.app());
      await tester.pump();
      expect(h.store.seen, isFalse);
      h.visible = true;
      h.active = false;
      await tester.pumpWidget(h.app());
      await tester.pump();
      expect(h.store.seen, isFalse);
      h.active = true;
      await tester.pumpWidget(h.app());
      await tester.pump();
      expect(find.text(hint), findsOneWidget);
      h.active = false;
      await tester.pumpWidget(h.app());
      await tester.pump();
      expect(find.text(hint), findsNothing);
      expect(pulse(tester).value, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'background and covering route remove hint/pulse without stale overlays',
    (tester) async {
      final h = Harness();
      await tester.pumpWidget(h.app());
      await tester.pump();
      expect(find.text(hint), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text(hint), findsNothing);
      expect(pulse(tester).value, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text(hint), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final fresh = Harness();
      await tester.pumpWidget(fresh.app());
      await tester.pump();
      fresh.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other route')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(hint), findsNothing);
      fresh.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'async claim rechecks tutorial blocker and releases on disposal',
    (tester) async {
      final pending = Completer<bool>();
      final h = Harness(store: Store(pending: pending));
      await tester.pumpWidget(h.app());
      h.allowed = false;
      pending.complete(false);
      await tester.pump();
      expect(find.text(hint), findsNothing);
      expect(h.store.seen, isFalse);
      h.allowed = true;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump();
      expect(find.text(hint), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final delayed = Completer<bool>();
      final gone = Harness(store: Store(pending: delayed));
      await tester.pumpWidget(gone.app());
      await tester.pumpWidget(const SizedBox());
      delayed.complete(false);
      await tester.pump();
      expect(gone.store.seen, isFalse);
      expect(await gone.tracker.claim(), isTrue);
      gone.tracker.release();
      expect(tester.takeException(), isNull);
    },
  );
}
