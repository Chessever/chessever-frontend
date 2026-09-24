import 'dart:ui' show Tristate;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/discovery_view.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/analyzed_games_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_controls.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/premium_tour_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/todays_miniatures_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/whos_hot_section.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/contrast_audit.dart';

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
  // The phone the page believes it is on (the view itself stays tall so
  // every section builds); null keeps the view's own size.
  Size? phone,
  ThemeData? theme,
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
            size: phone ?? MediaQuery.sizeOf(context),
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

    test('the Premium tour is for free accounts only', () {
      expect(
        discoverySections(subscribed: false),
        contains(DiscoverySection.premiumTour),
      );
      expect(
        discoverySections(subscribed: true),
        isNot(contains(DiscoverySection.premiumTour)),
      );
      expect(
        discoverySections(subscribed: true).last,
        DiscoverySection.smartEvents,
      );
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
    testWidgets('free: every section renders with its boundary in place', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final container = await _pump(tester);

      // Most liked: honest line while the ranking is not deployed.
      expect(find.text('Most liked'), findsOneWidget);
      expect(find.text(kMostLikedNotLive), findsOneWidget);
      // Nothing sells a ranking that is not live: no periods, no CTA line in
      // the section, no rankings tile on the tour, only the notice.
      expect(
        find.bySemanticsLabel(RegExp(r'^Most liked, (Today|Week|Month|Year)')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('tour_rankings')), findsNothing);
      expect(container.read(mostLikedPeriodProvider), MostLikedPeriod.today);

      // Streaks: 2400+ classical runs only.
      expect(find.text('Streaks'), findsOneWidget);
      expect(find.text("Who's hot"), findsNothing);
      expect(find.text('Gujrathi'), findsOneWidget);
      expect(find.text('Abdusattorov'), findsOneWidget);
      expect(find.text('Young'), findsNothing);

      // With Premium: each tile states its outcome, with its one padlock
      // after the words; the picture on the tile carries none.
      expect(find.text('With Premium'), findsOneWidget);
      final tour = find.byType(PremiumTourSection);
      for (final (id, cta) in const [
        ('reviews', 'Review a top game'),
        ('prep', 'Prepare for this player'),
        ('miniatures', 'Browse past days'),
        ('tree', 'Explore this position'),
        ('countrymen', "Follow your country's players"),
        ('library', 'Save to a synced personal database'),
        ('desktop', 'Continue on your computer'),
      ]) {
        final tile = find.byKey(ValueKey('tour_$id'));
        final words = find.descendant(
          of: tile,
          matching: find.textContaining(cta),
        );
        expect(words, findsOneWidget, reason: cta);
        final lock = find.descendant(
          of: tile,
          matching: find.byType(DiscoveryPadlock),
        );
        expect(lock, findsOneWidget, reason: cta);
        final at = tester.getRect(lock);
        final line = tester.getRect(words);
        expect(at.left, greaterThan(line.left), reason: cta);
        expect(at.center.dy, inInclusiveRange(line.top, line.bottom));
      }
      expect(
        find.descendant(of: tour, matching: find.byType(DiscoveryLockNotch)),
        findsNothing,
      );
      // The prep tile's flag is cut out of the tile's own fill, not boxed
      // in the page colour.
      final prepFace = tester.widget<WallAvatar>(
        find.descendant(
          of: find.byKey(const ValueKey('tour_prep')),
          matching: find.byType(WallAvatar),
        ),
      );
      expect(prepFace.ringColor, AppColors.dark.surface);
      expect(find.text('566,112'), findsOneWidget);

      // Miniatures: the archive boundary shows even on an empty day, once
      // on the page, sold by the section's own line without a second lock
      // (the earlier-days arrow carries it).
      expect(find.text('Miniatures'), findsOneWidget);
      expect(find.text('No miniatures yet today'), findsOneWidget);
      expect(find.textContaining(kMiniaturesUpgradeCta), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DiscoveryUpgradeLine),
          matching: find.byType(DiscoveryPadlock),
        ),
        findsNothing,
      );

      // Creating a Smart Event is the section's header action, Premium.
      expect(
        find.bySemanticsLabel('Create a Smart Event, Premium'),
        findsOneWidget,
      );
      expect(find.textContaining('Create', findRichText: true), findsWidgets);
      expect(
        find.text('No analyzed games in the last three days'),
        findsOneWidget,
      );
      expect(find.textContaining('coming later'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('subscribers see no Premium tour and no upgrade lines', (
      tester,
    ) async {
      await _pump(
        tester,
        subscribed: true,
        mostLiked: (_) async => const MostLikedResult.ranked([]),
      );

      expect(find.text('With Premium'), findsNothing);
      expect(find.text('Explore the Miniatures archive'), findsNothing);
      expect(find.text(kMostLikedUpgradeCta), findsNothing);
      expect(find.text('No games liked yet today'), findsOneWidget);
      expect(find.text('Most liked'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing section never blanks the others', (tester) async {
      await _pump(tester, mostLiked: (_) => Future.error(Exception('offline')));

      expect(find.text("Couldn't load Most liked"), findsOneWidget);
      expect(find.text('Retry'), findsWidgets);
      expect(find.text('Gujrathi'), findsOneWidget);
      expect(find.text('Smart Events'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('free Today ranking offers the Week/Month/Year boundary', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final asked = <MostLikedPeriod>[];
      final container = await _pump(
        tester,
        mostLiked: (period) async {
          asked.add(period);
          return period.isPremium
              ? const MostLikedResult.premiumRequired()
              : const MostLikedResult.ranked([]);
        },
      );

      expect(find.text('No games liked yet today'), findsOneWidget);
      // The outcome is sold once on the page: here, not on the tour tile.
      expect(find.textContaining(kMostLikedUpgradeCta), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tour_rankings')),
          matching: find.textContaining("See the week's top games"),
        ),
        findsOneWidget,
      );

      // Each locked period carries its padlock after its label; the line
      // under them sells the same boundary without a lock of its own.
      final segments = find.byType(DiscoverySegments<MostLikedPeriod>);
      expect(
        find.descendant(of: segments, matching: find.byType(DiscoveryPadlock)),
        findsNWidgets(3),
      );
      expect(
        find.descendant(
          of: find.byType(DiscoveryUpgradeLine),
          matching: find.byType(DiscoveryPadlock),
        ),
        findsNothing,
      );

      // The locked periods say so, as tabs: Today is picked and free.
      final today = tester.getSemantics(
        find.bySemanticsLabel('Most liked, Today'),
      );
      expect(today.flagsCollection.isSelected, Tristate.isTrue);
      expect(today.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      final week = find.bySemanticsLabel('Most liked, Week, Premium');
      expect(week, findsOneWidget);

      // Debug builds pass the premium guard, so the pick goes through and
      // the server's refusal lands as the boundary line, not an error.
      await tester.tap(week);
      await _settle(tester);
      expect(container.read(mostLikedPeriodProvider), MostLikedPeriod.week);
      expect(asked, contains(MostLikedPeriod.week));
      expect(find.text("Couldn't load Most liked"), findsNothing);
      expect(find.textContaining(kMostLikedUpgradeCta), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('each outcome sentence once, every way into Premium kept', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final container = await _pump(
        tester,
        mostLiked: (_) async => MostLikedResult.ranked([
          MostLikedEntry(
            rank: 1,
            likes: 40,
            game: _game('m1', fen: _fenA, lastMove: 'e2e4'),
          ),
        ]),
        miniatures: [
          DiscoveryMiniature(
            game: _game('mi1', fen: _fenB, lastMove: 'e2e4'),
            moves: 19,
          ),
        ],
        analyzed: [_game('an1', fen: _fenA, lastMove: 'e2e4')],
      );

      // The sections sell their own outcomes, and nothing repeats them.
      for (final sentence in const [
        kMostLikedUpgradeCta,
        kAnalyzedGamesUpgradeCta,
        kMiniaturesUpgradeCta,
      ]) {
        expect(find.textContaining(sentence), findsOneWidget, reason: sentence);
        expect(
          find.bySemanticsLabel('$sentence, Premium'),
          findsOneWidget,
          reason: sentence,
        );
      }
      // Every tour tile is still there, still a Premium button.
      for (final id in const [
        'reviews',
        'rankings',
        'prep',
        'miniatures',
        'tree',
        'countrymen',
        'library',
        'desktop',
      ]) {
        final tile = find.byKey(ValueKey('tour_$id'));
        expect(tile, findsOneWidget, reason: id);
        expect(
          find.descendant(
            of: tile,
            matching: find.bySemanticsLabel(RegExp(r', Premium$')),
          ),
          findsWidgets,
          reason: id,
        );
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await _teardownCards(tester, container);
    });

    testWidgets('sections keep one rhythm, measured from their last ink', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        mostLiked: (_) async => MostLikedResult.ranked([
          MostLikedEntry(
            rank: 1,
            likes: 40,
            game: _game('m1', fen: _fenA, lastMove: 'e2e4'),
          ),
        ]),
      );

      // Most liked ends on its upgrade line, Streaks on its tiles: the next
      // title sits the same distance below either.
      final line = tester.getRect(find.textContaining(kMostLikedUpgradeCta));
      final streaks = tester.getRect(find.text('Streaks'));
      final tile = tester.getRect(find.byType(DiscoveryStreakTile).first);
      final miniatures = tester.getRect(find.text('Miniatures'));
      expect(
        streaks.top - line.bottom,
        moreOrLessEquals(miniatures.top - tile.bottom, epsilon: 0.5),
      );

      // The line's 44 target still reaches past the trimmed edge, into the
      // gap: a tap just under the words is still the line's.
      expect(container.read(mostLikedPeriodProvider), MostLikedPeriod.today);
      await tester.tapAt(Offset(line.center.dx, line.bottom + 10));
      await _settle(tester);
      expect(container.read(mostLikedPeriodProvider), MostLikedPeriod.week);
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });

    testWidgets(
      'the date walks the archive and the players row opens in place',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final queries = <MostLikedQuery>[];
        // The ranking starts empty, so the date walk runs with no card built.
        var withGame = false;
        final container = await _pump(
          tester,
          subscribed: true,
          mostLikedQueries: queries,
          mostLiked: (_) async => MostLikedResult.ranked([
            if (withGame) MostLikedEntry(rank: 1, likes: 12, game: _game('g1')),
          ]),
        );
        final now = DateTime.now();
        final today = MostLikedQuery(MostLikedPeriod.today, now);
        final yesterday = today.previous!;

        // Today's date sits between the arrows; the next day does not exist.
        expect(find.text(today.label(now)), findsWidgets);
        expect(queries, contains(today));
        expect(find.text('No games liked yet today'), findsOneWidget);

        Finder arrow(String label) => find.descendant(
          of: find.byType(MostLikedDateControl),
          matching: find.bySemanticsLabel(label),
        );

        await tester.tap(arrow('Previous day'));
        await _settle(tester);
        expect(container.read(mostLikedDayProvider), yesterday.start);
        expect(queries, contains(yesterday));
        expect(find.text(yesterday.label(now)), findsOneWidget);
        expect(find.text('No games liked that day'), findsOneWidget);

        await tester.tap(arrow('Next day'));
        await _settle(tester);
        // Back on the current day the pick clears and follows the clock.
        expect(container.read(mostLikedDayProvider), isNull);

        // Once the ranking has a game, the players in it sit under it as a
        // row of faces; opening it lists them in place.
        withGame = true;
        container.invalidate(mostLikedProvider);
        await _settle(tester);
        final row = find.byKey(const ValueKey('most_liked_players_row'));
        expect(row, findsOneWidget);
        expect(find.text('2 players in this ranking'), findsOneWidget);
        // The game itself is the app's own card, names and all.
        expect(
          find.byKey(const ValueKey('most_liked_compact_g1')),
          findsOneWidget,
        );
        final firstPlayer = find.byKey(const ValueKey('most_liked_player_1'));
        expect(firstPlayer, findsNothing);

        await tester.tap(row);
        await _settle(tester);
        expect(container.read(mostLikedViewProvider), MostLikedView.players);
        expect(firstPlayer, findsOneWidget);
        expect(
          find.byKey(const ValueKey('most_liked_player_2')),
          findsOneWidget,
        );
        // Likes are drawn, and heard as a sentence.
        expect(
          find.bySemanticsLabel(RegExp(r'White, Player.*12 likes$')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'^Rank 1, 12 likes')),
          findsWidgets,
        );
        expect(find.text('12 likes'), findsNothing);
        expect(tester.takeException(), isNull);

        // And closes again.
        await tester.tap(row);
        await _settle(tester);
        expect(container.read(mostLikedViewProvider), MostLikedView.games);
        expect(firstPlayer, findsNothing);
        semantics.dispose();
        await _teardownCards(tester, container);
      },
    );

    testWidgets('Streaks switches time class without touching the wall', (
      tester,
    ) async {
      final container = await _pump(tester);

      await tester.tap(find.text('Rapid').last);
      await _settle(tester);
      expect(find.text('Nakamura'), findsOneWidget);
      expect(find.text('Gujrathi'), findsNothing);
      expect(container.read(discoveryHotClassProvider), StreakTimeClass.rapid);
      expect(
        container.read(streakSelectedClassProvider),
        StreakTimeClass.standard,
      );
    });

    testWidgets("an empty class says so instead of showing nothing", (
      tester,
    ) async {
      await _pump(
        tester,
        wall: [
          _row(3, StreakTimeClass.standard, 'Young, Prodigy', 9, rating: 1900),
        ],
      );
      expect(
        find.text('No live classical runs at 2400+ right now'),
        findsOneWidget,
      );
    });

    testWidgets('followed players lead the Streaks rail at any rating', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      // Young (1900) is under every floor, but the viewer follows them.
      final container = await _pump(tester, followed: {3, 2});
      final items = container.read(
        discoveryStreakRowsProvider(StreakTimeClass.standard),
      );
      expect(items.map((i) => i.row.fideId), [3, 2, 1]);
      expect(items.map((i) => i.followed), [true, true, false]);
      expect(find.text('Young'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r', following, ')), findsNWidgets(2));
      // The follow star is information: the name's own ink, stepped back,
      // never the accent that means "tap here".
      final stars = tester.widgetList<CustomPaint>(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && '${w.painter.runtimeType}' == '_StarPainter',
        ),
      );
      expect(stars, hasLength(2));
      for (final star in stars) {
        final ink = (star.painter as dynamic).color as Color;
        expect(ink, isNot(AppColors.dark.accentText));
        expect(ink, AppColors.dark.textPrimary.withValues(alpha: 0.55));
      }
      semantics.dispose();
    });

    testWidgets('a full page holds together at 360 wide and 1.3x text', (
      tester,
    ) async {
      PlayerCard p(String name, int rating) => PlayerCard(
        name: name,
        federation: 'NOR',
        title: 'GM',
        rating: rating,
        countryCode: 'NO',
        team: null,
      );
      GamesTourModel g(String id, String fen) =>
          _game(id, fen: fen, lastMove: 'e2e4').copyWith(
            whitePlayer: p('Carlsen, Magnus', 2837),
            blackPlayer: p('Praggnanandhaa, Rameshbabu', 2766),
          );
      final container = await _pump(
        tester,
        size: const Size(360, 6400),
        phone: const Size(360, 780),
        textScale: 1.3,
        mostLiked: (_) async => MostLikedResult.ranked([
          MostLikedEntry(
            rank: 1,
            likes: 1184,
            game: g('m1', _fenA),
            eventName:
                'FIDE World Rapid & Blitz Championships 2026 | Open Blitz 14',
          ),
          MostLikedEntry(rank: 2, likes: 12, game: g('m2', _fenB)),
        ]),
        miniatures: [
          DiscoveryMiniature(game: g('mi1', _fenA), moves: 19),
          DiscoveryMiniature(game: g('mi2', _fenB), moves: 24),
        ],
        analyzed: [g('an1', _fenA), g('an2', _fenB)],
      );

      expect(find.byKey(const ValueKey('most_liked_m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('mini_mi1')), findsOneWidget);
      expect(find.byKey(const ValueKey('analyzed_an1')), findsOneWidget);
      expect(find.text('Streaks'), findsOneWidget);
      expect(find.text('Smart Events'), findsOneWidget);
      expect(find.text('With Premium'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardownCards(tester, container);
    });

    testWidgets('a live ranking reads on paper: tabs, likes, meta, faces', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        theme: AppTheme.lightTheme,
        mostLiked: (_) async => MostLikedResult.ranked([
          MostLikedEntry(
            rank: 1,
            likes: 1184,
            game: _game('m1', fen: _fenA, lastMove: 'e2e4'),
            eventName: 'Tata Steel Chess Tournament 2026 | Masters',
          ),
        ]),
        miniatures: [
          DiscoveryMiniature(
            game: _game('mi1', fen: _fenB, lastMove: 'e2e4'),
            moves: 19,
          ),
        ],
      );
      expect(find.byKey(const ValueKey('most_liked_m1')), findsOneWidget);
      expectNoContrastMisses(
        auditTextContrast(
          tester,
          fallbackGround: AppColors.light.background,
          // The app's own cards and avatars are audited with their screens.
          ignoreWithin: const {
            'GridGameCardWrapperWidget',
            'GameCardWrapperWidget',
            'WallAvatar',
            'PlayerInitialsAvatar',
            'SmartEventCard',
          },
        ),
        where: 'DiscoveryView (ranked, light)',
      );
      await _teardownCards(tester, container);
    });

    testWidgets(
      'meta lines: one bold figure, plain ratings, month-first days',
      (tester) async {
        final container = await _pump(
          tester,
          // The test font sets every glyph a full em wide; smaller text
          // keeps each whole meta line on its card, as real type does.
          textScale: 0.6,
          miniatures: [
            DiscoveryMiniature(
              game: _game('mi1', fen: _fenB, lastMove: 'e2e4'),
              moves: 19,
            ),
          ],
          analyzed: [
            _game(
              'an1',
              fen: _fenA,
              lastMove: 'e2e4',
              whiteRating: 2760,
              blackRating: 2755,
              lastMoveTime: DateTime(DateTime.now().year, 9, 23, 12),
            ),
          ],
        );

        /// The bold spans of the one meta line that reads [plain].
        List<String?> boldIn(String plain) {
          final lines = tester
              .widgetList<RichText>(find.byType(RichText))
              .where((r) => r.text.toPlainText() == plain)
              .toList();
          expect(lines, hasLength(1), reason: plain);
          final bold = <String?>[];
          lines.single.text.visitChildren((span) {
            if (span is TextSpan &&
                span.text != null &&
                span.style?.fontWeight == FontWeight.w700) {
              bold.add(span.text);
            }
            return true;
          });
          return bold;
        }

        // Miniatures: the length is the figure, the average stays quiet.
        expect(boldIn('19 moves · Ø 2700'), ['19']);
        // Analyzed games: the average, never comma-grouped, then the day.
        expect(boldIn('Ø 2757 · Sep 23'), ['2757']);
        // The Miniatures stepper reads its day month first too.
        expect(find.text(discoveryWeekday(DateTime.now())), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardownCards(tester, container);
      },
    );
  });
}
