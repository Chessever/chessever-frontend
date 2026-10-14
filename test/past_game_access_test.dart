import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart'
    show liveBroadcastIdsProvider;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/past_game_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

GroupBroadcast _broadcast(String id) => GroupBroadcast(
  id: id,
  createdAt: DateTime.utc(2000),
  name: 'Event $id',
  search: const [],
  dateStart: DateTime.utc(2000, 1, 1),
  dateEnd: DateTime.utc(2000, 1, 9),
);

GamesTourModel _game({
  String tourId = 'actual-tour',
  GameSource source = GameSource.supabase,
  String? tourSlug,
}) {
  PlayerCard player(String name) => PlayerCard(
    name: name,
    federation: '',
    title: '',
    rating: 0,
    countryCode: '',
    team: null,
  );
  return GamesTourModel(
    gameId: 'very-old-game',
    source: source,
    whitePlayer: player('White'),
    blackPlayer: player('Black'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.draw,
    roundId: 'round',
    tourId: tourId,
    tourSlug: tourSlug,
    gameDay: DateTime.utc(2000, 1, 5),
  );
}

TourDetailViewModel _matchingDetail({
  List<DateTime> dates = const [],
  List<String> liveTourIds = const [],
}) => TourDetailViewModel(
  aboutTourModel: AboutTourModel.empty(),
  liveTourIds: liveTourIds,
  tours: [
    TourModel(
      tour: Tour.virtual(
        id: 'actual-tour',
        name: 'Actual event',
        slug: 'actual-event',
        dates: dates,
        players: const [],
      ),
      roundStatus: RoundStatus.completed,
    ),
  ],
);

class _BroadcastRepository implements GroupBroadcastRepository {
  _BroadcastRepository({
    this.byId = const {},
    this.bySlug = const {},
    this.currentIds = const {},
    this.failCurrentLookup = false,
  });

  final Map<String, GroupBroadcast> byId;
  final Map<String, GroupBroadcast> bySlug;
  final Set<String> currentIds;
  final bool failCurrentLookup;
  final idReads = <String>[];
  final slugReads = <String>[];
  final currentReads = <List<String>>[];

  @override
  Future<GroupBroadcast> getGroupBroadcastById(String id) async {
    idReads.add(id);
    final broadcast = byId[id];
    if (broadcast == null) throw StateError('Unknown broadcast metadata');
    return broadcast;
  }

  @override
  Future<GroupBroadcast?> getGroupBroadcastBySlug(String slug) async {
    slugReads.add(slug);
    return bySlug[slug];
  }

  @override
  Future<List<GroupBroadcast>> getCurrentGroupBroadcastsByIds(
    List<String> ids,
  ) async {
    currentReads.add(List.of(ids));
    if (failCurrentLookup) throw StateError('Current membership unavailable');
    return [
      for (final id in ids)
        if (currentIds.contains(id)) _broadcast(id),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository call: ${invocation.memberName}');
}

Future<void> _settle(WidgetTester tester) async {
  for (var n = 0; n < 6; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 160));
  }
}

Future<List<bool>> _tapGame(
  WidgetTester tester, {
  required _BroadcastRepository repository,
  required GamesTourModel game,
  bool premium = false,
  bool publishedEventGame = false,
  GroupBroadcast? selected,
  TourDetailViewModel? detail,
}) async {
  final results = <bool>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        groupBroadcastRepositoryProvider.overrideWithValue(repository),
        premiumAccessProvider.overrideWithValue(premium),
        liveBroadcastIdsProvider.overrideWith((_) => const []),
        selectedBroadcastModelProvider.overrideWith((_) => selected),
        if (detail != null) tourDetailScreenProviderOverride(detail),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            ResponsiveHelper.init(context);
            if (detail != null) ref.watch(tourDetailScreenProvider);
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  results.add(
                    await ensurePastGameAccess(
                      context,
                      game: game,
                      publishedEventGame: publishedEventGame,
                    ),
                  );
                },
                child: const Text('Open actual game'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await _settle(tester);
  await tester.tap(find.text('Open actual game'));
  await _settle(tester);
  return results;
}

Future<void> _deny(WidgetTester tester, List<bool> results) async {
  expect(find.text('Sign in to get Premium'), findsOneWidget);
  expect(results, isEmpty);
  Navigator.of(tester.element(find.text('Sign in to get Premium'))).pop();
  await _settle(tester);
  expect(results, [false]);
  expect(tester.takeException(), isNull);
}

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

  group('gameNavigationForAccess', () {
    test('free mixed Supabase history keeps event and remaps selection', () {
      final games = [
        _game(tourId: 'other-event').copyWith(gameId: 'other-first'),
        _game().copyWith(gameId: 'admitted-first'),
        _game(tourId: 'another-event').copyWith(gameId: 'other-middle'),
        _game().copyWith(gameId: 'admitted-selected'),
        _game().copyWith(gameId: 'admitted-next'),
      ];

      final navigation = gameNavigationForAccess(
        games: games,
        index: 3,
        premium: false,
      );

      expect(navigation.games.map((game) => game.gameId), [
        'admitted-first',
        'admitted-selected',
        'admitted-next',
      ]);
      expect(navigation.index, 1);
      expect(navigation.games[navigation.index], same(games[3]));
    });

    test('known sibling tours stay in the admitted event navigation', () {
      final games = [
        _game(
          tourId: 'rapid',
          source: GameSource.gamebase,
        ).copyWith(gameId: 'same-tour-different-source'),
        _game(tourId: 'rapid').copyWith(gameId: 'rapid-first'),
        _game(tourId: 'unrelated-event').copyWith(gameId: 'unrelated'),
        _game(tourId: 'classical').copyWith(gameId: 'classical-selected'),
        _game(tourId: 'rapid').copyWith(gameId: 'rapid-next'),
      ];

      final navigation = gameNavigationForAccess(
        games: games,
        index: 3,
        premium: false,
        eventTourIds: const ['rapid', 'classical'],
      );

      expect(navigation.games.map((game) => game.gameId), [
        'rapid-first',
        'classical-selected',
        'rapid-next',
      ]);
      expect(navigation.index, 1);
      expect(navigation.games[navigation.index], same(games[3]));
    });

    test('paid or rewarded access retains the entire mixed list', () {
      final games = [
        _game(tourId: 'other-event').copyWith(gameId: 'other'),
        _game(source: GameSource.gamebase).copyWith(gameId: 'archive'),
        _game().copyWith(gameId: 'selected'),
      ];

      final navigation = gameNavigationForAccess(
        games: games,
        index: 2,
        premium: true,
      );

      expect(navigation.games, same(games));
      expect(navigation.index, 2);
    });

    test('ordinary Gamebase event-name ambiguity admits only tapped game', () {
      final games = [
        _game(
          tourId: 'Annual Open',
          source: GameSource.gamebase,
        ).copyWith(gameId: 'earlier-edition', gameDay: DateTime.utc(1999)),
        _game(
          tourId: 'Annual Open',
          source: GameSource.gamebase,
        ).copyWith(gameId: 'admitted-edition', gameDay: DateTime.utc(2026)),
        _game(
          tourId: 'Annual Open',
          source: GameSource.gamebase,
        ).copyWith(gameId: 'another-edition', gameDay: DateTime.utc(2005)),
      ];

      final navigation = gameNavigationForAccess(
        games: games,
        index: 1,
        premium: false,
        eventTourIds: const ['Annual Open'],
      );

      expect(navigation.games, [games[1]]);
      expect(navigation.index, 0);
    });
  });

  testWidgets(
    'very old Supabase game in Current opens with no selected event',
    (tester) async {
      final repository = _BroadcastRepository(
        byId: {'actual-tour': _broadcast('actual-group')},
        currentIds: {'actual-group'},
      );
      final results = await _tapGame(
        tester,
        repository: repository,
        game: _game(),
      );

      expect(results, [true]);
      expect(find.text('Sign in to get Premium'), findsNothing);
      expect(repository.idReads, ['actual-tour']);
      expect(repository.currentReads, [
        ['actual-group'],
      ]);
      expect(repository.slugReads, isEmpty);
    },
  );

  testWidgets('past game outside Current prompts without selected context', (
    tester,
  ) async {
    final repository = _BroadcastRepository(
      byId: {'actual-tour': _broadcast('actual-group')},
    );
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(),
    );

    await _deny(tester, results);
    expect(repository.currentReads, [
      ['actual-group'],
    ]);
  });

  testWidgets('unrelated selected past event cannot gate a Current game', (
    tester,
  ) async {
    final repository = _BroadcastRepository(
      byId: {'actual-tour': _broadcast('actual-group')},
      currentIds: {'actual-group'},
    );
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(),
      selected: _broadcast('unrelated-past-group'),
      detail: TourDetailViewModel(
        aboutTourModel: AboutTourModel.empty(),
        liveTourIds: const [],
        tours: [
          TourModel(
            tour: Tour.virtual(
              id: 'unrelated-tour',
              name: 'Past event',
              slug: 'unrelated-past',
              dates: [DateTime.utc(2000, 1, 1), DateTime.utc(2000, 1, 9)],
              players: const [],
            ),
            roundStatus: RoundStatus.completed,
          ),
        ],
      ),
    );

    expect(results, [true]);
    expect(find.text('Sign in to get Premium'), findsNothing);
    expect(repository.idReads, ['actual-tour']);
    expect(repository.currentReads, [
      ['actual-group'],
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paid or rewarded access opens before metadata lookups', (
    tester,
  ) async {
    final repository = _BroadcastRepository();
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(source: GameSource.gamebase),
      premium: true,
    );

    expect(results, [true]);
    expect(repository.idReads, isEmpty);
    expect(repository.slugReads, isEmpty);
    expect(repository.currentReads, isEmpty);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('unknown Supabase event metadata preserves free game access', (
    tester,
  ) async {
    final repository = _BroadcastRepository();
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(tourSlug: 'unknown-slug'),
    );

    expect(results, [true]);
    expect(repository.idReads, ['actual-tour']);
    expect(repository.slugReads, isEmpty);
    expect(repository.currentReads, isEmpty);
    expect(find.text('Sign in to get Premium'), findsNothing);
  });

  testWidgets('unknown Current membership cannot prove that a game is past', (
    tester,
  ) async {
    final repository = _BroadcastRepository(
      byId: {'actual-tour': _broadcast('actual-group')},
      failCurrentLookup: true,
    );
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(),
    );

    expect(results, [true]);
    expect(repository.currentReads, [
      ['actual-group'],
    ]);
    expect(find.text('Sign in to get Premium'), findsNothing);
  });

  testWidgets('Gamebase slug resolves a Current broadcast despite old dates', (
    tester,
  ) async {
    final repository = _BroadcastRepository(
      bySlug: {'event-slug': _broadcast('actual-group')},
      currentIds: {'actual-group'},
    );
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(source: GameSource.gamebase, tourSlug: 'event-slug'),
    );

    expect(results, [true]);
    expect(repository.idReads, ['actual-tour']);
    expect(repository.slugReads, ['event-slug']);
    expect(repository.currentReads, [
      ['actual-group'],
    ]);
    expect(find.text('Sign in to get Premium'), findsNothing);
  });

  testWidgets('unresolved Gamebase archive preserves its Premium prompt', (
    tester,
  ) async {
    final repository = _BroadcastRepository();
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(source: GameSource.gamebase, tourSlug: 'unresolved-event'),
    );

    await _deny(tester, results);
    expect(repository.idReads, ['actual-tour']);
    expect(repository.slugReads, ['unresolved-event', 'actual-tour']);
    expect(repository.currentReads, isEmpty);
  });

  for (final current in [false, true]) {
    testWidgets(
      'undated selected event with old game ${current ? 'opens when Current' : 'prompts outside Current'}',
      (tester) async {
        final repository = _BroadcastRepository(
          currentIds: current ? {'selected-undated'} : const {},
        );
        final results = await _tapGame(
          tester,
          repository: repository,
          game: _game(),
          selected: GroupBroadcast(
            id: 'selected-undated',
            createdAt: DateTime.utc(2000),
            name: 'Undated event',
            search: const [],
          ),
          detail: _matchingDetail(),
        );

        if (current) {
          expect(results, [true]);
          expect(find.text('Sign in to get Premium'), findsNothing);
        } else {
          await _deny(tester, results);
        }
        expect(repository.idReads, isEmpty);
        expect(repository.currentReads, [
          ['selected-undated'],
        ]);
      },
    );
  }

  testWidgets('annual archive name cannot borrow the modern Current edition', (
    tester,
  ) async {
    final now = DateTime.now();
    final modernEdition = GroupBroadcast(
      id: 'modern-annual-open',
      createdAt: now,
      name: 'Annual Open',
      search: const [],
      dateStart: now.subtract(const Duration(days: 1)),
      dateEnd: now.add(const Duration(days: 1)),
    );
    final repository = _BroadcastRepository(
      bySlug: {'Annual Open': modernEdition},
      currentIds: {'modern-annual-open'},
    );
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(tourId: 'Annual Open', source: GameSource.gamebase),
    );

    await _deny(tester, results);
    expect(repository.slugReads, ['Annual Open']);
    expect(repository.currentReads, isEmpty);
  });

  testWidgets('stale detail live tour flag cannot unlock a past game', (
    tester,
  ) async {
    final repository = _BroadcastRepository();
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(),
      selected: _broadcast('selected-past'),
      detail: _matchingDetail(liveTourIds: ['actual-tour']),
    );

    await _deny(tester, results);
    expect(repository.idReads, isEmpty);
    expect(repository.currentReads, [
      ['selected-past'],
    ]);
  });

  testWidgets('published collection analysis game keeps the archive gate', (
    tester,
  ) async {
    final repository = _BroadcastRepository();
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(source: GameSource.localAnalysis),
      publishedEventGame: true,
    );

    await _deny(tester, results);
    expect(repository.idReads, ['actual-tour']);
  });

  testWidgets('personal analysis keeps free access with no metadata lookup', (
    tester,
  ) async {
    final repository = _BroadcastRepository();
    final results = await _tapGame(
      tester,
      repository: repository,
      game: _game(source: GameSource.localAnalysis),
    );

    expect(results, [true]);
    expect(repository.idReads, isEmpty);
    expect(repository.slugReads, isEmpty);
    expect(repository.currentReads, isEmpty);
    expect(find.text('Sign in to get Premium'), findsNothing);
  });
}
