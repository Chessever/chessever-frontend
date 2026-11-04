import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_builder_sheet.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/group_event/smart_event/starred_smart_events_screen.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/my_space/actions/space_remove_confirmation.dart';
import 'package:chessever2/screens/my_space/actions/space_shortcut_removal.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/event_card/smart_event_star.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'helpers/saved_smart_event_fakes.dart';

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => {};
  @override
  void hide(String key) => state = {...state, key};
  @override
  void unhide(String key) => state = {...state}..remove(key);
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _Aggregate extends SmartAggregateEventNotifier {
  _Aggregate(super.ref, super.query) {
    state = const AsyncData(SmartAggregateEvent.empty);
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSavedEventFixtureCache);
  final old = fixtureRequest();
  late SavedRowsTransport transport;
  late FixturePins pins;
  late ProviderContainer container;

  Future<void> host(
    WidgetTester tester,
    Widget child, {
    bool starred = true,
    List<SpaceShortcut>? cards,
    SmartEventRequest? subscribedRequest,
  }) async {
    transport = (await tester.runAsync(
      () async => SavedRowsTransport([
        if (starred) fixtureFavorite(subscribedRequest ?? old),
      ]),
    ))!;
    pins = FixturePins(cards ?? []);
    container = ProviderContainer(
      overrides: [
        favoriteEventsProvider.overrideWith(() => FixtureFavorites(transport)),
        spaceShortcutsProvider.overrideWith(() => pins),
        spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
        boardSettingsProviderNew.overrideWith(_BoardSettings.new),
        smartAggregateEventRepositoryProvider.overrideWith(
          (ref, query) => _Aggregate(ref, query),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await tester.runAsync(() => transport.client.dispose());
    });
    await Future.wait([
      container.read(favoriteEventsProvider.future),
      container.read(spaceShortcutsProvider.future),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          navigatorObservers: [routeObserver],
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return child;
            },
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'orphan subscription is visible, exact criteria shown, unstar stops only its subscription',
    (tester) async {
      await host(tester, const StarredSmartEventsScreen());
      expect(find.text(old.displayName), findsOneWidget);
      expect(find.textContaining('All time controls'), findsOneWidget);
      expect(find.textContaining('All openings'), findsOneWidget);
      expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
      expect(transport.writes, isEmpty);
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Unstar ${old.displayName}'),
        findsOneWidget,
      );
      await tester.tap(find.byType(SmartEventStar));
      await settle(tester);
      expect(transport.favorites, isEmpty);
      expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
      expect(find.text('No starred Smart Events.'), findsOneWidget);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'hidden subscription is explicitly recoverable without load-time backfill',
    (tester) async {
      await host(tester, const StarredSmartEventsScreen());
      final key = smartEventSpaceDraft(old).key;
      container.read(spaceHiddenAutoKeysProvider.notifier).hide(key);
      await settle(tester);
      expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
      expect(transport.writes, isEmpty);
      await tester.tap(find.text('Add ${old.displayName} to My Space'));
      await settle(tester);
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.targetId,
        old.criteriaKey,
      );
      expect(
        container.read(spaceHiddenAutoKeysProvider).contains(key),
        isFalse,
      );
      expect(transport.favorites, hasLength(1));
      expect(transport.writes, isEmpty);
      expect(find.text('In My Space'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Remove plus Undo changes pin/visibility only, not the actual subscription',
    (tester) async {
      SpaceShortcutRemoval? removed;
      await host(
        tester,
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () {
                    removed = removeSpaceShortcut(ref, fixturePin(old));
                  },
                  child: const Text('remove'),
                ),
                TextButton(
                  onPressed: () async {
                    await removed?.undo();
                  },
                  child: const Text('undo'),
                ),
              ],
            ),
          ),
        ),
        cards: [fixturePin(old)],
      );
      await tester.tap(find.text('remove'));
      await settle(tester);
      expect(removed, isNotNull);
      await removed!.written;
      expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
      expect(transport.favorites, hasLength(1));
      expect(transport.writes, isEmpty);
      await tester.tap(find.text('undo'));
      await settle(tester);
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.targetId,
        old.criteriaKey,
      );
      expect(transport.favorites, hasLength(1));
      expect(transport.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'smart removal explains notifications continue and where to stop them',
    (tester) async {
      await host(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  confirmSpaceSmartEventRemoval(context, [fixturePin(old)]),
              child: const Text('remove'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('remove'));
      await settle(tester);
      expect(
        find.textContaining('Starred events will still send notifications'),
        findsOneWidget,
      );
      expect(find.textContaining('Starred Smart Events'), findsOneWidget);
      expect(transport.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'builder exposes subscription management even with no saved cards',
    (tester) async {
      await host(
        tester,
        Scaffold(
          body: SmartEventBuilder(onToggle: (_) async {}, onDone: () {}),
        ),
      );
      expect(find.byTooltip('Starred Smart Events'), findsOneWidget);
      await tester.tap(find.byTooltip('Starred Smart Events'));
      await settle(tester);
      expect(find.byType(StarredSmartEventsScreen), findsOneWidget);
      expect(find.text(old.displayName), findsOneWidget);
      expect(transport.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<void> openEvent(
    WidgetTester tester, {
    bool starred = true,
    SmartEventRequest? subscribed,
  }) async {
    await host(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SmartEventScreen(request: old),
              ),
            ),
            child: const Text('open event'),
          ),
        ),
      ),
      starred: starred,
      subscribedRequest: subscribed,
      cards: [fixturePin(old)],
    );
    await tester.tap(find.text('open event'));
    await settle(tester);
  }

  Future<void> changeTier(WidgetTester tester) async {
    await tester.tap(find.text('FM+').first);
    await settle(tester);
    await tester.tap(find.text('Grandmaster · 2500+').last);
    await settle(tester);
  }

  Future<void> menu(WidgetTester tester) async {
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is AppBarIcons && w.image == SvgAsset.threeDots,
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'unstarred pinned event still has Apply; target star is not treated as source',
    (tester) async {
      await openEvent(tester, subscribed: old.withTierSelection('GM'));
      await changeTier(tester);
      await menu(tester);
      expect(find.textContaining('Apply changes to'), findsOneWidget);
      expect(find.text('Star saved event'), findsOneWidget);
      expect(
        find.text('Unstar saved event / stop notifications'),
        findsNothing,
      );
      expect(transport.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('discard and dismissed confirmation perform no persistence', (
    tester,
  ) async {
    await openEvent(tester);
    await changeTier(tester);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_outlined));
    await settle(tester);
    expect(find.text('Apply changes?'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await settle(tester);
    expect(find.byType(SmartEventScreen), findsOneWidget);
    expect(transport.writes, isEmpty);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_outlined));
    await settle(tester);
    await tester.tap(find.text('Discard'));
    await settle(tester);
    expect(find.byType(SmartEventScreen), findsNothing);
    expect(transport.writes, isEmpty);
    expect(
      container.read(spaceShortcutsProvider).requireValue.single.targetId,
      old.criteriaKey,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'failed Apply keeps screen dirty and saved baseline; retry saves and leaves',
    (tester) async {
      await openEvent(tester);
      await changeTier(tester);
      var fail = true;
      pins.beforeWrite = (_, _) async {
        if (fail) {
          fail = false;
          throw StateError('Fixture offline');
        }
      };
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_outlined));
      await settle(tester);
      await tester.tap(find.text('Apply & leave'));
      await settle(tester);
      expect(find.byType(SmartEventScreen), findsOneWidget);
      expect(
        find.textContaining('Could not save the Smart Event'),
        findsOneWidget,
      );
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.targetId,
        old.criteriaKey,
      );
      expect(transport.favorites.single.eventId, old.favoriteEventId);
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_outlined));
      await settle(tester);
      expect(find.text('Apply changes?'), findsOneWidget);
      await tester.tap(find.text('Apply & leave'));
      await settle(tester);
      expect(find.byType(SmartEventScreen), findsNothing);
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.targetId,
        old.withTierSelection('GM').criteriaKey,
      );
      expect(
        transport.favorites.single.eventId,
        old.withTierSelection('GM').favoriteEventId,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'subscription criteria describes pace/opening without inventing a rapid restriction',
    () {
      final opening = SmartEventRequest.forOpening(
        GameEcoFilter.forCode('B90'),
      );
      expect(
        smartEventSubscriptionCriteriaLabel(opening),
        contains('All time controls'),
      );
      final rapid = opening.withGameFilterOverrides(
        opening.seedGameFilter().copyWith(
          timeControl: GameTimeControlFilter.rapid,
        ),
      );
      expect(smartEventSubscriptionCriteriaLabel(rapid), contains('rapid'));
    },
  );
}
