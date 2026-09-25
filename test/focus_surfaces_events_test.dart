import 'package:chessever2/providers/event_mute_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/round_space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Event surfaces on the shared focus menu: an event card lifts itself and
/// keeps every action its old popup had (plus Open and My Space),
/// the round / event pins carry the fields their openers need, and teams
/// are shared, never pinned (older team pins still open).

/// My Space store double: in memory, never touches SQLite or Supabase.
class _MemorySpaceShortcuts extends SpaceShortcutsNotifier {
  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => const [];

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (_list.any((s) => s.key == draft.key)) return false;
    state = AsyncData([draft, ..._list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    SpaceShortcut? hit;
    for (final s in _list) {
      if (s.key == key) hit = s;
    }
    state = AsyncData([
      for (final s in _list)
        if (s.key != key) s,
    ]);
    return hit;
  }

  @override
  Future<void> restore(SpaceShortcut item) async {
    state = AsyncData([item, ..._list]);
  }
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];
}

/// No Spoilers double: never reads the local database.
class _MemoryNoSpoilers extends EventNoSpoilersController {
  _MemoryNoSpoilers(Ref ref, String tourId) : super(ref: ref, tourId: tourId);

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    state = EventNoSpoilersState(enabled: enabled, isLoading: false);
  }
}

class _NotMuted extends EventMuteNotifier {
  @override
  Future<bool> build(String arg) async => false;
}

class _TourIdsRepository implements GroupBroadcastRepository {
  int tourIdLookups = 0;

  @override
  Future<List<String>> getTourIdsForGroupBroadcast(
    String groupBroadcastId,
  ) async {
    tourIdLookups++;
    return const ['tour-1'];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupEventCardModel _broadcastEvent() {
  final start = DateTime(2026, 8, 1);
  final end = DateTime(2026, 8, 9);
  return GroupEventCardModel(
    id: 'group-1',
    title: 'Sinquefield Cup 2026',
    dates: 'Aug 1 - 9, 2026',
    maxAvgElo: 2760,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.completed,
    timeControl: '90+30',
    startDate: start,
    endDate: end,
  );
}

GroupEventCardModel _calendarEvent() {
  return GroupEventCardModel(
    id: 'cal_event_fide_grand_swiss_2026',
    title: 'FIDE Grand Swiss 2026',
    dates: 'Oct 3 - 16, 2026',
    maxAvgElo: 0,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.upcoming,
    timeControl: 'Classical',
    startDate: DateTime(2026, 10, 3),
    endDate: DateTime(2026, 10, 16),
    location: 'Samarkand, Uzbekistan',
    eventSource: EventSource.communityEvent,
    isMajorUpcoming: true,
  );
}

const _about = AboutTourModel(
  id: 'tour-1',
  slug: 'sinquefield-cup-2026',
  name: 'Sinquefield Cup 2026',
  description: '',
  imageUrl: '',
  players: [],
  timeControl: '90+30',
  date: 'Aug 1 - 9, 2026',
  location: 'Saint Louis',
  websiteUrl: '',
  standingsUrl: '',
  tourUrl: '',
  groupBroadcastId: 'group-1',
);

final _round = GamesAppBarModel(
  id: 'round-5',
  name: 'Round 5',
  startsAt: DateTime(2026, 8, 5, 19),
  roundStatus: RoundStatus.completed,
  sourceRoundIds: const ['round-5'],
);

Widget _host({required List<Override> overrides, required Widget child}) {
  return ProviderScope(
    overrides: [
      spaceShortcutsProvider.overrideWith(_MemorySpaceShortcuts.new),
      favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
      eventImageProvider.overrideWith(
        (ref, id) async => const EventImageData(),
      ),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _MemoryNoSpoilers(ref, tourId),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), devicePixelRatio: 3),
        child: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(alignment: Alignment.topCenter, child: child),
              ),
            );
          },
        ),
      ),
    ),
  );
}

List<SpaceShortcut> _stored(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  return container.read(spaceShortcutsProvider).valueOrNull ?? const [];
}

/// Lets the snack the My Space row raises time out, so no timer outlives the
/// test.
Future<void> _drainSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

void main() {
  group('event card focus menu', () {
    testWidgets(
      'long-press lifts the card and keeps every old action plus My Space',
      (tester) async {
        final repo = _TourIdsRepository();
        var opened = 0;
        await tester.pumpWidget(
          _host(
            overrides: [
              groupBroadcastRepositoryProvider.overrideWithValue(repo),
            ],
            child: EventCard(
              tourEventCardModel: _broadcastEvent(),
              favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
              heroTagSuffix: 'test',
              onTap: () => opened++,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.longPress(find.byType(EventCard));
        await tester.pumpAndSettle();

        // The card itself is the preview: a second, inert copy of it rises
        // above the actions (hero suffix switched so it can never fly).
        expect(find.text('Sinquefield Cup 2026'), findsNWidgets(2));
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is EventCard &&
                w.heroTagSuffix == 'test-menu' &&
                w.onTap == null,
          ),
          findsOneWidget,
        );

        // Every row the old popup had, with the same labels...
        expect(find.text('Turn on No Spoilers'), findsOneWidget);
        expect(find.text('Share'), findsOneWidget);
        expect(find.text('Copy PGN'), findsOneWidget);
        // ...plus Open and the My Space row. Favoriting is the card's own
        // star, never a menu row.
        expect(find.text('Open event'), findsOneWidget);
        expect(find.text('Add to favorites'), findsNothing);
        expect(find.text('Add to My Space'), findsOneWidget);
        expect(repo.tourIdLookups, 1);

        await tester.tap(find.text('Add to My Space'));
        await tester.pumpAndSettle();

        final stored = _stored(tester);
        expect(stored, hasLength(1));
        expect(stored.single.kind, SpaceShortcutKind.event);
        expect(stored.single.targetId, 'group-1');
        expect(stored.single.title, 'Sinquefield Cup 2026');
        expect(opened, 0);
        await _drainSnack(tester);

        // Reopening reads live state: the row flips to Remove, and the tour
        // lookup is reused instead of asked again.
        await tester.longPress(find.byType(EventCard).first);
        await tester.pumpAndSettle();
        expect(find.text('Remove from My Space'), findsOneWidget);
        expect(repo.tourIdLookups, 1);

        await tester.tap(find.text('Open event'));
        await tester.pumpAndSettle();
        expect(opened, 1);
      },
    );

    testWidgets(
      'calendar events keep only their non-broadcast rows and pin with '
      'their calendar identity',
      (tester) async {
        final repo = _TourIdsRepository();
        await tester.pumpWidget(
          _host(
            overrides: [
              groupBroadcastRepositoryProvider.overrideWithValue(repo),
            ],
            child: EventCard(
              tourEventCardModel: _calendarEvent(),
              favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
              heroTagSuffix: 'test',
              onTap: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.longPress(find.byType(EventCard));
        await tester.pumpAndSettle();

        expect(find.text('Open event'), findsOneWidget);
        expect(find.text('Add to favorites'), findsNothing);
        expect(find.text('Add to My Space'), findsOneWidget);
        expect(find.text('Share'), findsNothing);
        expect(find.text('Copy PGN'), findsNothing);
        expect(find.textContaining('No Spoilers'), findsNothing);
        // A calendar event has no tours to look up.
        expect(repo.tourIdLookups, 0);

        await tester.tap(find.text('Add to My Space'));
        await tester.pumpAndSettle();
        final pin = _stored(tester).single;
        expect(pin.kind, SpaceShortcutKind.event);
        expect(pin.targetId, 'cal_event_fide_grand_swiss_2026');
        expect(pin.params['source'], 'calendar');
        expect(
          pin.params['calendarEventId'],
          'cal_event_fide_grand_swiss_2026',
        );
        expect(pin.params['calendarEventName'], 'FIDE Grand Swiss 2026');
        expect(pin.params['eventSource'], 'communityEvent');
        await _drainSnack(tester);
      },
    );
  });

  group('round pins', () {
    test('round draft carries what the round opener needs', () {
      final draft = roundSpaceDraft(
        round: _round,
        tourId: 'tour-1',
        groupBroadcastId: 'group-1',
        eventName: 'Sinquefield Cup 2026',
      )!;
      expect(draft.kind, SpaceShortcutKind.round);
      expect(draft.targetId, 'round-5');
      expect(draft.title, 'Round 5');
      expect(draft.subtitle, 'Sinquefield Cup 2026');
      expect(draft.params, {
        'tourId': 'tour-1',
        'groupBroadcastId': 'group-1',
        'eventName': 'Sinquefield Cup 2026',
      });
    });

    test('a synthetic knockout stage keeps its real rounds alongside', () {
      final stage = GamesAppBarModel(
        id: 'knockout-stage-tour-1-final',
        name: 'Final',
        startsAt: null,
        roundStatus: RoundStatus.completed,
        sourceRoundIds: const ['r-a', 'r-b'],
      );
      final draft = roundSpaceDraft(round: stage, tourId: 'tour-1')!;
      expect(draft.targetId, 'knockout-stage-tour-1-final');
      expect(draft.params['tourId'], 'tour-1');
      expect(draft.params['sourceRoundIds'], ['r-a', 'r-b']);
    });

    test('no pin for gamebase-only events or rounds with nowhere to open', () {
      expect(
        roundSpaceDraft(round: _round, tourId: 'gamebase::Tata Steel 2024'),
        isNull,
      );
      expect(roundSpaceDraft(round: _round, tourId: null), isNull);
    });

    testWidgets('round header long-press pins the round into My Space', (
      tester,
    ) async {
      var toggles = 0;
      await tester.pumpWidget(
        _host(
          overrides: [
            tourDetailScreenProviderOverride(
              const TourDetailViewModel(
                aboutTourModel: _about,
                liveTourIds: [],
                tours: [],
              ),
            ),
            selectedBroadcastModelProvider.overrideWith(
              (ref) => GroupBroadcast(
                id: 'group-1',
                createdAt: DateTime(2026, 7, 1),
                name: 'Sinquefield Cup 2026',
                search: const [],
              ),
            ),
          ],
          child: RoundHeader(
            round: _round,
            roundGames: const [],
            onToggle: () => toggles++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(RoundHeader));
      await tester.pumpAndSettle();

      expect(find.text('Collapse round'), findsOneWidget);
      expect(find.text('Add round to My Space'), findsOneWidget);

      await tester.tap(find.text('Add round to My Space'));
      await tester.pumpAndSettle();

      final pin = _stored(tester).single;
      expect(pin.kind, SpaceShortcutKind.round);
      expect(pin.targetId, 'round-5');
      expect(pin.title, 'Round 5');
      expect(pin.subtitle, 'Sinquefield Cup 2026');
      expect(pin.params['tourId'], 'tour-1');
      expect(pin.params['groupBroadcastId'], 'group-1');
      expect(pin.params['eventName'], 'Sinquefield Cup 2026');
      // Long-press never folds the round; only the tap does.
      expect(toggles, 0);
      await _drainSnack(tester);
    });
  });

  group('event 3-dot', () {
    List<Override> aboutTab(GroupBroadcast broadcast, AboutTourModel about) => [
      tourDetailScreenProviderOverride(
        TourDetailViewModel(
          aboutTourModel: about,
          liveTourIds: const [],
          tours: const [],
        ),
      ),
      selectedBroadcastModelProvider.overrideWith((ref) => broadcast),
      selectedTourModeProvider.overrideWith(
        (ref) => TournamentDetailScreenMode.about,
      ),
      eventMuteProvider.overrideWith(_NotMuted.new),
      isTeamEventProvider.overrideWith((ref, id) => false),
      knockoutTournamentStateProvider.overrideWith(
        (ref, id) => const KnockoutTournamentState.empty(),
      ),
    ];

    testWidgets('keeps its rows and adds the event to My Space', (
      tester,
    ) async {
      final broadcast = GroupBroadcast(
        id: 'group-1',
        createdAt: DateTime(2026, 7, 1),
        name: 'Sinquefield Cup 2026',
        search: const [],
      );
      await tester.pumpWidget(
        _host(
          overrides: aboutTab(broadcast, _about),
          child: const TournamentMenuButton(
            tourData: TourDetailViewModel(
              aboutTourModel: _about,
              liveTourIds: [],
              tours: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TournamentMenuButton));
      await tester.pumpAndSettle();

      // Same rows as before on the About tab, same labels.
      expect(find.text('Disable notifications'), findsOneWidget);
      expect(find.text('Share event'), findsOneWidget);
      // Games-tab rows stay on the Games tab.
      expect(find.text('Pin all'), findsNothing);
      expect(find.text('Add event to My Space'), findsOneWidget);

      await tester.tap(find.text('Add event to My Space'));
      await tester.pumpAndSettle();
      final pin = _stored(tester).single;
      expect(pin.key, eventSpaceDraft(_broadcastEvent()).key);
      expect(pin.params['tourId'], 'tour-1');
      await _drainSnack(tester);
    });

    testWidgets('pins a gamebase-only virtual event by its virtual id', (
      tester,
    ) async {
      const virtualAbout = AboutTourModel(
        id: 'gamebase::Tata Steel 2024',
        slug: '',
        name: 'Tata Steel 2024',
        description: '',
        imageUrl: '',
        players: [],
        timeControl: '',
        date: '',
        location: '',
        websiteUrl: '',
        standingsUrl: '',
        tourUrl: '',
        groupBroadcastId: 'gamebase::Tata Steel 2024',
      );
      await tester.pumpWidget(
        _host(
          overrides: aboutTab(
            GroupBroadcast(
              id: 'gamebase::Tata Steel 2024',
              createdAt: DateTime(2026, 7, 1),
              name: 'Tata Steel 2024',
              search: const [],
            ),
            virtualAbout,
          ),
          child: const TournamentMenuButton(
            tourData: TourDetailViewModel(
              aboutTourModel: virtualAbout,
              liveTourIds: [],
              tours: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TournamentMenuButton));
      await tester.pumpAndSettle();

      expect(find.text('Share event'), findsOneWidget);
      expect(find.text('Add event to My Space'), findsOneWidget);

      await tester.tap(find.text('Add event to My Space'));
      await tester.pumpAndSettle();
      final pin = _stored(tester).single;
      expect(pin.kind, SpaceShortcutKind.event);
      expect(pin.targetId, 'gamebase::Tata Steel 2024');
      expect(pin.title, 'Tata Steel 2024');
      // A virtual tour id is not a tour the opener could preselect.
      expect(pin.params.containsKey('tourId'), isFalse);
      await _drainSnack(tester);
    });
  });

  group('event pins and team menus', () {
    test('the event 3-dot pin dedupes with the card, keeps the category', () {
      final broadcast = GroupBroadcast(
        id: 'group-1',
        createdAt: DateTime(2026, 7, 1),
        name: 'Sinquefield Cup 2026',
        search: const [],
      );
      final draft =
          tournamentEventSpaceDraft(broadcast: broadcast, about: _about)!;
      expect(draft.key, eventSpaceDraft(_broadcastEvent()).key);
      expect(draft.params['tourId'], 'tour-1');
    });

    test('no round pin inside a gamebase-only virtual event', () {
      expect(
        roundSpaceDraft(
          round: _round,
          tourId: 'gamebase::Tata Steel 2024',
          groupBroadcastId: 'gamebase::Tata Steel 2024',
        ),
        isNull,
      );
    });

    testWidgets('a team menu opens and shares the team, never pins it', (
      tester,
    ) async {
      late List<String> single;
      late List<String> matchup;
      await tester.pumpWidget(
        _host(
          overrides: [
            tourDetailScreenProviderOverride(
              const TourDetailViewModel(
                aboutTourModel: _about,
                liveTourIds: [],
                tours: [],
              ),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              single = [
                for (final a in teamMenuActions(
                  context: context,
                  ref: ref,
                  teamName: 'Norway',
                  onOpen: () {},
                ))
                  a.label,
              ];
              matchup = [
                for (final name in ['Norway', 'India'])
                  for (final a in teamMenuActions(
                    context: context,
                    ref: ref,
                    teamName: name,
                    onOpen: () {},
                    includeShare: false,
                    nameInLabels: true,
                  ))
                    a.label,
              ];
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(single, ['Open team scorecard', 'Share link']);
      expect(matchup, ['Open Norway', 'Open India']);
      expect(
        [...single, ...matchup].where((l) => l.contains('My Space')),
        isEmpty,
      );
    });

    // Nothing pins a team any more, but older builds stored team pins as
    // this team page link, and those pins keep opening the team scorecard.
    test('an older team pin still opens its team scorecard', () {
      final url = teamPageShareUrl(about: _about, teamName: 'Norway')!;
      expect(
        url,
        'https://chessever.com/broadcast/sinquefield-cup-2026/tour-1'
        '/team/Norway',
      );
      final uri = Uri.parse(url);
      expect(isRoutableSpaceLink(uri), isTrue);
      final target = spaceBroadcastLinkTarget(uri)!;
      expect(target.eventId, 'tour-1');
      expect(target.teamName, 'Norway');
      expect(target.playerFideId, isNull);
    });
  });
}
