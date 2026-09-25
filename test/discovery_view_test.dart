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
import 'package:chessever2/screens/for_you/discovery/most_liked_screen.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_controls.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_section.dart'
    show kMostLikedNotLive;
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
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
import 'package:chessever2/widgets/hub_tile_art.dart';
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
      feedFirstPageCacheReaderProvider.overrideWithValue(
        () async => feedCache,
      ),
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

const _fenA =
    'r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R w KQ - 0 9';
const _fenB = '6k1/5pp1/7p/3P4/1r6/6P1/5PKP/3R4 w - - 0 38';

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

  group('DiscoveryView', () {
    testWidgets('opens with the Feed and Collection tiles, then Most liked '
        'and Miniatures, nothing else', (tester) async {
      final container = await _pump(tester);

      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Collection'), findsOneWidget);
      expect(find.text('Most liked'), findsOneWidget);
      expect(find.text('Miniatures'), findsOneWidget);
      // Hidden or moved elsewhere.
      expect(find.text('Streaks'), findsNothing);
      expect(find.text('Smart Events'), findsNothing);
      expect(find.text('Analyzed games'), findsNothing);
      expect(find.text('With Premium'), findsNothing);
      // The tiles lead the page.
      expect(
        tester.getTopLeft(find.text('Feed')).dy,
        lessThan(tester.getTopLeft(find.text('Most liked')).dy),
      );
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });

    testWidgets('Most liked lists its games as game cards, each board '
        'holding its likes in a heart', (tester) async {
      final container = await _pump(
        tester,
        subscribed: true,
        mostLiked: (_) async => MostLikedResult.ranked([
          MostLikedEntry(
            rank: 1,
            likes: 40,
            game: _game('m1', fen: _fenA, lastMove: 'e2e4'),
          ),
          MostLikedEntry(
            rank: 2,
            likes: 1184,
            game: _game('m2', fen: _fenB, lastMove: 'e2e4'),
          ),
        ]),
        miniatures: [
          DiscoveryMiniature(
            game: _game('mi1', fen: _fenB, lastMove: 'e2e4'),
            moves: 19,
          ),
        ],
      );

      expect(find.byType(DiscoveryGameList), findsNWidgets(2));
      final hearts = tester
          .widgetList<LikeCountHeart>(find.byType(LikeCountHeart))
          .map((h) => h.likes)
          .toList();
      expect(hearts, containsAll(<int>[40, 1184]));
      // A miniature carries no heart.
      expect(hearts, hasLength(2));
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });

    testWidgets('a failing section never blanks the others', (tester) async {
      final container = await _pump(
        tester,
        mostLiked: (_) => Future.error(Exception('offline')),
      );

      expect(find.text("Couldn't load Most liked"), findsOneWidget);
      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Miniatures'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });
  });

  group('DiscoveryView previews', () {
    List<MostLikedEntry> twelve() => [
      for (var i = 0; i < 12; i++)
        MostLikedEntry(
          rank: i + 1,
          likes: 1200 - i * 90,
          game: _game(
            'ml$i',
            fen: i.isEven ? _fenA : _fenB,
            lastMove: 'e2e4',
          ),
          eventName: 'Sinquefield Cup 2026',
        ),
    ];
    List<DiscoveryMiniature> minis(int n) => [
      for (var i = 0; i < n; i++)
        DiscoveryMiniature(
          game: _game(
            'mi$i',
            fen: _fenB,
            lastMove: 'e2e4',
            source: GameSource.gamebase,
            whiteRating: 2701,
            blackRating: 2800,
          ),
          moves: 19,
        ),
    ];

    Finder seeAll() => find.textContaining('See all', findRichText: true);

    testWidgets('Most liked previews four of its twelve, each board holding '
        'its likes, and the fourth opens on all twelve', (tester) async {
      final container = await _pump(
        tester,
        mostLiked: (_) async => MostLikedResult.ranked(twelve()),
      );

      final cards = tester
          .widgetList<GridGameCardWrapperWidget>(
            find.byType(GridGameCardWrapperWidget),
          )
          .toList();
      expect(cards, hasLength(4));
      for (final card in cards) {
        expect(card.orderedGames, hasLength(12));
      }
      expect(cards[3].gameIndex, 3);
      expect(cards[3].orderedGames[3].gameId, 'ml3');
      expect(
        tester
            .widgetList<LikeCountHeart>(find.byType(LikeCountHeart))
            .map((h) => h.likes),
        [1200, 1110, 1020, 930],
      );
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });

    testWidgets('board view previews two; list view four rows with likes and '
        'event under the players', (tester) async {
      var container = await _pump(
        tester,
        mode: GamesListViewMode.chessBoard,
        mostLiked: (_) async => MostLikedResult.ranked(twelve()),
      );
      expect(find.byType(GameCardWrapperWidget), findsNWidgets(2));
      await _teardownCards(tester, container);

      container = await _pump(
        tester,
        mode: GamesListViewMode.gamesCard,
        mostLiked: (_) async => MostLikedResult.ranked(twelve()),
      );
      final rows = tester
          .widgetList<GameCardWrapperWidget>(find.byType(GameCardWrapperWidget))
          .toList();
      expect(rows, hasLength(4));
      // A row's strip shows its clocks (or, without them, the opening and
      // the day); the likes and the event ride on the one line over each
      // row, as they ride over a grid card.
      expect(rows.first.footerDetail ?? '', isNot(contains('likes')));
      final lines = tester
          .widgetList<DiscoveryCardMeta>(find.byType(DiscoveryCardMeta))
          .toList();
      expect(lines, hasLength(4));
      expect(lines.first.semanticsLabel, startsWith('1,200 likes'));
      expect(lines.first.semanticsLabel, contains('Sinquefield Cup'));
      for (final row in rows) {
        expect(row.gamesData.gamesTourModels, hasLength(12));
      }
      await _teardownCards(tester, container);
    });

    testWidgets('the hub is always today: no periods, no date control, and '
        'a period picked on the page never moves it', (tester) async {
      final queries = <MostLikedQuery>[];
      final container = await _pump(
        tester,
        subscribed: true,
        mostLikedQueries: queries,
        mostLiked: (_) async => MostLikedResult.ranked(twelve()),
        extra: [
          mostLikedPeriodProvider.overrideWith((ref) => MostLikedPeriod.week),
        ],
      );

      expect(find.byType(DiscoverySegments<MostLikedPeriod>), findsNothing);
      expect(find.byType(MostLikedDateControl), findsNothing);
      expect(find.byType(DiscoveryDateStepper), findsNothing);
      expect(queries, isNotEmpty);
      expect(queries.every((q) => q.period == MostLikedPeriod.today), isTrue);
      await _teardownCards(tester, container);
    });

    testWidgets('a miniature card reads its length and average over the '
        'board, on one line', (tester) async {
      // The test font sets every glyph a full em wide; at a smaller text
      // size the whole line fits the card, as it does in Inter.
      final container = await _pump(
        tester,
        miniatures: minis(12),
        textScale: 0.7,
      );

      expect(find.byType(GridGameCardWrapperWidget), findsNWidgets(4));
      final label = find.textContaining('19 moves · Ø 2750', findRichText: true);
      expect(label, findsNWidgets(4));
      // Paired cards keep one top edge.
      final tops = [
        for (final e in label.evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      ];
      expect(tops[0], tops[1]);
      expect(tops[2], tops[3]);
      await _teardownCards(tester, container);
    });

    testWidgets('nothing on the hub streams or runs the engine, and the Feed '
        'is never built', (tester) async {
      final container = await _pump(
        tester,
        mostLiked: (_) async => MostLikedResult.ranked(twelve()),
        miniatures: minis(6),
      );

      final grid = tester.widgetList<GridGameCardWrapperWidget>(
        find.byType(GridGameCardWrapperWidget),
      );
      expect(grid, hasLength(8));
      for (final card in grid) {
        expect(card.streamEnabled, isFalse);
        expect(card.allowStockfishFallback, isFalse);
      }
      for (final card in tester.widgetList<GameCardWrapperWidget>(
        find.byType(GameCardWrapperWidget),
      )) {
        expect(card.streamEnabled, isFalse);
        expect(card.allowStockfishFallback, isFalse);
      }
      expect(container.exists(feedProvider), isFalse);
      await _teardownCards(tester, container);
    });

    testWidgets('the tiles say what is behind them', (tester) async {
      final feedGame = _game('feed', fen: _fenA, lastMove: 'e2e4').copyWith(
        whitePlayer: PlayerCard(
          name: 'Carlsen, Magnus',
          federation: 'NOR',
          title: 'GM',
          rating: 2830,
          countryCode: 'NO',
          team: null,
        ),
        blackPlayer: PlayerCard(
          name: 'Nakamura, Hikaru',
          federation: 'USA',
          title: 'GM',
          rating: 2800,
          countryCode: 'US',
          team: null,
        ),
      );
      Collection c(String id, CollectionKind kind) =>
          Collection(id: id, slug: id, kind: kind, title: id);
      var container = await _pump(
        tester,
        feedCache: [
          FeedItem(
            game: feedGame,
            plies: const [FeedPly(fen: _fenA, uci: 'e2e4')],
            reason: 'Brilliant finish',
          ),
        ],
        collections: () async => [
          c('a', CollectionKind.event),
          c('b', CollectionKind.event),
          c('c', CollectionKind.book),
        ],
      );
      expect(find.text('Carlsen vs Nakamura'), findsOneWidget);
      expect(find.text('2 events · 1 book'), findsOneWidget);
      // Both tiles are filled by their picture: Feed's animated pixel object.
      expect(find.byType(HubPixelBackdrop), findsWidgets);
      await _teardownCards(tester, container);

      // Before Feed has cached a page, and before the collections land.
      container = await _pump(
        tester,
        collections: () => Completer<List<Collection>>().future,
      );
      expect(find.text('Games and news'), findsOneWidget);
      expect(find.text('Tap to view'), findsOneWidget);
      await _teardownCards(tester, container);
    });

    testWidgets('on a tablet the two previews stand side by side', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        size: const Size(1024, 5200),
        phone: const Size(1024, 1366),
        mostLiked: (_) async => MostLikedResult.ranked(twelve()),
        miniatures: minis(6),
      );
      final mostLiked = tester.getTopLeft(find.text('Most liked'));
      final miniatures = tester.getTopLeft(find.text('Miniatures'));
      expect(miniatures.dy, mostLiked.dy);
      expect(miniatures.dx, greaterThan(mostLiked.dx + 300));
      // Each column is a 2x2 grid of its own.
      expect(find.byType(GridGameCardWrapperWidget), findsNWidgets(8));
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });

    testWidgets('See all opens the Most liked page', (tester) async {
      final container = await _pump(
        tester,
        mostLiked: (_) async => MostLikedResult.ranked(twelve()),
      );
      await tester.tap(find.bySemanticsLabel('See all of Most liked'));
      await _settle(tester);
      expect(find.byType(MostLikedScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });

    testWidgets('empty and not-live states keep the page honest', (
      tester,
    ) async {
      var container = await _pump(
        tester,
        mostLiked: (_) async => const MostLikedResult.ranked([]),
      );
      expect(find.text('No games liked yet today'), findsOneWidget);
      expect(find.text('No miniatures yet today'), findsOneWidget);
      // Both headers still lead somewhere.
      expect(seeAll(), findsNWidgets(2));
      await _teardownCards(tester, container);

      container = await _pump(tester);
      expect(find.text(kMostLikedNotLive), findsOneWidget);
      // Nothing to see all of while ranking is not live.
      expect(seeAll(), findsOneWidget);
      await _teardownCards(tester, container);
    });
  });
}
