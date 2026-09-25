import 'dart:math' as math;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The top bar is part of the home scaffold, not of each tab: the widgets the
/// four tabs share (the profile avatar on every tab, the search field on
/// Events, For You and Library) sit at the same place and the same size
/// whichever tab is open, in both themes, for a free and a premium account,
/// at the default and large text sizes. Events is the reference and its
/// shipped geometry is pinned at every text size, so parity can never be
/// reached by moving it. Every control in the bar takes a 44pt tap however
/// small the phone draws it.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await SharedPreferencesService.instance.initialize();
    // The app's own type, so text takes the width it takes on a phone. The
    // stock test font draws every glyph a full em wide, far wider than
    // Inter: at 2x its "Search " hint alone outruns a field that holds
    // Inter's with room to spare.
    final inter = FontLoader('InterDisplay');
    for (final weight in const ['Regular', 'Medium', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
    }
    await inter.load();
  });

  // 393 first: the field's type is sized once, on the first layout, as it is
  // on a phone.
  final cases = <(Size, double)>[
    for (final size in const [Size(393, 852), Size(360, 780)])
      for (final textScale in [1.0, 1.3, 1.4, 2.0]) (size, textScale),
  ];

  for (final (size, textScale) in cases) {
    for (final light in [true, false]) {
      for (final premium in [false, true]) {
        final label =
            '${size.width.toInt()}x${size.height.toInt()} ${textScale}x '
            '${light ? 'light' : 'dark'} ${premium ? 'premium' : 'free'}';

        testWidgets('common top-bar widgets hold still across tabs, $label', (
          tester,
        ) async {
          final shell = await pumpHomeShell(
            tester,
            size: size,
            light: light,
            premium: premium,
            textScale: textScale,
          );
          final bars = <BottomNavBarItem, TopBarRects>{};
          for (final tab in homeTabs) {
            await shell.show(tab);
            expect(tester.takeException(), isNull, reason: tab.name);
            bars[tab] = measureTopBar(tester);
          }

          final events = bars[BottomNavBarItem.tournaments]!;

          // The avatar: one rect everywhere, always a circle.
          for (final tab in homeTabs) {
            final bar = bars[tab]!;
            _expectRect(bar.avatar, events.avatar, '${tab.name} avatar', 0.01);
            _expectRect(bar.circle, events.circle, '${tab.name} circle', 0.01);
            expect(
              bar.circle.width,
              closeTo(bar.circle.height, 0.01),
              reason: '${tab.name}: the avatar is never squashed to an oval',
            );
          }

          // The search field starts, sits and stands the same wherever it
          // appears; only its width is the tab's own (Library keeps its
          // Board and Add tiles beside it).
          for (final tab in const [
            BottomNavBarItem.forYou,
            BottomNavBarItem.library,
          ]) {
            final field = bars[tab]!.field!;
            final reference = events.field!;
            final reason = '${tab.name} search field';
            expect(field.left, closeTo(reference.left, 0.5), reason: reason);
            expect(field.top, closeTo(reference.top, 0.5), reason: reason);
            expect(
              field.height,
              closeTo(reference.height, 0.5),
              reason: reason,
            );
          }
          // For You wears Events' bar unchanged, width included.
          _expectRect(
            bars[BottomNavBarItem.forYou]!.field!,
            events.field!,
            'For You field',
          );

          // Every tab-specific control rides the avatar's centre line and
          // stays inside the bar's right gutter.
          final centre = events.circle.center.dy;
          for (final tab in homeTabs) {
            for (final entry in bars[tab]!.controls.entries) {
              expect(
                entry.value.center.dy,
                closeTo(centre, 0.5),
                reason: '${tab.name} ${entry.key} centre line',
              );
              expect(
                entry.value.right,
                lessThanOrEqualTo(size.width - events.avatar.left + 11.5),
                reason: '${tab.name} ${entry.key} right gutter',
              );
            }
          }
          // Events' shipped geometry, unchanged at every text size.
          _expectShippedEvents(size, textScale, premium, events);

          // The field's text follows the system text size on every tab; the
          // chrome (the avatar's initials) stops at the bar's cap.
          for (final tab in homeTabs) {
            await shell.show(tab);
            final chromeScale = math.min(
              textScale,
              HomeTopBarMetrics.maxTextScale,
            );
            _expectScale(
              tester,
              find.byType(HomeTopBarAvatar),
              chromeScale,
              '${tab.name} avatar',
            );
            _expectScale(
              tester,
              find.byType(EditableText),
              textScale,
              '${tab.name} field',
            );
          }

          await shell.dispose();
        });
      }
    }
  }

  // 360 draws the avatar 40.3pt tall and Library's tiles
  // 33pt; 350 draws them 39.2pt and 32.1pt, so a tap 2pt past each one's
  // edge is still inside its 44pt target.
  for (final size in const [Size(350, 760), Size(360, 780)]) {
    testWidgets('every top-bar control takes a 44pt tap without moving, '
        '${size.width.toInt()}pt', (tester) async {
      final shell = await pumpHomeShell(
        tester,
        size: size,
        light: true,
        premium: false,
      );
      for (final tab in homeTabs) {
        await shell.show(tab);
        final layout = measureTopBar(tester).toString();
        final controls = [
          for (final (name, finder) in _tapControls(tab))
            (
              name: name,
              drawn: tester.getRect(finder),
              target: _gestureTarget(tester, finder),
            ),
        ];
        expect(controls, isNotEmpty);

        /// The control a tap at [point] belongs to: the nearest one whose
        /// 44pt target reaches it (a neighbour's reach can overlap).
        RenderObject? owner(Offset point) {
          RenderObject? best;
          var bestDistance = double.infinity;
          for (final control in controls) {
            final drawn = control.drawn;
            final reach = Rect.fromCenter(
              center: drawn.center,
              width: math.max(drawn.width, 44),
              height: math.max(drawn.height, 44),
            );
            if (!reach.contains(point)) continue;
            final dx = math.max(
              0.0,
              math.max(drawn.left - point.dx, point.dx - drawn.right),
            );
            final dy = math.max(
              0.0,
              math.max(drawn.top - point.dy, point.dy - drawn.bottom),
            );
            if (dx * dx + dy * dy < bestDistance) {
              bestDistance = dx * dx + dy * dy;
              best = control.target;
            }
          }
          return best;
        }

        for (final (:name, :drawn, :target) in controls) {
          final reason = '${tab.name} $name';
          // How far the 44pt target reaches past each drawn edge; a side
          // drawn a full 44pt (to layout rounding) reaches nowhere.
          double reachFor(double extent) =>
              extent > 44 - 0.02 ? 0 : (44 - extent) / 2;
          final reachX = reachFor(drawn.width);
          final reachY = reachFor(drawn.height);
          // Every control here is drawn short of 44pt on some side, and on
          // the narrower phone by more than 2pt a side.
          expect(
            math.max(reachX, reachY),
            size.width < 360 ? greaterThan(2) : greaterThan(0),
            reason: reason,
          );

          // Just inside the 44pt target on every short side, and 2pt past
          // the drawn edge wherever the target reaches that far: taken, by
          // this control or a nearer neighbour whose target overlaps it.
          double inside(double reach) =>
              reach > 0 ? math.max(reach - 0.25, reach / 2) : 0;
          for (final point in [
            ..._around(drawn, inside(reachX), inside(reachY)),
            ..._around(drawn, reachX > 2 ? 2 : 0, reachY > 2 ? 2 : 0),
          ]) {
            final expected = owner(point);
            expect(expected, isNotNull, reason: '$reason at $point');
            expect(
              _hits(tester, point, expected!),
              isTrue,
              reason: '$reason at $point, drawn $drawn',
            );
          }
          // Past the target: never taken by this control.
          for (final point in _around(
            drawn,
            reachX > 0 ? reachX + 1 : 0,
            reachY > 0 ? reachY + 1 : 0,
          )) {
            expect(
              _hits(tester, point, target),
              isFalse,
              reason: '$reason at $point, drawn $drawn',
            );
          }
        }

        // A real tap outside the drawn avatar opens the sidebar.
        final avatar = tester.getRect(
          find.descendant(
            of: find.byType(_ShellBody),
            matching: find.byType(HomeTopBarAvatar),
          ),
        );
        final nudge = math.min(2.0, (44 - avatar.width) / 2 - 0.25);
        await tester.tapAt(Offset(avatar.left - nudge, avatar.center.dy));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Sidebar'), findsOneWidget, reason: tab.name);
        tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // The targets change no layout.
        expect(measureTopBar(tester).toString(), layout, reason: tab.name);
      }
      await shell.dispose();
    });
  }

  testWidgets('the avatar opens the sidebar from every tab', (tester) async {
    final shell = await pumpHomeShell(
      tester,
      size: const Size(393, 852),
      light: false,
      premium: true,
    );
    for (final tab in homeTabs) {
      await shell.show(tab);
      expect(find.text('Sidebar'), findsNothing, reason: tab.name);
      await tester.tap(find.bySemanticsLabel('Open sidebar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sidebar'), findsOneWidget, reason: tab.name);
      tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await shell.dispose();
  });

  testWidgets('Library search: focus takes the row, typing filters, clear '
      'resets and lets go', (tester) async {
    final shell = await pumpHomeShell(
      tester,
      size: const Size(393, 852),
      light: true,
      premium: false,
    );
    await shell.show(BottomNavBarItem.library);
    final surface = find.byKey(const ValueKey('simple-search-field-surface'));
    final field = find.byKey(const ValueKey('e2e_library_search_field'));
    expect(find.text('ChessEver'), findsOneWidget);
    expect(find.text('Miniatures'), findsOneWidget);
    expect(tester.getRect(surface).left, closeTo(80, 0.5));

    // Focus hands the field the whole row: avatar and tiles squeeze out,
    // the height holds.
    await tester.tap(field);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(surface).left, closeTo(20, 0.5));
    expect(tester.getRect(surface).right, closeTo(373, 0.5));
    expect(tester.getRect(surface).height, closeTo(44, 0.5));

    await tester.enterText(field, 'Mini');
    await tester.pump();
    expect(find.text('Miniatures'), findsOneWidget);
    expect(find.text('ChessEver'), findsNothing);

    // The field's own clear button.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('ChessEver'), findsOneWidget);
    expect(find.text('Miniatures'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.getRect(surface).left, closeTo(80, 0.5));

    await shell.dispose();
  });
}

/// The home tabs, in bottom-nav order.
const homeTabs = <BottomNavBarItem>[
  BottomNavBarItem.tournaments,
  BottomNavBarItem.forYou,
  BottomNavBarItem.library,
];

/// The status bar and home indicator of a notched phone.
const double shellTopInset = 47;
const double shellBottomInset = 34;

/// Events' shipped bar, as its plain row always laid it out: the avatar and
/// the field centred on the taller of the two. The field's height follows
/// the system text size: 4.sp padding around the taller of the filter tile
/// and one 16pt line at 1.5 line height, scaled.
void _expectShippedEvents(
  Size size,
  double textScale,
  bool premium,
  TopBarRects events,
) {
  final narrow = size.width == 360;
  final top = narrow ? 68.97 : 71.0;
  final avatarSide = switch ((narrow, premium)) {
    (false, false) => 44.0,
    (false, true) => 58.0,
    (true, false) => 40.31,
    (true, true) => 53.12,
  };
  final fieldHeight = switch ((narrow, textScale)) {
    (false, 2.0) => 56.0,
    (false, _) => 44.0,
    (true, 2.0) => 55.32,
    (true, 1.4) => 41.32,
    (true, _) => 40.28,
  };
  final (fieldLeft, fieldWidth) = switch ((narrow, premium)) {
    (false, false) => (80.0, 293.0),
    (false, true) => (94.0, 279.0),
    (true, false) => (73.27, 268.42),
    (true, true) => (86.09, 255.60),
  };
  final row = math.max(avatarSide, fieldHeight);
  _expectRect(
    events.avatar,
    Rect.fromLTWH(
      narrow ? 18.31 : 20,
      top + (row - avatarSide) / 2,
      avatarSide,
      avatarSide,
    ),
    'shipped Events avatar',
    0.01,
  );
  _expectRect(
    events.field!,
    Rect.fromLTWH(
      fieldLeft,
      top + (row - fieldHeight) / 2,
      fieldWidth,
      fieldHeight,
    ),
    'shipped Events field',
    0.01,
  );
}

/// The text scale [finder]'s first match in the open tab lays out at.
void _expectScale(
  WidgetTester tester,
  Finder finder,
  double scale,
  String reason,
) {
  final element = find
      .descendant(of: find.byType(_ShellBody), matching: finder)
      .evaluate()
      .first;
  expect(
    MediaQuery.textScalerOf(element).scale(10),
    closeTo(10 * scale, 0.001),
    reason: reason,
  );
}

/// The tab's own tappable controls in the bar, avatar included.
List<(String, Finder)> _tapControls(BottomNavBarItem tab) {
  Finder inTab(Finder finder) =>
      find.descendant(of: find.byType(_ShellBody), matching: finder);
  return [
    ('avatar', inTab(find.byType(HomeTopBarAvatar))),
    if (tab == BottomNavBarItem.library) ...[
      ('board', inTab(find.byKey(const ValueKey('e2e_library_board_button')))),
      (
        'add',
        inTab(find.byKey(const ValueKey('e2e_library_create_folder_button'))),
      ),
    ],
  ];
}

/// The render object that receives [control]'s taps: its outermost
/// gesture listener.
RenderObject _gestureTarget(WidgetTester tester, Finder control) {
  final listener = find.descendant(
    of: control,
    matching: find.byType(Listener),
  );
  expect(listener, findsWidgets);
  return tester.renderObject(listener.first);
}

/// Whether a pointer at [point] reaches [target].
bool _hits(WidgetTester tester, Offset point, RenderObject target) {
  final result = tester.hitTestOnBinding(point);
  return result.path.any((entry) => entry.target == target);
}

/// Points [dx] out from [drawn]'s left and right edges and [dy] out from its
/// top and bottom, each on the rect's centre line; a zero skips that axis.
List<Offset> _around(Rect drawn, double dx, double dy) => [
  if (dx > 0) ...[
    Offset(drawn.left - dx, drawn.center.dy),
    Offset(drawn.right + dx, drawn.center.dy),
  ],
  if (dy > 0) ...[
    Offset(drawn.center.dx, drawn.top - dy),
    Offset(drawn.center.dx, drawn.bottom + dy),
  ],
];

void _expectRect(
  Rect actual,
  Rect expected,
  String reason, [
  double tol = 0.5,
]) {
  expect(actual.left, closeTo(expected.left, tol), reason: '$reason left');
  expect(actual.top, closeTo(expected.top, tol), reason: '$reason top');
  expect(actual.width, closeTo(expected.width, tol), reason: '$reason width');
  expect(
    actual.height,
    closeTo(expected.height, tol),
    reason: '$reason height',
  );
}

/// Where one tab's top bar puts things, in global logical pixels.
class TopBarRects {
  const TopBarRects({
    required this.avatar,
    required this.circle,
    required this.field,
    required this.controls,
  });

  /// The whole avatar, premium ring included.
  final Rect avatar;

  /// The photo circle inside it.
  final Rect circle;

  /// The search field's surface, on the tabs that have one.
  final Rect? field;

  /// The tab's own controls, by name.
  final Map<String, Rect> controls;

  @override
  String toString() {
    String r(Rect rect) =>
        'L${rect.left.toStringAsFixed(2)} T${rect.top.toStringAsFixed(2)} '
        'W${rect.width.toStringAsFixed(2)} H${rect.height.toStringAsFixed(2)}';
    return [
      'avatar: ${r(avatar)}',
      'circle: ${r(circle)}',
      if (field != null) 'field: ${r(field!)}',
      for (final entry in controls.entries) '${entry.key}: ${r(entry.value)}',
    ].join('\n');
  }
}

TopBarRects measureTopBar(WidgetTester tester) {
  // The open tab only: the bottom nav carries its own labels.
  Finder inTab(Finder finder) =>
      find.descendant(of: find.byType(_ShellBody), matching: finder);

  final avatar = inTab(find.byType(UserAvatar));
  expect(avatar, findsOneWidget);
  final circle = find
      .descendant(of: avatar, matching: find.byType(AnimatedContainer))
      .first;
  final field = inTab(
    find.byKey(const ValueKey('simple-search-field-surface')),
  );

  Rect? rectOf(Finder finder) =>
      finder.evaluate().isEmpty ? null : tester.getRect(finder.first);

  final controls = <String, Rect>{
    for (final (name, finder) in [
      ('board', find.byKey(const ValueKey('e2e_library_board_button'))),
      ('add', find.byKey(const ValueKey('e2e_library_create_folder_button'))),
    ])
      if (rectOf(inTab(finder)) case final rect?) name: rect,
  };

  return TopBarRects(
    avatar: tester.getRect(avatar),
    circle: tester.getRect(circle),
    field: rectOf(field),
    controls: controls,
  );
}

/// One home shell with every tab offline: the real tab screens under one
/// Scaffold (sidebar drawer, bottom nav), switched the way the nav switches
/// them. Events and For You get stand-in list pages; Library has no
/// folders.
class HomeShell {
  HomeShell._(this._tester, this._container);

  final WidgetTester _tester;
  final ProviderContainer _container;

  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  Future<void> show(BottomNavBarItem tab) async {
    _container.read(selectedBottomNavBarItemProvider.notifier).state = tab;
    await _tester.pump();
    await _tester.pump();
    await _tester.pump(const Duration(milliseconds: 50));
  }

  /// Unmounts inside the fake clock so no timer outlives the test.
  Future<void> dispose() async {
    await _tester.pumpWidget(const SizedBox.shrink());
    await _tester.pump(const Duration(seconds: 61));
  }
}

Future<HomeShell> pumpHomeShell(
  WidgetTester tester, {
  required Size size,
  required bool light,
  required bool premium,
  double textScale = 1,
  Key? boundaryKey,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  tester.view.padding = const FakeViewPadding(
    top: shellTopInset * 2,
    bottom: shellBottomInset * 2,
  );
  tester.view.viewPadding = const FakeViewPadding(
    top: shellTopInset * 2,
    bottom: shellBottomInset * 2,
  );
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        overrides: [
          selectedBottomNavBarItemProvider.overrideWith(
            (ref) => BottomNavBarItem.tournaments,
          ),
          recentSearchStorageProvider.overrideWithValue(
            _MemoryRecentSearches(),
          ),
          currentUserProvider.overrideWithValue(
            AppUser(
              id: 'u1',
              displayName: 'Test User',
              createdAt: DateTime(2026),
            ),
          ),
          subscriptionProvider.overrideWith(
            (ref) => _FixedSubscription(premium: premium),
          ),
          boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
          likedGamesProvider.overrideWith(_NoLikes.new),
          spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
          libraryRepositoryProvider.overrideWith(
            (ref) => _OfflineLibraryRepository(),
          ),
          libraryFolderAuthenticatedUserIdProvider.overrideWith((ref) => null),
          libraryFoldersStreamProvider.overrideWith(
            (ref) => Stream.value(const <LibraryFolder>[]),
          ),
          subscribedBooksProvider.overrideWith(
            (ref) async => const <LibraryFolder>[],
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const Scaffold(
                resizeToAvoidBottomInset: false,
                drawer: Drawer(child: Text('Sidebar')),
                bottomNavigationBar: BottomNavBar(),
                body: _ShellBody(),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  return HomeShell._(tester, container);
}

/// `BottomNavBarView`, with stand-in list pages for Events and For You.
class _ShellBody extends ConsumerWidget {
  const _ShellBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(selectedBottomNavBarItemProvider);
    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: switch (tab) {
        BottomNavBarItem.tournaments => const GroupEventScreen(
          pageBuilder: _eventsPage,
        ),
        BottomNavBarItem.forYou => const ForYouScreen(pageBuilder: _forYouPage),
        BottomNavBarItem.library => const LibraryScreen(),
      },
    );
  }
}

Widget _eventsPage(
  BuildContext context,
  GroupEventCategory category,
  ScrollController controller,
) => ListView(
  controller: controller,
  children: [Text('events:${category.name}')],
);

Widget _forYouPage(
  BuildContext context,
  ForYouTab tab,
  ScrollController controller,
) => ListView(controller: controller, children: [Text('forYou:${tab.name}')]);

class _MemoryRecentSearches implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

class _FixedSubscription extends SubscriptionNotifier {
  _FixedSubscription({required this.premium}) : super() {
    state = SubscriptionState(isSubscribed: premium, isLoading: false);
  }

  final bool premium;

  @override
  set state(SubscriptionState value) =>
      super.state = value.copyWith(isSubscribed: premium, isLoading: false);
}

class _TestBoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _NoLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => const <SavedAnalysis>[];
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const <SpaceShortcut>[];
}

/// No Supabase: the only call Library makes on mount is the default-folder
/// seed.
class _OfflineLibraryRepository implements LibraryRepository {
  @override
  Future<void> ensureDefaultFolders() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
