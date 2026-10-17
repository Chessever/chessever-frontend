import 'dart:async';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/utils/live_stream_coachmark.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'event_video_test.dart' show fixtureVideos;

class HintStore implements LiveStreamCoachmarkStore {
  HintStore({this.seen = false, this.read});
  bool seen;
  int writes = 0;
  final Completer<bool>? read;
  @override
  Future<bool> hasSeen() async => read == null ? seen : await read!.future;
  @override
  Future<void> markSeen() async {
    writes++;
    seen = true;
  }
}

class PreviewEngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
}

EventVideoSession selectedSession({
  Future<void> Function(bool)? saveVisibility,
}) {
  final session = EventVideoSession(
    repository: null,
    saveVisibility: saveVisibility,
  );
  session.openGame(gameId: 'g1', tourId: 'tour', roundId: 'round');
  session.streams = fixtureVideos();
  session.select('english-main');
  return session;
}

// The real selector + camera widgets under their real session/layout scopes.
// No platform player, account, network or device connection is needed.
Widget selectedStreamHarness(
  EventVideoSession session,
  LiveStreamCoachmarkTracker restoreTracker, {
  bool reducedMotion = false,
  bool accessibleNavigation = false,
  bool active = true,
  Widget? board,
}) => ProviderScope(
  overrides: [
    engineSettingsProviderNew.overrideWith(PreviewEngineSettings.new),
    engineDepthStatusProvider.overrideWithValue(null),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reducedMotion,
        accessibleNavigation: accessibleNavigation,
      ),
      child: child!,
    ),
    home: EventVideoScope(
      session: session,
      player: null,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          ResponsiveHelper.init(context);
          return EventVideoLayoutScope(
            layout: EventVideoLayout.of(session),
            child: Scaffold(
              body: Column(
                children: [
                  if (board != null) board,
                  const EventVideoFlagSlot(),
                  const EventVideoSurface(),
                ],
              ),
              bottomNavigationBar: ChessBoardBottomNavBar(
                gameIndex: 0,
                isActivePage: active,
                onLeftMove: () {},
                onRightMove: () {},
                onFlip: () {},
                onVideoToggle: session.hasVideo ? session.toggle : null,
                videoVisible: session.showVideo,
                canMoveForward: true,
                canMoveBackward: true,
                showEngineAnalysis: false,
                showUnseenMoveBadge: false,
                liveStreamCoachmarkTracker: LiveStreamCoachmarkTracker(
                  HintStore(seen: true),
                ),
                restoreVideoCoachmarkTracker: restoreTracker,
              ),
            ),
          );
        },
      ),
    ),
  ),
);

void main() {
  final chip = find.byKey(const ValueKey('video_stream_english-main'));
  final camera = find.byKey(const ValueKey('board_video_toggle'));
  final hint = find.text('Show video here');
  double scale(WidgetTester tester) => tester
      .widget<ScaleTransition>(find.byKey(const ValueKey('video_camera_pulse')))
      .scale
      .value;

  test(
    'selected chip hides, persists visibility and camera restores exact ID',
    () async {
      final saved = <bool>[];
      final session = selectedSession(
        saveVisibility: (visible) async {
          saved.add(visible);
        },
      );
      addTearDown(session.dispose);
      session.reportMuted(true, session.playerRevision);
      session.reportPlayback(true, session.playerRevision);
      final id = session.selected!.identity;
      final language = session.rememberedLanguage;
      final country = session.savedCountry;
      session.activateStream('english-main');
      expect(session.showVideo, isFalse);
      expect(session.chipDismissals, 1);
      expect(session.playing, isFalse);
      expect(session.playRequested, isFalse);
      expect(session.expanded, isFalse);
      expect(session.selected!.identity, id);
      expect(session.muted, isTrue);
      expect(session.rememberedLanguage, language);
      expect(session.savedCountry, country);
      session.openGame(gameId: 'g2', tourId: 'tour', roundId: 'round-2');
      session.toggle();
      expect(session.selected!.identity, id);
      expect(session.showVideo, isTrue);
      expect(session.playRequested, isFalse);
      expect(session.chipDismissals, 1);
      await Future<void>.delayed(Duration.zero);
      expect(saved, [false, true]);
    },
  );

  test('different chip switches while retaining playback intent and mute', () {
    final session = selectedSession();
    addTearDown(session.dispose);
    session.reportPlayback(true, session.playerRevision);
    session.reportMuted(true, session.playerRevision);
    session.activateStream('english-second');
    expect(session.selected!.id, 'english-second');
    expect(session.showVideo, isTrue);
    expect(session.playRequested, isTrue);
    expect(session.muted, isTrue);
    expect(session.chipDismissals, 0);
  });

  test('a quick second tap on a just-switched chip does not hide', () {
    final session = selectedSession();
    addTearDown(session.dispose);
    session.activateStream('english-second');
    session.activateStream('english-second');
    expect(session.selected!.id, 'english-second');
    expect(session.showVideo, isTrue);
    expect(session.chipDismissals, 0);
  });

  test(
    'explicit select remains idempotent, invalid/disposed chip is harmless',
    () {
      final session = selectedSession();
      session.reportPlayback(true, session.playerRevision);
      final revision = session.playerRevision;
      session.select('english-main');
      session.activateStream('missing');
      expect(session.playerRevision, revision);
      expect(session.playing, isTrue);
      session.dispose();
      session.activateStream('english-main');
      expect(session.chipDismissals, 0);
    },
  );

  test('restore hint has a distinct local key from old hide hint', () {
    expect(
      AppDatabaseLiveStreamCoachmarkStore.restoreStorageKey,
      isNot(AppDatabaseLiveStreamCoachmarkStore.storageKey),
    );
  });

  testWidgets('actual selected chip hides and camera restores without repeat', (
    tester,
  ) async {
    final session = selectedSession();
    addTearDown(session.dispose);
    final store = HintStore();
    final tracker = LiveStreamCoachmarkTracker(store);
    await tester.pumpWidget(selectedStreamHarness(session, tracker));
    await tester.pump();
    expect(hint, findsNothing);
    await tester.tap(chip);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('event_video_surface')), findsNothing);
    expect(hint, findsOneWidget);
    expect(store.writes, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(scale(tester), closeTo(1.12, .001));
    await tester.pump(const Duration(milliseconds: 500));
    expect(scale(tester), 1);
    await tester.pump(const Duration(seconds: 5));
    expect(scale(tester), 1);
    await tester.tap(camera);
    await tester.pumpAndSettle();
    expect(session.selected!.id, 'english-main');
    expect(find.byKey(const ValueKey('event_video_surface')), findsOneWidget);
    expect(hint, findsNothing);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    expect(store.writes, 1);
    expect(scale(tester), 1);
    await tester.pumpWidget(const SizedBox());
    expect(await LiveStreamCoachmarkTracker(store).claim(), isFalse);
  });

  testWidgets(
    'different chip switches and camera-only hiding shows no new hint',
    (tester) async {
      final session = selectedSession();
      addTearDown(session.dispose);
      final store = HintStore();
      await tester.pumpWidget(
        selectedStreamHarness(session, LiveStreamCoachmarkTracker(store)),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('video_stream_english-second')),
      );
      await tester.pump();
      expect(session.selected!.id, 'english-second');
      expect(session.showVideo, isTrue);
      expect(hint, findsNothing);
      await tester.tap(camera);
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
      expect(store.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final accessibility in ['reduced motion', 'accessible navigation']) {
    testWidgets('$accessibility keeps static readable hint without pulse', (
      tester,
    ) async {
      final session = selectedSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        selectedStreamHarness(
          session,
          LiveStreamCoachmarkTracker(HintStore()),
          reducedMotion: accessibility == 'reduced motion',
          accessibleNavigation: accessibility == 'accessible navigation',
        ),
      );
      await tester.tap(chip);
      await tester.pump();
      await tester.pump();
      expect(hint, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(scale(tester), 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disposing during pulse removes overlay and ticker', (
    tester,
  ) async {
    final session = selectedSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      selectedStreamHarness(session, LiveStreamCoachmarkTracker(HintStore())),
    );
    await tester.tap(chip);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(scale(tester), greaterThan(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(hint, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing while storage loads releases unseen reservation', (
    tester,
  ) async {
    final session = selectedSession();
    addTearDown(session.dispose);
    final read = Completer<bool>();
    final store = HintStore(read: read);
    final tracker = LiveStreamCoachmarkTracker(store);
    await tester.pumpWidget(selectedStreamHarness(session, tracker));
    await tester.tap(chip);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    read.complete(false);
    await tester.pump();
    expect(store.writes, 0);
    expect(await tracker.claim(), isTrue);
    tracker.release();
    expect(tester.takeException(), isNull);
  });

  testWidgets('restore before storage returns never shows a stale hint', (
    tester,
  ) async {
    final session = selectedSession();
    addTearDown(session.dispose);
    final read = Completer<bool>();
    final store = HintStore(read: read);
    final tracker = LiveStreamCoachmarkTracker(store);
    await tester.pumpWidget(selectedStreamHarness(session, tracker));
    await tester.tap(chip);
    await tester.pump();
    await tester.tap(camera);
    await tester.pump();
    read.complete(false);
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    expect(store.writes, 0);
    expect(session.showVideo, isTrue);
    expect(await tracker.claim(), isTrue);
    tracker.release();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing hint stops pulse without restoring or repeating', (
    tester,
  ) async {
    final session = selectedSession();
    addTearDown(session.dispose);
    final store = HintStore();
    final tracker = LiveStreamCoachmarkTracker(store);
    await tester.pumpWidget(selectedStreamHarness(session, tracker));
    await tester.tap(chip);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('close_live_stream_coachmark')));
    await tester.pumpAndSettle();
    expect(session.showVideo, isFalse);
    expect(hint, findsNothing);
    expect(scale(tester), 1);
    await tester.tap(camera);
    await tester.pump();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    expect(store.writes, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('enabling reduced motion during pulse cancels it', (
    tester,
  ) async {
    final session = selectedSession();
    addTearDown(session.dispose);
    final tracker = LiveStreamCoachmarkTracker(HintStore());
    await tester.pumpWidget(selectedStreamHarness(session, tracker));
    await tester.tap(chip);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(scale(tester), greaterThan(1));
    await tester.pumpWidget(
      selectedStreamHarness(session, tracker, reducedMotion: true),
    );
    await tester.pump();
    expect(scale(tester), 1);
    expect(hint, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inactive adjacent page does not claim dismissal hint', (
    tester,
  ) async {
    final session = selectedSession();
    addTearDown(session.dispose);
    final store = HintStore();
    await tester.pumpWidget(
      selectedStreamHarness(
        session,
        LiveStreamCoachmarkTracker(store),
        active: false,
      ),
    );
    session.activateStream('english-main');
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    expect(store.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
