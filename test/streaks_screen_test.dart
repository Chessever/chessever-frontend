import 'dart:async';

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/streaks/streaks_screen.dart';
import 'package:chessever2/screens/streaks/widgets/wall_filter_tabs.dart';
import 'package:chessever2/screens/streaks/widgets/wall_row.dart';
import 'package:chessever2/screens/streaks/widgets/wall_runs_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Wall double: fixture rows, no SQLite, no network.
class _FakeWall extends StreakWallNotifier {
  _FakeWall(this._load);

  final Future<List<StreakRow>> Function() _load;
  int refreshes = 0;

  @override
  Future<List<StreakRow>> build() => _load();

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Future<void> refreshIfStale({Duration maxAge = kStreakWallMaxAge}) async {}
}

/// Subscription double without RevenueCat's constructor side effects.
class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(bool subscribed)
    : super(SubscriptionState(isSubscribed: subscribed));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StreakRow _row(
  int fideId,
  StreakTimeClass tc,
  String name,
  int streak, {
  String? title = 'GM',
  String fed = 'IND',
  int? rating = 2700,
  int? age = 30,
  String sex = 'M',
  int? oppAvg,
  bool playing = false,
}) {
  return StreakRow(
    fideId: fideId,
    timeClass: tc,
    name: name,
    title: title,
    fed: fed,
    sex: sex,
    rating: rating,
    age: age,
    currentStreak: streak,
    bestStreak: streak,
    runOppAvg: oppAvg,
    trackedCurrent: playing,
  );
}

const _std = StreakTimeClass.standard;
const _rapid = StreakTimeClass.rapid;
const _blitz = StreakTimeClass.blitz;

/// Ranked per class, the way the wall arrives.
final _fixture = <StreakRow>[
  _row(1503014, _std, 'Carlsen, Magnus', 11, fed: 'NOR', rating: 2830, age: 35, oppAvg: 2701),
  _row(5000017, _std, 'Gujrathi, Vidit', 9, rating: 2727, age: 32),
  _row(20000001, _std, 'Oro, Faustino', 7, title: 'IM', fed: 'ARG', rating: 2512, age: 12),
  _row(30000009, _std, 'Young, Prodigy', 5, title: null, fed: 'USA', rating: 1900, age: 9),
  _row(40000004, _std, 'Hou, Yifan', 4, fed: 'CHN', rating: 2630, age: 32, sex: 'F', playing: true),
  _row(50000005, _std, 'Elder, Statesman', 3, rating: 2400, age: 66),
  _row(60000006, _rapid, 'Nakamura, Hikaru', 8, fed: 'USA', rating: 2750),
  _row(1503014, _rapid, 'Carlsen, Magnus', 4, fed: 'NOR', rating: 2820, age: 35),
  _row(70000007, _rapid, 'Firouzja, Alireza', 3, fed: 'FRA', rating: 2700, age: 23),
  _row(80000008, _blitz, 'So, Wesley', 6, fed: 'USA', rating: 2760),
  _row(90000009, _blitz, 'Caruana, Fabiano', 3, fed: 'USA', rating: 2780),
];

Iterable<int> _ids(StreakTimeClass tc) =>
    _fixture.where((r) => r.timeClass == tc).map((r) => r.fideId);

/// The players a class wall shows by default: rated 2650+ in that class.
Iterable<int> _floorIds(StreakTimeClass tc) => _fixture
    .where((r) => r.timeClass == tc && passesStreakFloor(r))
    .map((r) => r.fideId);

Finder _wallRow(int fideId) => find.byKey(ValueKey<int>(fideId));

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Future<List<StreakRow>> Function()? load,
  bool subscribed = false,
  StreakTimeClass? initialClass,
  _FakeWall? wall,
}) async {
  // Tall enough that the whole list is built without scrolling.
  tester.view.physicalSize = const Size(390, 4200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final notifier = wall ?? _FakeWall(load ?? () async => _fixture);
  final container = ProviderContainer(
    overrides: [
      streakWallProvider.overrideWith(() => notifier),
      subscriptionProvider.overrideWith((ref) => _Subscription(subscribed)),
      playerPhotoProvider.overrideWith((ref, fideId) async => null),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return StreaksScreen(initialClass: initialClass);
          },
        ),
      ),
    ),
  );
  await _settle(tester);
  return container;
}

/// The embers drift forever, so never pumpAndSettle: a few frames land
/// every spring and post-frame callback the wall uses.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  // The last match is the drawn label; the first is its invisible bold twin.
  final tab = find.text(label).last;
  await tester.ensureVisible(tab);
  await tester.pump();
  await tester.tap(tab);
  await _settle(tester);
}

void main() {
  testWidgets('class switch shows each wall\'s count and swaps the list', (
    tester,
  ) async {
    final container = await _pump(tester);

    Finder countIn(StreakTimeClass tc, String n) => find.descendant(
      of: find.byKey(ValueKey<String>('streak-class-${tc.wire}')),
      matching: find.text(n),
    );
    // Classical counts only its 2650+ players: Carlsen and Vidit.
    expect(countIn(_std, '2'), findsOneWidget);
    expect(countIn(_rapid, '3'), findsOneWidget);
    expect(countIn(_blitz, '2'), findsOneWidget);

    // Classical is the default wall: its 2650+ runs, nothing else.
    expect(find.text('Everyone on a run'), findsOneWidget);
    for (final id in _floorIds(_std)) {
      expect(_wallRow(id), findsOneWidget);
    }
    for (final id in _ids(_std).where((id) => !_floorIds(_std).contains(id))) {
      expect(_wallRow(id), findsNothing);
    }
    expect(_wallRow(60000006), findsNothing);
    expect(find.text('Classical · all ages'), findsOneWidget);

    // Carlsen burns in rapid too; the row says so, with his opposition.
    expect(find.text('beat avg 2701 · also 4 in rapid'), findsOneWidget);
    expect(find.text('NOR · 2830 · 35 y'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('streak-class-rapid')));
    await _settle(tester);

    expect(container.read(streakSelectedClassProvider), _rapid);
    for (final id in _ids(_rapid)) {
      expect(_wallRow(id), findsOneWidget);
    }
    expect(_wallRow(5000017), findsNothing);
    expect(find.text('Rapid · all ages'), findsOneWidget);
    // Ranked as the wall ranks them: Nakamura's 8 above Carlsen's 4.
    expect(
      tester.getTopLeft(_wallRow(60000006)).dy,
      lessThan(tester.getTopLeft(_wallRow(1503014)).dy),
    );
    expect(find.text('also 11 in classical'), findsOneWidget);
  });

  testWidgets('FIDE age groups filter by calendar-year age', (tester) async {
    final container = await _pump(tester);

    // Under 12 is 12 or younger this year: Oro (12) and the 9-year-old.
    await _tapTab(tester, 'Under 12');
    expect(container.read(streakWallFilterProvider).age, StreakAgeGroup.u12);
    expect(_wallRow(20000001), findsOneWidget);
    expect(_wallRow(30000009), findsOneWidget);
    expect(_wallRow(1503014), findsNothing);
    expect(find.text('Classical · Under 12'), findsOneWidget);

    await _tapTab(tester, 'Under 10');
    expect(_wallRow(30000009), findsOneWidget);
    expect(_wallRow(20000001), findsNothing);

    await _tapTab(tester, 'Seniors 65+');
    expect(_wallRow(50000005), findsOneWidget);
    expect(_wallRow(30000009), findsNothing);

    await _tapTab(tester, 'All ages');
    for (final id in _floorIds(_std)) {
      expect(_wallRow(id), findsOneWidget);
    }

    // The distribution counts what is visible (the 2650+ default).
    final card = tester.widget<WallRunsCard>(find.byType(WallRunsCard));
    expect(card.rows.length, _floorIds(_std).length);
  });

  testWidgets('women and playing-now toggles narrow the wall', (tester) async {
    await _pump(tester);

    await _tapTab(tester, 'Women');
    expect(_wallRow(40000004), findsOneWidget);
    expect(_wallRow(1503014), findsNothing);
    expect(find.text('Classical · all ages · women'), findsOneWidget);

    // Playing now narrows by time, not by who, so the 2650 floor stays:
    // Hou (2630) is live but under it, and no 2650+ player is live.
    await _tapTab(tester, 'Women');
    await _tapTab(tester, 'Playing now');
    expect(_wallRow(40000004), findsNothing);
    expect(_wallRow(5000017), findsNothing);
  });

  testWidgets('an empty filter is one calm line with a way back', (
    tester,
  ) async {
    final container = await _pump(tester);

    await _tapTab(tester, 'Under 10');
    await _tapTab(tester, 'Women');

    expect(find.byType(WallRow), findsNothing);
    expect(
      find.text('No one matching these filters is on a classical run right now.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Show everyone'));
    await _settle(tester);

    expect(container.read(streakWallFilterProvider).isDefault, isTrue);
    expect(find.byType(WallRow), findsNWidgets(_floorIds(_std).length));
  });

  testWidgets('locked filters carry the padlock only without Premium', (
    tester,
  ) async {
    await _pump(tester);
    // Eight age groups beyond "All ages", Women and Playing now.
    expect(find.byType(WallLockGlyph), findsNWidgets(10));
  });

  testWidgets('subscribers see no padlocks', (tester) async {
    await _pump(tester, subscribed: true);
    expect(find.byType(WallLockGlyph), findsNothing);
  });

  testWidgets('initialClass opens straight onto that wall', (tester) async {
    final container = await _pump(tester, initialClass: _blitz);

    expect(container.read(streakSelectedClassProvider), _blitz);
    expect(_wallRow(80000008), findsOneWidget);
    expect(_wallRow(90000009), findsOneWidget);
    expect(_wallRow(1503014), findsNothing);
  });

  testWidgets('loading shows skeleton rows, not the wall', (tester) async {
    final never = Completer<List<StreakRow>>();
    await _pump(tester, load: () => never.future);

    expect(find.byType(WallSkeletonRows), findsOneWidget);
    expect(find.byType(WallRow), findsNothing);
  });

  testWidgets('a failed first load offers a retry', (tester) async {
    final wall = _FakeWall(() async => throw Exception('offline'));
    await _pump(tester, wall: wall);

    expect(find.byType(GenericErrorWidget), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(wall.refreshes, 1);
  });
}
