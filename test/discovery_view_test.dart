import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_tile_board.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/discovery_view.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/for_you/discovery/reports_screen.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/hub_context_art.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_controls.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/board_like_heart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------- doubles

/// Streak wall double: fixture rows, no SQLite, no network.
class _FakeWall extends StreakWallNotifier {
  _FakeWall(this._rows);

  final List<StreakRow> _rows;

  @override
  Future<List<StreakRow>> build() async => _rows;

  @override
  Future<void> refresh() async {}

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

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

/// Engine settings without SharedPreferences: the game cards read them.
class _EngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// No Spoilers off, without a Supabase read.
class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _HiddenSpoilers extends EventNoSpoilersController {
  _HiddenSpoilers({required super.ref, required super.tourId});
  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: true, isLoading: false);
  }
}

CloudEval _eval(String fen) => CloudEval(
  fen: fen,
  knodes: 0,
  depth: 20,
  pvs: [Pv(moves: 'e2e4', cp: 40)],
  requestedMultiPv: 1,
);

StreakRow _row(
  int fideId,
  StreakTimeClass tc,
  String name,
  int streak, {
  int? rating = 2700,
}) {
  return StreakRow(
    fideId: fideId,
    timeClass: tc,
    name: name,
    title: 'GM',
    fed: 'IND',
    rating: rating,
    currentStreak: streak,
    bestStreak: streak,
  );
}

final _wall = <StreakRow>[
  _row(1, StreakTimeClass.standard, 'Gujrathi, Vidit', 14, rating: 2727),
  _row(2, StreakTimeClass.standard, 'Abdusattorov, Nodirbek', 7, rating: 2762),
  // Under the 2400 floor: never on the Discovery rail.
  _row(3, StreakTimeClass.standard, 'Young, Prodigy', 9, rating: 1900),
  _row(4, StreakTimeClass.rapid, 'Nakamura, Hikaru', 8, rating: 2750),
  _row(5, StreakTimeClass.blitz, 'So, Wesley', 6, rating: 2760),
];

GamesTourModel _game(
  String id, {
  String? fen,
  String? lastMove,
  String? pgn,
  String tourId = 'tour-1',
  GameSource source = GameSource.supabase,
  int whiteRating = 2700,
  int blackRating = 2700,
  DateTime? lastMoveTime,
}) {
  PlayerCard player(String name, int rating) => PlayerCard(
    name: name,
    federation: 'IND',
    title: 'GM',
    rating: rating,
    countryCode: 'IN',
    team: null,
  );
  return GamesTourModel(
    gameId: id,
    source: source,
    whitePlayer: player('White, Player', whiteRating),
    blackPlayer: player('Black, Player', blackRating),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: 'round-1',
    tourId: tourId,
    fen: fen,
    lastMove: lastMove,
    pgn: pgn,
    lastMoveTime: lastMoveTime,
  );
}

// ---------------------------------------------------------------- pump

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool subscribed = false,
  Future<MostLikedResult> Function(MostLikedPeriod period)? mostLiked,
  List<MostLikedQuery>? mostLikedQueries,
  List<StreakRow>? wall,
  Set<int> followed = const <int>{},
  List<DiscoveryMiniature> miniatures = const [],
  List<GamesTourModel> analyzed = const [],
  Future<AnalyzedGamesPage> Function()? firstReportsPage,
  Size size = const Size(390, 5200),
  double textScale = 1,
  // The screen the page believes it is on (the view itself stays tall so
  // every section builds); a 390-wide phone when null.
  Size? phone,
  ThemeData? theme,
  List<FeedItem> feedCache = const [],
  Future<List<Collection>> Function()? collections,
  GamesListViewMode? mode,
  List<Override> extra = const [],
  List<NavigatorObserver> observers = const [],
}) async {
  // Tall enough that every section builds without scrolling.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      subscriptionProvider.overrideWith((ref) => _Subscription(subscribed)),
      streakWallProvider.overrideWith(() => _FakeWall(wall ?? _wall)),
      playerPhotoProvider.overrideWith((ref, fideId) async => null),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      mostLikedProvider.overrideWith((ref, query) {
        mostLikedQueries?.add(query);
        return mostLiked?.call(query.period) ??
            Future.value(const MostLikedResult.notLive());
      }),
      discoveryTodayMiniaturesProvider.overrideWith((ref) async => miniatures),
      discoveryAnalyzedGamesProvider.overrideWith((ref) async => analyzed),
      reportsFirstPageProvider.overrideWith(
        (ref) =>
            firstReportsPage?.call() ??
            Future.value(AnalyzedGamesPage(items: analyzed)),
      ),
      discoveryReviewCurveProvider.overrideWith((ref) async => null),
      discoverySmartRequestsProvider.overrideWith(
        (ref) => const AsyncData(<SmartEventRequest>[]),
      ),
      discoveryCountryProvider.overrideWith((ref) => null),
      miniaturesTotalCountProvider.overrideWith((ref) async => 566112),
      // The seam over the viewer's favourites (never the account itself).
      discoveryFollowedFideIdsProvider.overrideWith((ref) => followed),
      // What the app's game cards read.
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
      ),
      gameCardEvalWithStockfishFallbackProvider.overrideWith(
        (ref, fen) async => _eval(fen),
      ),
      gameCardEvalCacheOnlyProvider.overrideWith(
        (ref, fen) async => _eval(fen),
      ),
      // The tiles' previews: Feed's disk cache and the collections list.
      feedFirstPageCacheReaderProvider.overrideWithValue(() async => feedCache),
      collectionsProvider.overrideWith(
        (ref) => collections?.call() ?? Future.value(const <Collection>[]),
      ),
      if (mode != null) gamesListViewModeProvider.overrideWithValue(mode),
      ...extra,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        navigatorObservers: observers,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            // A phone unless a test says otherwise: the view itself is
            // tall only so every section builds.
            size: phone ?? const Size(390, 844),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const Scaffold(body: DiscoveryView());
          },
        ),
      ),
    ),
  );
  await _settle(tester);
  return container;
}

/// Records the page each push would open, without opening it (a page with
/// reads of its own the test does not stand up): the route is taken back
/// off before its first frame.
class _PushedPages extends NavigatorObserver {
  final pages = <Widget>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! MaterialPageRoute) return;
    final nav = navigator!;
    pages.add(route.builder(nav.context));
    scheduleMicrotask(() => nav.removeRoute(route));
  }
}

/// The flames flicker forever, so never pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Game cards leave a short timer behind; take the tree down and let it run
/// so the test ends with nothing pending.
Future<void> _teardownCards(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
  // The event-video cache the broadcast cards start keeps a periodic timer
  // for as long as its container lives.
  container.dispose();
}

void main() {
  group('Most Liked data', () {
    test('every period is a calendar one holding the day', () {
      final now = DateTime(2026, 9, 23, 15, 30); // a Wednesday
      final today = mostLikedWindow(MostLikedPeriod.today, now);
      expect(today.from, DateTime(2026, 9, 23));
      expect(today.to, DateTime(2026, 9, 24));

      final week = mostLikedWindow(MostLikedPeriod.week, now);
      expect(week.from, DateTime(2026, 9, 21)); // Monday
      expect(week.to, DateTime(2026, 9, 28));

      final month = mostLikedWindow(MostLikedPeriod.month, now);
      expect(month.from, DateTime(2026, 9));
      expect(month.to, DateTime(2026, 10));

      final year = mostLikedWindow(MostLikedPeriod.year, now);
      expect(year.from, DateTime(2026));
      expect(year.to, DateTime(2027));

      // A Sunday belongs to the week that started six days earlier.
      expect(
        mostLikedWindow(MostLikedPeriod.week, DateTime(2026, 9, 27, 23)).from,
        DateTime(2026, 9, 21),
      );
      expect(MostLikedPeriod.today.isPremium, isFalse);
      expect(MostLikedPeriod.values.where((p) => p.isPremium), [
        MostLikedPeriod.week,
        MostLikedPeriod.month,
        MostLikedPeriod.year,
      ]);
    });

    test('the date control walks calendar periods and stops at the edges', () {
      final now = DateTime(2026, 9, 23, 15, 30);
      final today = MostLikedQuery(MostLikedPeriod.today, now);
      expect(today.isCurrent(now), isTrue);
      expect(today.isFree(now), isTrue);
      expect(today.next(now), isNull); // the future has no ranking

      final yesterday = today.previous!;
      expect(yesterday.start, DateTime(2026, 9, 22));
      expect(yesterday.isFree(now), isFalse); // earlier days are Premium
      expect(yesterday.next(now), today);

      final week = MostLikedQuery(MostLikedPeriod.week, now);
      expect(week.isFree(now), isFalse);
      expect(week.previous!.start, DateTime(2026, 9, 14));

      // Month steps land on the 1st, even from the 31st.
      expect(
        MostLikedQuery(
          MostLikedPeriod.month,
          DateTime(2026, 7, 31),
        ).next(now)!.start,
        DateTime(2026, 8),
      );
      expect(
        MostLikedQuery(MostLikedPeriod.month, now).previous!.start,
        DateTime(2026, 8),
      );

      // Nothing before the first day there were likes, but the period that
      // holds it is still reachable.
      expect(
        MostLikedQuery(MostLikedPeriod.today, kMostLikedFirstDay).previous,
        isNull,
      );
      expect(MostLikedQuery(MostLikedPeriod.year, now).previous, isNull);
      expect(
        MostLikedQuery(MostLikedPeriod.month, DateTime(2026, 5, 31)).previous,
        isNull,
      );
      final firstWeek = MostLikedQuery(
        MostLikedPeriod.week,
        DateTime(2026, 6, 1),
      ).previous!;
      expect(firstWeek.start, DateTime(2026, 5, 25));
      expect(firstWeek.previous, isNull);

      // Equal periods are one cache key, whichever day built them.
      expect(
        MostLikedQuery(MostLikedPeriod.week, DateTime(2026, 9, 21)),
        MostLikedQuery(MostLikedPeriod.week, DateTime(2026, 9, 27, 22)),
      );
    });

    test('the date reads unambiguously', () {
      final now = DateTime(2026, 9, 23);
      String label(MostLikedPeriod p, DateTime day) =>
          MostLikedQuery(p, day).label(now);
      // Month first, like the streak card; the year only outside this one.
      expect(label(MostLikedPeriod.today, now), 'Wed, Sep 23');
      expect(
        label(MostLikedPeriod.today, DateTime(2025, 9, 23)),
        'Tue, Sep 23, 2025',
      );
      expect(label(MostLikedPeriod.week, now), 'Sep 21–27');
      expect(
        label(MostLikedPeriod.week, DateTime(2026, 10, 1)),
        'Sep 28 – Oct 4',
      );
      expect(
        label(MostLikedPeriod.week, DateTime(2025, 9, 23)),
        'Sep 22–28, 2025',
      );
      expect(
        label(MostLikedPeriod.week, DateTime(2025, 10, 1)),
        'Sep 29 – Oct 5, 2025',
      );
      expect(
        label(MostLikedPeriod.week, DateTime(2026, 12, 30)),
        'Dec 28, 2026 – Jan 3, 2027',
      );
      expect(label(MostLikedPeriod.month, now), 'September');
      expect(label(MostLikedPeriod.month, DateTime(2025, 8, 2)), 'August 2025');
      expect(label(MostLikedPeriod.year, now), '2026');
    });

    test('players fold across games and earn each game\'s likes', () {
      PlayerCard p(String name, {int? fide, int rating = 2700}) => PlayerCard(
        name: name,
        federation: 'IND',
        title: 'GM',
        rating: rating,
        countryCode: 'IND',
        team: null,
        fideId: fide,
      );
      MostLikedEntry e(int rank, int likes, PlayerCard w, PlayerCard b) =>
          MostLikedEntry(
            rank: rank,
            likes: likes,
            game: _game('g$rank').copyWith(whitePlayer: w, blackPlayer: b),
          );

      final players = aggregateMostLikedPlayers([
        e(1, 30, p('Gukesh, D', fide: 1), p('Ding, Liren', fide: 2)),
        // Same FIDE id under another spelling folds together.
        e(2, 20, p('Gukesh D', fide: 1, rating: 2790), p('Carlsen, Magnus')),
        e(3, 20, p('Carlsen, Magnus'), p('?')),
      ]);
      expect(players.map((r) => r.player.name), [
        'Gukesh, D',
        'Carlsen, Magnus',
        'Ding, Liren',
      ]);
      expect(players.map((r) => r.likes), [50, 40, 30]);
      expect(players.map((r) => r.games), [2, 2, 1]);
      expect(players.map((r) => r.rank), [1, 2, 3]);
      // The richer card wins: the higher rating another event carried.
      expect(players.first.player.rating, 2790);
      expect(aggregateMostLikedPlayers(const []), isEmpty);
    });

    test('rows rank by likes desc, id asc; bad rows never get a count', () {
      final counts = parseMostLikedRows([
        {'source_game_id': 'b', 'like_count': 5},
        {'source_game_id': 'a', 'like_count': 5},
        {'source_game_id': 'c', 'like_count': 9},
        {'source_game_id': 'c', 'like_count': 2}, // repeated id
        {'source_game_id': '', 'like_count': 4}, // no id
        {'source_game_id': 'z', 'like_count': 0}, // no likes
        {'source_game_id': 'y', 'like_count': 'x'}, // unreadable
        'not a row',
      ]);
      expect(counts, const [
        MostLikedCount(gameId: 'c', likes: 9),
        MostLikedCount(gameId: 'a', likes: 5),
        MostLikedCount(gameId: 'b', likes: 5),
      ]);
      expect(parseMostLikedRows(null), isEmpty);
    });

    test('entries keep their true rank and skip unresolved games', () {
      final entries = assembleMostLikedEntries(
        counts: const [
          MostLikedCount(gameId: 'g1', likes: 30),
          MostLikedCount(gameId: 'gone', likes: 20),
          MostLikedCount(gameId: 'g3', likes: 10),
        ],
        gamesById: {
          'g1': _game('g1', tourId: 'olympiad'),
          'g3': _game('g3', tourId: 'Tata Steel', source: GameSource.gamebase),
        },
        eventNamesByTourId: const {'olympiad': 'Olympiad Open'},
      );
      expect(entries.map((e) => e.rank), [1, 3]);
      expect(entries.map((e) => e.likes), [30, 10]);
      expect(entries.first.eventName, 'Olympiad Open');
      // Archive games carry their event name in tourId.
      expect(entries.last.eventName, 'Tata Steel');
    });

    test('a missing ranking function reads as not live, not as an error', () {
      expect(
        classifyMostLikedError(
          const PostgrestException(message: 'not found', code: 'PGRST202'),
        ),
        MostLikedFailure.missingFunction,
      );
      expect(
        classifyMostLikedError(
          const PostgrestException(message: 'undefined', code: '42883'),
        ),
        MostLikedFailure.missingFunction,
      );
      expect(
        classifyMostLikedError(
          const PostgrestException(message: 'premium_required', code: 'P0001'),
        ),
        MostLikedFailure.premiumRequired,
      );
      expect(
        classifyMostLikedError(Exception('offline')),
        MostLikedFailure.other,
      );
    });
  });

  group('positions and reviews', () {
    test('a board shows only for a real position', () {
      const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      expect(discoveryHasRealPosition(_game('a')), isFalse);
      expect(discoveryHasRealPosition(_game('b', fen: start)), isFalse);
      expect(
        discoveryHasRealPosition(
          _game('c', fen: '8/6Q1/b1p5/6k1/1p1Pr3/6K1/8/8 b - - 1 54'),
        ),
        isTrue,
      );
      expect(discoveryHasRealPosition(_game('d', lastMove: 'e2e4')), isTrue);
      expect(
        discoveryHasRealPosition(
          _game('e', pgn: '[Event "X"]\n\n1. e4 e5 2. Nf3 *'),
        ),
        isTrue,
      );
    });

    test('eval curve reads centipawns and pins mates to the edge', () {
      const pgn =
          '1. e4 { [%eval 0.17] [%clk 1:59:52] } 1... e5 { [%eval -0.35,22] } '
          '2. Qh5 { [%eval #3] } 2... g6 { [%eval #-2] } 3. a3 { [%eval 25.0] }';
      expect(parseEvalCurve(pgn), [17, -35, 1000, -1000, 1000]);
      expect(parseEvalCurve('1. e4 e5 *'), isEmpty);
      expect(parseEvalCurve(null), isEmpty);
    });

    test('analyzed games rank strongest first, then most recent', () {
      final older = DateTime(2026, 9, 20);
      final newer = DateTime(2026, 9, 22);
      final ranked = rankAnalyzedGames([
        _game('weak', whiteRating: 2400, blackRating: 2400),
        _game('strong-old', lastMoveTime: older),
        _game('strong-new', lastMoveTime: newer),
      ]);
      expect(ranked.map((g) => g.gameId), ['strong-new', 'strong-old', 'weak']);
    });
  });

  group('card meta', () {
    test('event names shorten to what one card line can hold', () {
      const table = {
        'FIDE World Rapid & Blitz Championships 2026 | Open Blitz Round 14':
            'FIDE World Rapid & Blitz Championships',
        'Tata Steel Chess Tournament 2026 | Masters': 'Tata Steel',
        'Norway Chess 2026 | Open': 'Norway Chess',
        "FIDE Women's Grand Prix 2026 | Leg 3, Monaco":
            "FIDE Women's Grand Prix",
        'Sinquefield Cup 2026': 'Sinquefield Cup',
        '2026 FIDE World Cup': 'FIDE World Cup',
        'Grand Chess Tour 2026 - Superbet Poland':
            'Grand Chess Tour - Superbet Poland',
        '  Olympiad   Open  ': 'Olympiad Open',
        // Nothing left once trimmed: the first segment stays as written.
        'Chess Tournament': 'Chess Tournament',
        '2026 | Open': '2026',
      };
      for (final MapEntry(key: raw, value: short) in table.entries) {
        expect(discoveryShortEventName(raw), short, reason: raw);
      }
      expect(discoveryShortEventName(null), isNull);
      expect(discoveryShortEventName('   '), isNull);
    });

    test('the average rating uses whichever sides are rated', () {
      expect(
        discoveryAverageRating(
          _game('a', whiteRating: 2701, blackRating: 2800),
        ),
        2750,
      );
      expect(
        discoveryAverageRating(_game('b', whiteRating: 0, blackRating: 2600)),
        2600,
      );
      expect(
        discoveryAverageRating(_game('c', whiteRating: 2500, blackRating: 0)),
        2500,
      );
      expect(
        discoveryAverageRating(_game('d', whiteRating: 0, blackRating: 0)),
        isNull,
      );
    });
  });

  group('Discovery destinations', () {
    testWidgets('Discovery starts one Reports page before its tile is tapped', (
      tester,
    ) async {
      var reads = 0;
      final container = await _pump(
        tester,
        firstReportsPage: () async {
          reads++;
          return AnalyzedGamesPage(items: [_game('report')]);
        },
      );
      expect(reads, 1);
      expect(find.byType(ReportsScreen), findsNothing);
      expect(container.exists(reportsPaginationProvider), isFalse);
      await _settle(tester);
      expect(reads, 1);
      await _teardownCards(tester, container);
    });

    testWidgets(
      'distinct graphic fields cannot reveal hidden broadcast positions',
      (tester) async {
        const fen = '8/6Q1/b1p5/6k1/1p1Pr3/6K1/8/8 b - - 1 54';
        final game = _game('hidden', fen: fen);
        final container = await _pump(
          tester,
          analyzed: [game],
          feedCache: [
            FeedItem(
              game: game,
              plies: const [FeedPly(fen: fen, uci: 'g7g6')],
              reason: '',
            ),
          ],
          extra: [
            eventNoSpoilersProvider.overrideWith(
              (ref, tourId) => _HiddenSpoilers(ref: ref, tourId: tourId),
            ),
            discoveryReviewCurveProvider.overrideWith(
              (ref) async => [0, 10, 20, 30, 0, 10, 20, 30],
            ),
          ],
        );
        final scenes = tester.widgetList<HubSceneBackdrop>(
          find.byType(HubSceneBackdrop),
        );
        expect(scenes.map((art) => art.scene), [
          HubScene.feed,
          HubScene.mostLiked,
          HubScene.miniatures,
          HubScene.reports,
        ]);
        expect(find.byType(DiscoveryMiniBoard), findsNothing);
        expect(container.exists(discoveryReviewCurveProvider), isFalse);
        await _teardownCards(tester, container);
      },
    );

    List<MostLikedEntry> ranking(int n) => [
      for (var i = 0; i < n; i++)
        MostLikedEntry(rank: i + 1, likes: 1200 - i * 90, game: _game('ml$i')),
    ];

    testWidgets('four complete tiles replace the old Collections destination', (
      tester,
    ) async {
      final container = await _pump(tester);
      for (final title in ['Feed', 'Likes', 'Miniatures', 'Reports']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Most Liked'), findsNothing);
      expect(find.text('Collections'), findsNothing);
      expect(find.byType(HubTile), findsNWidgets(4));
      expect(find.byType(DiscoveryGameList), findsNothing);
      expect(container.exists(feedProvider), isFalse);
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });

    testWidgets(
      'hearts stay simple and reports do not show a preview as a total',
      (tester) async {
        final container = await _pump(
          tester,
          mostLiked: (_) async => MostLikedResult.ranked(ranking(12)),
          analyzed: [_game('review1'), _game('review2')],
        );
        expect(
          tester
              .widgetList<HubSceneBackdrop>(find.byType(HubSceneBackdrop))
              .where((art) => art.scene == HubScene.mostLiked),
          hasLength(1),
        );
        expect(find.text('Games with analysis'), findsOneWidget);
        expect(find.text('2 analyzed games'), findsNothing);
        expect(container.exists(discoveryAnalyzedGamesProvider), isFalse);
        expect(find.byType(GridGameCardWrapperWidget), findsNothing);
        expect(find.byType(GameCardWrapperWidget), findsNothing);
        expect(find.byType(LikeCountHeart), findsNothing);
        await _teardownCards(tester, container);
      },
    );

    testWidgets('Likes, Miniatures and Reports open working destinations', (
      tester,
    ) async {
      final pushed = _PushedPages();
      final container = await _pump(tester, observers: [pushed]);
      for (final name in ['likes', 'miniatures', 'reports']) {
        await tester.tap(find.byKey(ValueKey('discovery_${name}_tile')));
        await _settle(tester);
      }
      expect(pushed.pages, hasLength(3));
      expect(pushed.pages[0], isA<LikesScreen>());
      expect(pushed.pages[1], isA<MiniaturesScreen>());
      expect(pushed.pages[2], isA<ReportsScreen>());
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });

    testWidgets(
      'unavailable rankings do not block Likes before or after refresh',
      (tester) async {
        final queries = <MostLikedQuery>[];
        final container = await _pump(
          tester,
          mostLikedQueries: queries,
          mostLiked: (_) => Future.error(Exception('offline')),
        );
        expect(find.text('Saved games & rankings'), findsOneWidget);
        expect(find.byType(HubTile), findsNWidgets(4));
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await _settle(tester);
        expect(find.text('Likes'), findsOneWidget);
        expect(queries, isEmpty);
        expect(
          tester
              .widgetList<HubSceneBackdrop>(find.byType(HubSceneBackdrop))
              .where((art) => art.scene == HubScene.mostLiked),
          hasLength(1),
        );
        await _teardownCards(tester, container);
      },
    );

    testWidgets('unknown data never invents games or player pairings', (
      tester,
    ) async {
      final container = await _pump(tester);
      expect(find.text('Games with analysis'), findsOneWidget);
      expect(find.text('0 analyzed games'), findsNothing);
      expect(
        tester
            .widgetList<HubSceneBackdrop>(find.byType(HubSceneBackdrop))
            .where((art) => art.scene == HubScene.mostLiked),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });

    testWidgets('Likes loads rankings only when its Most Liked tab opens', (
      tester,
    ) async {
      final queries = <MostLikedQuery>[];
      final container = await _pump(
        tester,
        mostLikedQueries: queries,
        extra: [
          mostLikedPeriodProvider.overrideWith((ref) => MostLikedPeriod.week),
        ],
      );
      expect(queries, isEmpty);
      expect(find.byType(DiscoverySegments<MostLikedPeriod>), findsNothing);
      expect(find.byType(MostLikedDateControl), findsNothing);
      await _teardownCards(tester, container);
    });

    for (final width in [320.0, 390.0, 1024.0]) {
      testWidgets('two rows align at $width pixels with large text', (
        tester,
      ) async {
        final container = await _pump(
          tester,
          size: Size(width, 1200),
          phone: Size(width, width > 600 ? 1366 : 844),
          textScale: 1.5,
        );
        Rect box(String name) =>
            tester.getRect(find.byKey(ValueKey('discovery_${name}_tile')));
        expect(box('feed').top, box('likes').top);
        expect(box('miniatures').top, box('reports').top);
        expect(box('feed').left, box('miniatures').left);
        expect(box('likes').left, box('reports').left);
        expect(box('feed').height, box('likes').height);
        expect(tester.takeException(), isNull);
        await _teardownCards(tester, container);
      });
    }
  });
}
