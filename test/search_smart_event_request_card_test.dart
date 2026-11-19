import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart'
    show kSpaceSmartFormatPresets;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/search/search_page_sections.dart'
    show SearchSmartEventGrid;
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/smart_event_board_window.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_request_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_star.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:dartchess/dartchess.dart' show Square;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A smart event drawn from its request alone, as My Space draws a saved
/// one: the shared card, its star, its long-press with My Space, and a tap
/// that opens the smart event.
void main() {
  final sicilian = SmartEventRequest.forOpeningSelection(
    searchOpeningSuggestions('Sicilian', limit: 1).single.selection,
  );
  final gm = kGmSmartPreset;

  test('the presets are Super GM, GM and IM, strongest first', () {
    expect(
      [for (final p in kDiscoverySmartPresets) p.displayName],
      ['Super GM Games', 'GM Games', 'IM Games'],
    );
    expect(kSuperGmSmartPreset.minElo, 2700);
    expect(kSuperGmSmartPreset.caption, 'Every game averaging 2700+');
    expect(gm.minElo, 2500);
  });

  testWidgets('a tier smart event names its floor, never a count every tier '
      'would share', (tester) async {
    await _pump(
      tester,
      gm,
      members: [_member('a', 2700), _member('b', 2600), _member('c', 0)],
    );
    final card = tester.widget<SmartEventCard>(find.byType(SmartEventCard));
    // Membership cannot see a game's rating: Super GM, GM and IM would all
    // print the same number of events.
    expect(card.metaText, 'Game average 2500+');
    expect(card.liveCount, 0);
    expect(card.avgElo, 0);
    expect(card.summary, 'Grandmaster level');
    expect(card.starRequest?.criteriaKey, gm.criteriaKey);
    expect(card.spaceDraft?.kind, SpaceShortcutKind.smartEvent);
    expect(find.byType(SmartEventStar), findsOneWidget);
    expect(find.text('Game average 2500+'), findsOneWidget);
    expect(find.textContaining('events', findRichText: true), findsNothing);
  });

  testWidgets('Super GM Games: the 2700 floor and its king', (tester) async {
    await _pump(tester, kSuperGmSmartPreset, members: [_member('a', 2700)]);
    final card = tester.widget<SmartEventCard>(find.byType(SmartEventCard));
    expect(find.text('Super GM Games'), findsOneWidget);
    expect(card.metaText, 'Game average 2700+');
    expect(card.summary, 'Super Grandmaster level');
    final window = tester.widget<SmartEventBoardWindow>(
      find.byType(SmartEventBoardWindow),
    );
    expect(window.fen, startsWith('8/8/8/8/8/8/8/4K3'));
  });

  testWidgets('a time control alone still counts its events', (tester) async {
    final classical = kSpaceSmartFormatPresets.first;
    await _pump(
      tester,
      classical,
      members: [_member('a', 2700), _member('b', 2600), _member('c', 0)],
    );
    final card = tester.widget<SmartEventCard>(find.byType(SmartEventCard));
    expect(card.metaText, isNull);
    expect(card.liveCount, 3);
    expect(card.avgElo, 2650);
    expect(find.textContaining('3 events', findRichText: true), findsOneWidget);
  });

  testWidgets('an opening names what it covers, never a number of events', (
    tester,
  ) async {
    // Even with current events around: they are not this opening's.
    await _pump(tester, sicilian, members: [_member('a', 2700)]);
    final card = tester.widget<SmartEventCard>(find.byType(SmartEventCard));
    // The codes it covers, not a count passed off as events, and the
    // thinnest deck on its plate whatever the family's size.
    expect(card.metaText, 'ECO B20-B99');
    expect(card.deckEvents, 1);
    expect(card.liveCount, 0);
    expect(card.avgElo, 0);
    expect(find.text('ECO B20-B99'), findsOneWidget);
    expect(find.textContaining('event', findRichText: true), findsNothing);
    // Its last line is its moves, not its codes a second time.
    final moves = sicilian.openingContext!.movePath;
    expect(moves, isNotEmpty);
    expect(card.summary, formatOpeningMovePath(moves));
    expect(card.summary, isNot(contains('B20')));
    expect(find.text(card.summary!), findsOneWidget);
    // Its plate shows the position its line reaches, ...c5 marked.
    expect(card.opening?.moves, moves);
    final window = tester.widget<SmartEventBoardWindow>(
      find.byType(SmartEventBoardWindow),
    );
    expect(window.marks, {Square.c7, Square.c5});
  });

  test('an opening\'s last line: other criteria first, else its moves, '
      'else what it gathers', () {
    final withMoves = SmartEventRequest.forOpening(
      GameEcoFilter.forFamily('B9'),
      openingContext: SmartEventOpeningContext(
        hierarchyLabel: 'Sicilian Defense: Najdorf Variation',
        movePath: const ['e4', 'c5', 'Nf3', 'd6'],
        isAggregate: true,
      ),
    );
    expect(smartEventOpeningCaption(withMoves), '1. e4 c5 2. Nf3 d6');
    final bare = SmartEventRequest.forOpening(GameEcoFilter.forCode('B90'));
    expect(smartEventOpeningCaption(bare), 'Current games in this opening');
  });

  testWidgets('a tap opens the smart event on its request', (tester) async {
    final observer = _Pushes();
    await _pump(tester, sicilian, observer: observer);
    await tester.tap(find.byType(SmartEventCard));
    await tester.pump();
    final route = observer.routes.last as MaterialPageRoute<dynamic>;
    final screen = route.builder(tester.element(find.byType(Scaffold).first));
    expect(screen, isA<SmartEventScreen>());
    expect(
      (screen as SmartEventScreen).request.criteriaKey,
      sicilian.criteriaKey,
    );
  });

  testWidgets('a card that opens without Filters opens its smart event so', (
    tester,
  ) async {
    final observer = _Pushes();
    await _pump(tester, gm, observer: observer, showFilters: false);
    await tester.tap(find.byType(SmartEventCard));
    await tester.pump();
    final route = observer.routes.last as MaterialPageRoute<dynamic>;
    final screen = route.builder(tester.element(find.byType(Scaffold).first));
    expect((screen as SmartEventScreen).showFilters, isFalse);
  });

  testWidgets('onTap takes the open instead', (tester) async {
    final observer = _Pushes();
    var taps = 0;
    await _pump(tester, sicilian, observer: observer, onTap: () => taps++);
    final before = observer.routes.length;
    await tester.tap(find.byType(SmartEventCard));
    await tester.pump();
    expect(taps, 1);
    expect(observer.routes.length, before);
  });

  testWidgets('its long-press opens the smart event or keeps it in My Space', (
    tester,
  ) async {
    var taps = 0;
    await _pump(tester, sicilian, onTap: () => taps++);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SmartEventCard)),
    );
    await tester.longPress(find.byType(SmartEventCard));
    await tester.pumpAndSettle();
    expect(find.text('Open smart event'), findsOneWidget);
    await tester.tap(find.text('Add to My Space'));
    await tester.pumpAndSettle();
    final saved = container.read(spaceShortcutsProvider).requireValue.single;
    expect(saved.kind, SpaceShortcutKind.smartEvent);
    expect(saved.targetId, sicilian.criteriaKey);

    await tester.longPress(find.byType(SmartEventCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open smart event'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('Search\'s grid: Super GM leads on the grid of GM and IM, '
      'whose plates fill their half cards; its plate is theirs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      gm,
      child: SearchSmartEventGrid(
        requests: kDiscoverySmartPresets,
        leadFullWidth: true,
      ),
    );
    final cards = tester
        .widgetList<SmartEventCard>(find.byType(SmartEventCard))
        .toList();
    expect([for (final c in cards) c.tierLabel], ['Super GM', 'GM', 'IM']);
    expect(cards.first.stacked, isFalse);
    expect(cards.first.lead, isNotNull);
    for (final half in cards.skip(1)) {
      expect(half.stacked, isTrue);
      expect(half.fillPlate, isTrue);
    }
    final plates = [
      for (final e in find.byType(SmartEventPlate).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];
    expect(plates, hasLength(3));
    expect(plates[0].width, moreOrLessEquals(plates[1].width));
    expect(plates[0].left, moreOrLessEquals(plates[1].left));
    expect(plates[1].width, moreOrLessEquals(plates[2].width));
    expect(plates[0].width, greaterThan(108.w));
    expect(tester.takeException(), isNull);
  });

  testWidgets('star off: no star and no chevron', (tester) async {
    await _pump(tester, gm, star: false);
    final card = tester.widget<SmartEventCard>(find.byType(SmartEventCard));
    expect(card.starRequest, isNull);
    expect(card.disclosure, isFalse);
    expect(find.byType(SmartEventStar), findsNothing);
  });
}

class _Pushes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
}

GroupEventCardModel _member(String id, int elo) => GroupEventCardModel(
  id: id,
  title: 'Event $id',
  dates: '',
  maxAvgElo: elo,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.ongoing,
  timeControl: 'Standard',
  startDate: null,
  endDate: null,
);

Future<void> _pump(
  WidgetTester tester,
  SmartEventRequest request, {
  List<GroupEventCardModel> members = const [],
  NavigatorObserver? observer,
  VoidCallback? onTap,
  bool star = true,
  bool showFilters = true,
  Widget? child,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        discoverySmartEventMembersProvider.overrideWith(
          (ref, criteria) async => members,
        ),
        liveGroupBroadcastIdsProvider.overrideWith(
          (ref) => Stream.value(const <String>[]),
        ),
        favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
        spaceShortcutsProvider.overrideWith(_MemorySpaceShortcuts.new),
        boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        navigatorObservers: [?observer],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child:
                      child ??
                      SmartEventRequestCard(
                        request: request,
                        onTap: onTap,
                        star: star,
                        showFilters: showFilters,
                      ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];
}

class _MemorySpaceShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];

  @override
  Future<bool> add(SpaceShortcut draft) async {
    final list = state.requireValue;
    if (!draft.canAddToMySpace || list.any((s) => s.key == draft.key)) {
      return false;
    }
    state = AsyncData([draft, ...list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> remove(String id) async {
    final list = state.requireValue;
    final removed = list.where((s) => s.id == id).firstOrNull;
    state = AsyncData([
      for (final s in list)
        if (s.id != id) s,
    ]);
    return removed;
  }

  @override
  Future<void> restore(SpaceShortcut item) async {
    state = AsyncData([item, ...state.requireValue]);
  }
}
