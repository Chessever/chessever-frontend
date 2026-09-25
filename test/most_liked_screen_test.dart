import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/most_liked_screen.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_controls.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_section.dart';
import 'package:chessever2/screens/my_space/widgets/space_avatar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/board_like_heart.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ---------------------------------------------------------------- doubles

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

class _EngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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

const _fen = '6k1/5pp1/7p/3P4/1r6/6P1/5PKP/3R4 w - - 0 38';

PlayerCard _player(String name, int fide) => PlayerCard(
  name: name,
  federation: 'NOR',
  title: 'GM',
  rating: 2800,
  countryCode: 'NO',
  team: null,
  fideId: fide,
);

List<MostLikedEntry> _ranking(int n) => [
  for (var i = 0; i < n; i++)
    MostLikedEntry(
      rank: i + 1,
      likes: 500 - i * 10,
      game: GamesTourModel(
        gameId: 'g$i',
        whitePlayer: _player('White$i, Player', 1000 + i),
        blackPlayer: _player('Black$i, Player', 2000 + i),
        whiteTimeDisplay: '--:--',
        blackTimeDisplay: '--:--',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: GameStatus.whiteWins,
        roundId: 'round-1',
        tourId: 'tour-1',
        fen: _fen,
        lastMove: 'e2e4',
      ),
      eventName: 'Sinquefield Cup 2026',
    ),
];

// ---------------------------------------------------------------- pump

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool subscribed,
  List<MostLikedQuery>? queries,
  Widget home = const MostLikedScreen(),
}) async {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      subscriptionProvider.overrideWith((ref) => _Subscription(subscribed)),
      playerPhotoProvider.overrideWith((ref, fideId) async => null),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
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
      mostLikedProvider.overrideWith((ref, query) async {
        queries?.add(query);
        return MostLikedResult.ranked(_ranking(12));
      }),
    ],
  );
  addTearDown(container.dispose);
  await _mount(tester, container, home);
  return container;
}

Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container,
  Widget home,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: const Size(390, 844)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return home;
          },
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Game cards leave a short timer behind, and the event-video cache they
/// start keeps a periodic one for as long as its container lives.
Future<void> _teardown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
  container.dispose();
}

void main() {
  testWidgets('Games lists the whole ranking with a heart on every board; '
      'Players lists everyone in it, each as their profile circle', (
    tester,
  ) async {
    final container = await _pump(tester, subscribed: true);

    expect(find.text('Most liked'), findsOneWidget);
    expect(find.text('Games'), findsOneWidget);
    expect(find.text('Players'), findsOneWidget);
    // No second "Most liked" or period title: the segments pick the period
    // and the date control says which.
    expect(find.byType(DiscoverySegments<MostLikedPeriod>), findsOneWidget);
    expect(find.byType(MostLikedDateControl), findsOneWidget);

    final cards = tester.widgetList<GridGameCardWrapperWidget>(
      find.byType(GridGameCardWrapperWidget),
    );
    expect(cards, hasLength(12));
    expect(find.byType(LikeCountHeart), findsNWidgets(12));
    // Nothing runs the engine on the page.
    for (final card in cards) {
      expect(card.allowStockfishFallback, isFalse);
    }

    await tester.tap(find.text('Players'));
    await _settle(tester);
    expect(find.byType(MostLikedPlayersList), findsOneWidget);
    expect(find.byType(SpacePlayerAvatar), findsWidgets);
    // A person is a photo circle with a flat monogram, never the gradient
    // initials tile.
    expect(find.byType(PlayerInitialsAvatar), findsNothing);
    expect(find.text('White0, Player'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester, container);
  });

  testWidgets('a free account sees the locked periods and the Players '
      'unlock', (tester) async {
    final container = await _pump(tester, subscribed: false);

    // Week, Month and Year each carry the padlock, and so does the arrow to
    // earlier days.
    expect(find.byType(DiscoveryPadlock), findsNWidgets(4));
    expect(
      find.textContaining(kMostLikedUpgradeCta, findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Players'));
    await _settle(tester);
    expect(find.text('See everyone in this ranking'), findsOneWidget);
    expect(find.byType(MostLikedPlayersList), findsNothing);

    // Debug builds let the guard through, as the paywall would on a
    // purchase; the list then opens in place.
    await tester.tap(find.textContaining('Unlock', findRichText: true));
    await _settle(tester);
    expect(container.read(mostLikedViewProvider), MostLikedView.players);
    expect(find.byType(MostLikedPlayersList), findsOneWidget);
    await _teardown(tester, container);
  });

  testWidgets('the hub stays on today after the page picks a week', (
    tester,
  ) async {
    final queries = <MostLikedQuery>[];
    final container = await _pump(
      tester,
      subscribed: true,
      queries: queries,
    );

    // The label sits under the segment's own target.
    await tester.tap(find.text('Week').first, warnIfMissed: false);
    await _settle(tester);
    expect(container.read(mostLikedPeriodProvider), MostLikedPeriod.week);
    expect(queries.last.period, MostLikedPeriod.week);

    queries.clear();
    await _mount(
      tester,
      container,
      const Scaffold(body: SingleChildScrollView(child: MostLikedPreview())),
    );
    expect(queries, isNotEmpty);
    expect(queries.every((q) => q.period == MostLikedPeriod.today), isTrue);
    // The preview draws four of the twelve.
    expect(find.byType(GridGameCardWrapperWidget), findsNWidgets(4));
    await _teardown(tester, container);
  });
}
