import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/my_space/domain/my_space_shelf_state.dart';
import 'package:chessever2/screens/my_space/my_space_screen.dart';
import 'package:chessever2/screens/my_space/providers/my_space_content_providers.dart';
import 'package:chessever2/screens/my_space/widgets/my_space_entity_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  testWidgets('renders the exact curated shelf order', (tester) async {
    await _pumpMySpace(tester);

    final feed = tester.widget<ListView>(
      find.byKey(const PageStorageKey<String>('my-space-vertical-feed')),
    );
    final delegate = feed.childrenDelegate as SliverChildListDelegate;

    expect(
      delegate.children.map((child) => (child.key! as ValueKey<String>).value),
      const [
        'my-space-shelf-default_continue',
        'my-space-shelf-default_my_likes',
        'my-space-shelf-default_saved_events',
        'my-space-shelf-default_databases',
        'my-space-shelf-default_saved_studies',
        'my-space-shelf-default_favorite_players',
      ],
    );
  });

  testWidgets('one shelf error leaves the other shelves visible', (
    tester,
  ) async {
    await _pumpMySpace(
      tester,
      size: const Size(393, 1200),
      continueState: MySpaceShelfState<List<MySpaceContentItem>>.error(
        StateError('continue failed'),
      ),
    );

    expect(find.text('Continue could not load'), findsOneWidget);
    expect(find.text('My Likes is ready when you are'), findsOneWidget);
    expect(find.text('Saved Events is ready when you are'), findsOneWidget);
  });

  testWidgets('renders loading, empty, data, and item tombstone states', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final event = _eventItem();
    const tombstone = MySpaceUnavailableItem(
      id: 'event-unavailable',
      title: 'Saved event unavailable',
      subtitle: 'This favorite does not have a canonical event reference.',
      sourceType: 'Event',
    );

    await _pumpMySpace(
      tester,
      size: const Size(393, 1200),
      continueState:
          const MySpaceShelfState<List<MySpaceContentItem>>.loading(),
      savedEventsState: MySpaceShelfState<List<MySpaceContentItem>>.data([
        event,
        tombstone,
      ]),
    );

    expect(find.bySemanticsLabel('Continue loading'), findsOneWidget);
    expect(find.text('My Likes is ready when you are'), findsOneWidget);
    expect(find.text(event.title), findsOneWidget);
    expect(find.text('Saved event unavailable'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
    semantics.dispose();
  });

  testWidgets('populated card invokes the injected primary action', (
    tester,
  ) async {
    final event = _eventItem();
    MySpaceContentItem? opened;

    await _pumpMySpace(
      tester,
      size: const Size(393, 1000),
      savedEventsState: MySpaceShelfState<List<MySpaceContentItem>>.data([
        event,
      ]),
      screen: MySpaceScreen(onOpenItem: (item) => opened = item),
    );

    final card = find.byKey(ValueKey<String>('my-space-card-${event.id}'));
    await tester.scrollUntilVisible(
      card,
      220,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey<String>('my-space-vertical-feed')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(card);
    await tester.pump();

    expect(opened, same(event));
  });

  testWidgets('light and dark large-text layouts do not overflow small phones', (
    tester,
  ) async {
    final longItem = _eventItem(
      title:
          'A deliberately long international championship title for Dynamic Type',
      subtitle:
          'Classical · A long date range and status that must remain inside the opaque card',
      status: 'Live coverage is available from the canonical event source',
    );
    final data = MySpaceShelfState<List<MySpaceContentItem>>.data([longItem]);

    for (final config in <(Size, ThemeData)>[
      (const Size(320, 1200), AppTheme.lightTheme),
      (const Size(393, 1200), AppTheme.darkTheme),
    ]) {
      await _pumpMySpace(
        tester,
        size: config.$1,
        theme: config.$2,
        textScaler: const TextScaler.linear(2),
        continueState: data,
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Failed at ${config.$1}');
      expect(find.byType(MySpaceEntityCard), findsWidgets);
    }
  });

  testWidgets(
    'uses floating overlay chrome without an app bar or pinned header',
    (tester) async {
      await _pumpMySpace(tester);

      expect(find.byType(GlassFullScreenPage), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SliverAppBar), findsNothing);
      expect(find.byType(SliverPersistentHeader), findsNothing);
      expect(
        tester
            .widgetList<Scaffold>(find.byType(Scaffold))
            .every((scaffold) => scaffold.appBar == null),
        isTrue,
      );
      expect(
        find.ancestor(
          of: find.byKey(
            const ValueKey<String>('my-space-floating-top-overlay'),
          ),
          matching: find.byType(Stack),
        ),
        findsWidgets,
      );
    },
  );

  testWidgets('Reduce Motion removes shelf transition durations', (
    tester,
  ) async {
    await _pumpMySpace(tester);

    final switchers = tester.widgetList<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switchers, isNotEmpty);
    expect(
      switchers.every((switcher) => switcher.duration == Duration.zero),
      isTrue,
    );
  });

  testWidgets('labels controls and previews Add shelf without a fake save', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final event = _eventItem();
    await _pumpMySpace(
      tester,
      size: const Size(393, 1000),
      continueState: MySpaceShelfState<List<MySpaceContentItem>>.data([event]),
    );

    expect(find.bySemanticsLabel('Open account'), findsOneWidget);
    expect(find.bySemanticsLabel('Add shelf'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'Event, Candidates Tournament.*Open event'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('my-space-account-button')),
          )
          .shortestSide,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('my-space-add-shelf-button')),
          )
          .height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('my-space-add-shelf-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build your own My Space'), findsOneWidget);
    expect(
      find.textContaining('Preview only — this cannot change your layout'),
      findsOneWidget,
    );
    expect(find.textContaining('saved successfully'), findsNothing);
    expect(find.text('Shelf saved'), findsNothing);
    semantics.dispose();
  });

  testWidgets('authorized Add shelf capability is callback-driven', (
    tester,
  ) async {
    var calls = 0;
    await _pumpMySpace(
      tester,
      screen: MySpaceScreen(onAuthorizedAddShelf: () => calls++),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('my-space-add-shelf-button')),
    );
    await tester.pump();

    expect(calls, 1);
    expect(find.text('Build your own My Space'), findsNothing);
  });
}

Future<void> _pumpMySpace(
  WidgetTester tester, {
  Size size = const Size(393, 900),
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  MySpaceContentShelfState? continueState,
  MySpaceContentShelfState? likesState,
  MySpaceContentShelfState? savedEventsState,
  MySpaceContentShelfState? databasesState,
  MySpaceContentShelfState? savedStudiesState,
  MySpaceContentShelfState? favoritePlayersState,
  MySpaceScreen screen = const MySpaceScreen(),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  const empty = MySpaceShelfState<List<MySpaceContentItem>>.empty();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        mySpaceContinueShelfProvider.overrideWithValue(continueState ?? empty),
        mySpaceLikesShelfProvider.overrideWithValue(likesState ?? empty),
        mySpaceSavedEventsShelfProvider.overrideWithValue(
          savedEventsState ?? empty,
        ),
        mySpaceDatabasesShelfProvider.overrideWithValue(
          databasesState ?? empty,
        ),
        mySpaceSavedStudiesShelfProvider.overrideWithValue(
          savedStudiesState ?? empty,
        ),
        mySpaceFavoritePlayersShelfProvider.overrideWithValue(
          favoritePlayersState ?? empty,
        ),
      ],
      child: LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: textScaler, disableAnimations: true),
                child: screen,
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

MySpaceEventItem _eventItem({
  String title = 'Candidates Tournament',
  String subtitle = 'Classical',
  String? status,
}) {
  final now = DateTime(2026, 7, 10);
  final event = FavoriteEvent(
    id: 'favorite-event-1',
    userId: 'user-1',
    eventId: 'broadcast-42',
    eventName: title,
    metadata: const {'timeControl': 'Classical'},
    createdAt: now,
    updatedAt: now,
  );
  return MySpaceEventItem(
    id: 'event:broadcast-42',
    title: title,
    subtitle: subtitle,
    status: status,
    actionLabel: 'Open event',
    event: event,
  );
}
