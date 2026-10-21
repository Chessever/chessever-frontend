import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_event_view.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart'
    show liveBroadcastIdsProvider;
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/past_event_access.dart';
import 'package:chessever2/widgets/paywall/pgn_copy_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _now = DateTime.utc(2026, 10, 14, 12);

GroupBroadcast _event({DateTime? start, DateTime? end, String id = 'event'}) =>
    GroupBroadcast(
      id: id,
      createdAt: DateTime.utc(2026),
      name: 'Event',
      search: const [],
      dateStart: start,
      dateEnd: end,
    );

/// Pumps a button that runs [gate] and records what it resolved to. A gate
/// that asked for Premium would push the chooser instead of resolving.
Future<List<bool>> _runGate(
  WidgetTester tester,
  Future<bool> Function(BuildContext context) gate, {
  required bool premium,
  GroupBroadcast? selected,
  List<String> liveIds = const [],
  List<Override> overrides = const [],
  void Function(WidgetRef)? watch,
}) async {
  final results = <bool>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        premiumAccessProvider.overrideWithValue(premium),
        currentEventMembershipProvider.overrideWith((_, _) async => false),
        liveBroadcastIdsProvider.overrideWith((_) => liveIds),
        selectedBroadcastModelProvider.overrideWith((_) => selected),
        ...overrides,
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            watch?.call(ref);
            return TextButton(
              onPressed: () async => results.add(await gate(context)),
              child: const Text('Go'),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Go'));
  await tester.pumpAndSettle();
  return results;
}

/// A free viewer's gate pushes the Premium prompt (for a guest, the sign-in
/// step in front of checkout). Dismissing it must resolve the gate to false.
Future<void> _expectPromptThenDeny(
  WidgetTester tester,
  Future<bool> Function(BuildContext context) gate, {
  GroupBroadcast? selected,
  List<String> liveIds = const [],
  List<Override> overrides = const [],
  void Function(WidgetRef)? watch,
}) async {
  final results = <bool>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        premiumAccessProvider.overrideWithValue(false),
        currentEventMembershipProvider.overrideWith((_, _) async => false),
        liveBroadcastIdsProvider.overrideWith((_) => liveIds),
        selectedBroadcastModelProvider.overrideWith((_) => selected),
        ...overrides,
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            watch?.call(ref);
            ResponsiveHelper.init(context);
            return TextButton(
              onPressed: () async => results.add(await gate(context)),
              child: const Text('Go'),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Go'));
  await _settle(tester);
  expect(find.text('Sign in to get Premium'), findsOneWidget);
  expect(results, isEmpty);
  Navigator.of(tester.element(find.text('Sign in to get Premium'))).pop();
  await _settle(tester);
  expect(results, [false]);
}

Future<void> _settle(WidgetTester tester) async {
  for (var n = 0; n < 6; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 160));
  }
}

TourDetailViewModel _detail(List<DateTime> dates) => TourDetailViewModel(
  aboutTourModel: AboutTourModel.empty(),
  liveTourIds: const [],
  tours: [
    TourModel(
      tour: Tour.virtual(
        id: 'tour',
        name: 'Event',
        slug: 'event',
        dates: dates,
        players: const [],
      ),
      roundStatus: RoundStatus.completed,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture-publishable-key',
    );
  });

  group('isPastEventWindow', () {
    test('Current keeps the whole final day before becoming past', () {
      final end = DateTime.utc(2026, 10, 14);
      expect(isPastEventWindow(end: end, now: _now), isFalse);
      expect(
        isPastEventWindow(end: end, now: end.add(const Duration(days: 1))),
        isTrue,
      );
    });
    test('an event whose end has passed is past', () {
      expect(
        isPastEventWindow(
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 10),
          now: _now,
        ),
        isTrue,
      );
    });

    test('an event still running is not past', () {
      expect(
        isPastEventWindow(
          start: DateTime.utc(2026, 10, 10),
          end: DateTime.utc(2026, 10, 20),
          now: _now,
        ),
        isFalse,
      );
    });

    test('with no end, a start over a week ago is past', () {
      expect(
        isPastEventWindow(start: DateTime.utc(2026, 10, 1), now: _now),
        isTrue,
      );
      expect(
        isPastEventWindow(start: DateTime.utc(2026, 10, 12), now: _now),
        isFalse,
      );
    });

    test('an undated event is not called past', () {
      expect(isPastEventWindow(now: _now), isFalse);
    });
  });

  group('isPastEvent', () {
    test('a live event is never past, whatever its dates', () {
      final event = _event(
        start: DateTime.utc(2026, 10, 1),
        end: DateTime.utc(2026, 10, 10),
      );
      expect(isPastEvent(event, now: _now), isTrue);
      expect(isPastEvent(event, liveIds: ['event'], now: _now), isFalse);
    });
  });

  group('ensurePastEventAccess', () {
    testWidgets('Current SQL membership overrides even a Past category', (
      tester,
    ) async {
      final results = await _runGate(
        tester,
        (context) => ensurePastEventAccess(
          context,
          broadcast: _event(end: DateTime.utc(2000)),
          past: true,
        ),
        premium: false,
        overrides: [
          currentEventMembershipProvider(
            'event',
          ).overrideWith((_) async => true),
        ],
      );
      expect(results, [true]);
    });

    testWidgets('canonical live IDs bypass the prompt without Events cache', (
      tester,
    ) async {
      final results = await _runGate(
        tester,
        (context) => ensurePastEventAccess(
          context,
          broadcast: _event(end: DateTime.utc(2026, 1, 1)),
        ),
        premium: false,
        overrides: [
          liveGroupBroadcastIdsProvider.overrideWith(
            (_) => Stream.value(['event']),
          ),
        ],
        watch: (ref) => ref.watch(liveGroupBroadcastIdsProvider),
      );
      expect(results, [true]);
    });
    testWidgets('a current event opens without asking', (tester) async {
      final results = await _runGate(
        tester,
        (context) => ensurePastEventAccess(
          context,
          broadcast: _event(
            start: DateTime.now().subtract(const Duration(days: 1)),
            end: DateTime.now().add(const Duration(days: 3)),
          ),
        ),
        premium: false,
      );
      expect(results, [true]);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a live event past its end date opens without asking', (
      tester,
    ) async {
      final results = await _runGate(
        tester,
        (context) => ensurePastEventAccess(
          context,
          broadcast: _event(end: DateTime.utc(2026, 1, 1)),
        ),
        premium: false,
        liveIds: ['event'],
      );
      expect(results, [true]);
    });

    testWidgets('Premium access opens a Past card at once', (tester) async {
      final results = await _runGate(
        tester,
        (context) => ensurePastEventAccess(
          context,
          broadcast: _event(end: DateTime.utc(2026, 1, 1)),
          past: true,
        ),
        premium: true,
      );
      expect(results, [true]);
    });
  });

  group('ensureEventGameAccess', () {
    testWidgets('old dates never gate games of a Current-view event', (
      tester,
    ) async {
      final results = await _runGate(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        premium: false,
        selected: _event(start: DateTime.utc(2000)),
        overrides: [
          currentEventMembershipProvider(
            'event',
          ).overrideWith((_) async => true),
        ],
      );
      expect(results, [true]);
    });

    testWidgets('a later start-only category keeps the event playable', (
      tester,
    ) async {
      final now = DateTime.now();
      final old = _detail([
        now.subtract(const Duration(days: 20)),
        now.subtract(const Duration(days: 10)),
      ]);
      final later = _detail([now.add(const Duration(days: 3))]);
      final results = await _runGate(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        premium: false,
        selected: _event(),
        overrides: [
          tourDetailScreenProviderOverride(
            TourDetailViewModel(
              aboutTourModel: old.aboutTourModel,
              liveTourIds: const [],
              tours: [...old.tours, ...later.tours],
            ),
          ),
        ],
        watch: (ref) => ref.watch(tourDetailScreenProvider),
      );
      expect(results, [true]);
    });

    testWidgets('a final-day event game stays free', (tester) async {
      final results = await _runGate(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        premium: false,
        selected: _event(
          end: DateTime.now().subtract(const Duration(hours: 12)),
        ),
      );
      expect(results, [true]);
    });

    testWidgets('a lone tour date retains the start-only grace', (
      tester,
    ) async {
      final results = await _runGate(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        premium: false,
        selected: _event(),
        overrides: [
          tourDetailScreenProviderOverride(
            _detail([DateTime.now().subtract(const Duration(days: 2))]),
          ),
        ],
        watch: (ref) => ref.watch(tourDetailScreenProvider),
      );
      expect(results, [true]);
    });
    testWidgets('no open event: the game opens', (tester) async {
      final results = await _runGate(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        premium: false,
      );
      expect(results, [true]);
    });

    testWidgets('a live event: the game opens', (tester) async {
      final results = await _runGate(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        premium: false,
        selected: _event(end: DateTime.utc(2026, 1, 1)),
        liveIds: ['event'],
      );
      expect(results, [true]);
    });

    testWidgets('a running event: the game opens', (tester) async {
      final results = await _runGate(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        premium: false,
        selected: _event(
          start: DateTime.now().subtract(const Duration(days: 2)),
          end: DateTime.now().add(const Duration(days: 2)),
        ),
      );
      expect(results, [true]);
    });

    testWidgets('Premium access opens a past event game at once', (
      tester,
    ) async {
      final results = await _runGate(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        premium: true,
        selected: _event(end: DateTime.utc(2026, 1, 1)),
      );
      expect(results, [true]);
    });
  });

  group('ensurePgnCopyAccess', () {
    testWidgets('Premium access copies without asking', (tester) async {
      final results = await _runGate(
        tester,
        (context) => ensurePgnCopyAccess(context, returnTo: 'chessboard'),
        premium: true,
      );
      expect(results, [true]);
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('a free viewer is asked first', () {
    testWidgets('a resolved empty live snapshot clears the old Events cache', (
      tester,
    ) async {
      await _expectPromptThenDeny(
        tester,
        (context) => ensurePastEventAccess(
          context,
          broadcast: _event(end: DateTime.utc(2026, 1, 1)),
        ),
        liveIds: ['event'],
        overrides: [
          liveGroupBroadcastIdsProvider.overrideWith((_) => Stream.value([])),
        ],
        watch: (ref) => ref.watch(liveGroupBroadcastIdsProvider),
      );
    });

    testWidgets('an explicit single-day tour end is retained', (tester) async {
      final date = DateTime.now().subtract(const Duration(days: 2));
      await _expectPromptThenDeny(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        selected: _event(),
        overrides: [
          tourDetailScreenProviderOverride(_detail([date, date])),
        ],
        watch: (ref) => ref.watch(tourDetailScreenProvider),
      );
    });

    testWidgets('a partial selected row uses the canonical end', (
      tester,
    ) async {
      final start = DateTime.now().subtract(const Duration(days: 3));
      await _expectPromptThenDeny(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        selected: _event(start: start),
        overrides: [
          canonicalSelectedBroadcastProvider.overrideWith(
            (_) async =>
                _event(start: start, end: start.add(const Duration(days: 1))),
          ),
        ],
        watch: (ref) => ref.watch(canonicalSelectedBroadcastProvider),
      );
    });

    testWidgets('an undated database event resolves its dates before opening', (
      tester,
    ) async {
      await _expectPromptThenDeny(
        tester,
        (context) => ensurePastEventAccess(
          context,
          broadcast: virtualGroupBroadcastForEvent('Event'),
        ),
        overrides: [
          gamebaseEventViewProvider(
            const GamebaseEventViewRequest(eventName: 'Event'),
          ).overrideWith(
            (_) async => GamebaseEventView.fromData({
              'event': 'Event',
              'about': {'startDate': '2026-01-01', 'endDate': '2026-01-01'},
            }),
          ),
        ],
      );
    });
    testWidgets('a Past card raises the prompt; dismissal stays put', (
      tester,
    ) async {
      await _expectPromptThenDeny(
        tester,
        (context) => ensurePastEventAccess(
          context,
          broadcast: _event(end: DateTime.utc(2026, 1, 1)),
          past: true,
        ),
      );
    });

    testWidgets('a past search hit raises the prompt', (tester) async {
      await _expectPromptThenDeny(
        tester,
        (context) => ensurePastEventAccess(
          context,
          broadcast: _event(
            start: DateTime.utc(2026, 1, 1),
            end: DateTime.utc(2026, 1, 9),
          ),
        ),
      );
    });

    testWidgets('a game of a past event raises the prompt', (tester) async {
      await _expectPromptThenDeny(
        tester,
        (context) => ensureEventGameAccess(context, tourId: 'tour'),
        selected: _event(
          start: DateTime.utc(2026, 1, 1),
          end: DateTime.utc(2026, 1, 9),
        ),
      );
    });

    testWidgets('Copy PGN raises the prompt', (tester) async {
      await _expectPromptThenDeny(
        tester,
        (context) => ensurePgnCopyAccess(context, returnTo: 'chessboard'),
      );
    });

    testWidgets('Copy event PGN raises the prompt', (tester) async {
      await _expectPromptThenDeny(
        tester,
        (context) => ensurePgnCopyAccess(
          context,
          featureId: 'copy_event_pgn',
          returnTo: 'events/event_card',
        ),
      );
    });
  });
}
