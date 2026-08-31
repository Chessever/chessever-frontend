// Regression: Miniatures / gamebase board & grid cards used to mount the
// eval bar only after hasStarted (lastMove) hydration. Inserting
// EvaluationBarWidgetForGames later shrank the board and reflowed the card.
//
// Finished archive cards must reserve and mount the bar on the first frame;
// eval text may fill in later without changing board or card dimensions.
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _hydratedFen =
    'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR b KQkq - 3 3';
const _startFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

PlayerCard _player(String name) => PlayerCard(
  name: name,
  federation: '',
  title: '',
  rating: 2600,
  countryCode: '',
  team: null,
);

/// Miniatures Games tab shape: gamebase finished archive, header-only
/// (no fen / lastMove) until position hydration lands.
GamesTourModel _headerOnlyMiniature() {
  return GamesTourModel(
    gameId: 'mini-eval-1',
    source: GameSource.gamebase,
    whitePlayer: _player('Morphy'),
    blackPlayer: _player('Duke of Brunswick'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: 'gamebase-miniatures',
    tourId: 'Paris Opera',
    eco: 'C41',
    boardNr: 17,
  );
}

GamesTourModel _hydratedMiniature() {
  return _headerOnlyMiniature().copyWith(
    fen: _hydratedFen,
    lastMove: 'd1f3',
  );
}

class _FakeEngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  _FakeEngineSettings([this.settings = const EngineSettings()]);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeBoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async {
    const settings = BoardSettingsNew();
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _FakeEventNoSpoilersController extends EventNoSpoilersController {
  _FakeEventNoSpoilersController({
    required super.ref,
    required super.tourId,
    this.loadedState = const EventNoSpoilersState(
      enabled: false,
      isLoading: false,
    ),
  });

  final EventNoSpoilersState loadedState;

  @override
  Future<void> load() async {
    state = loadedState;
  }
}

CloudEval _cloudEval(String fen, int cp) {
  return CloudEval(
    fen: fen,
    knodes: 0,
    depth: 12,
    pvs: [Pv(moves: 'e7e5', cp: cp)],
    requestedMultiPv: 1,
  );
}

/// Host that can swap the game model mid-test to simulate hydration.
class _BoardCardHost extends StatefulWidget {
  const _BoardCardHost({super.key, required this.initialGame});

  final GamesTourModel initialGame;

  @override
  State<_BoardCardHost> createState() => _BoardCardHostState();
}

class _BoardCardHostState extends State<_BoardCardHost> {
  late GamesTourModel _game = widget.initialGame;

  void hydrate(GamesTourModel game) => setState(() => _game = game);

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: ChessBoardFromFENNew(
            gamesTourModel: _game,
            onChanged: () {},
            pinnedIds: const [],
            onPinToggle: (_) {},
            allowStockfishFallback: false,
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpBoardCard(
  WidgetTester tester, {
  required GamesTourModel game,
  required GlobalKey<_BoardCardHostState> hostKey,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        engineSettingsProviderNew.overrideWith(_FakeEngineSettings.new),
        boardSettingsProviderNew.overrideWith(_FakeBoardSettings.new),
        eventNoSpoilersProvider.overrideWith(
          (ref, tourId) =>
              _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
        ),
        gameCardEvalWithStockfishFallbackProvider.overrideWith(
          (ref, fen) async => _cloudEval(fen, 250),
        ),
        gameCardEvalCacheOnlyProvider.overrideWith(
          (ref, fen) async => _cloudEval(fen, 250),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: _BoardCardHost(key: hostKey, initialGame: game),
      ),
    ),
  );
}

/// Drains a few frames without pumpAndSettle (settings/sqlite timers).
Future<void> _settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    'miniatures board card mounts eval bar on first frame and keeps size after hydration',
    (tester) async {
      final hostKey = GlobalKey<_BoardCardHostState>();
      final headerOnly = _headerOnlyMiniature();

      expect(headerOnly.hasStarted, isFalse, reason: 'fixture is header-only');
      expect(headerOnly.fen, isNull);
      expect(headerOnly.lastMove, isNull);

      await _pumpBoardCard(tester, game: headerOnly, hostKey: hostKey);
      // First frame only — do not wait for async eval or hydration.
      await tester.pump();

      final barFinder = find.byType(EvaluationBarWidgetForGames);
      expect(
        barFinder,
        findsOneWidget,
        reason:
            'eval bar must be in the tree before lastMove/fen hydration '
            'so board width is reserved from first paint',
      );

      final firstCardSize = tester.getSize(find.byType(ChessBoardFromFENNew));
      final firstBarSize = tester.getSize(barFinder);
      expect(firstBarSize.width, greaterThan(0));

      // Simulate gamebase position hydration: fen + lastMove arrive later.
      hostKey.currentState!.hydrate(_hydratedMiniature());
      await _settleFrames(tester);

      expect(find.byType(EvaluationBarWidgetForGames), findsOneWidget);
      final settledCardSize = tester.getSize(find.byType(ChessBoardFromFENNew));
      final settledBarSize = tester.getSize(
        find.byType(EvaluationBarWidgetForGames),
      );

      expect(
        settledCardSize.width,
        firstCardSize.width,
        reason: 'card width must not reflow when position/eval settles',
      );
      expect(
        settledCardSize.height,
        firstCardSize.height,
        reason: 'card height must not reflow when position/eval settles',
      );
      expect(
        settledBarSize.width,
        firstBarSize.width,
        reason: 'side-bar width must stay reserved; only text/fill may update',
      );
    },
  );

  testWidgets(
    'grid miniatures card also mounts eval bar without lastMove',
    (tester) async {
      final headerOnly = _headerOnlyMiniature();
      expect(headerOnly.hasStarted, isFalse);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineSettingsProviderNew.overrideWith(_FakeEngineSettings.new),
            boardSettingsProviderNew.overrideWith(_FakeBoardSettings.new),
            eventNoSpoilersProvider.overrideWith(
              (ref, tourId) =>
                  _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
            ),
            gameCardEvalWithStockfishFallbackProvider.overrideWith(
              (ref, fen) async => _cloudEval(fen, 0),
            ),
            gameCardEvalCacheOnlyProvider.overrideWith(
              (ref, fen) async => _cloudEval(fen, 0),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [AppColors.dark],
            ),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 180,
                      child: GridChessBoardFromFENNew(
                        gamesTourModel: headerOnly,
                        onChanged: () {},
                        pinnedIds: const [],
                        onPinToggle: (_) {},
                        allowStockfishFallback: false,
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

      expect(find.byType(EvaluationBarWidgetForGames), findsOneWidget);
    },
  );

  testWidgets(
    'ongoing game without lastMove still omits eval bar (upcoming)',
    (tester) async {
      final upcoming = GamesTourModel(
        gameId: 'upcoming-1',
        source: GameSource.supabase,
        whitePlayer: _player('A'),
        blackPlayer: _player('B'),
        whiteTimeDisplay: '90:00',
        blackTimeDisplay: '90:00',
        whiteClockCentiseconds: 540000,
        blackClockCentiseconds: 540000,
        gameStatus: GameStatus.ongoing,
        roundId: 'round-1',
        tourId: 'tour-1',
        fen: _startFen,
      );
      expect(upcoming.hasStarted, isFalse);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineSettingsProviderNew.overrideWith(_FakeEngineSettings.new),
            boardSettingsProviderNew.overrideWith(_FakeBoardSettings.new),
            eventNoSpoilersProvider.overrideWith(
              (ref, tourId) =>
                  _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [AppColors.dark],
            ),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 360,
                      child: ChessBoardFromFENNew(
                        gamesTourModel: upcoming,
                        onChanged: () {},
                        pinnedIds: const [],
                        onPinToggle: (_) {},
                        allowStockfishFallback: false,
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

      expect(find.byType(EvaluationBarWidgetForGames), findsNothing);
    },
  );

  testWidgets('Grid View off hides grid bars while Board View remains on', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineSettingsProviderNew.overrideWith(
            () => _FakeEngineSettings(
              const EngineSettings(
                showEngineGaugeOnBoard: true,
                showEngineGaugeInGrid: false,
              ),
            ),
          ),
          boardSettingsProviderNew.overrideWith(_FakeBoardSettings.new),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: SizedBox(
                  width: 360,
                  child: ChessBoardFromFENNew(
                    gamesTourModel: _hydratedMiniature(),
                    onChanged: () {},
                    pinnedIds: const [],
                    onPinToggle: (_) {},
                    allowStockfishFallback: false,
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

    expect(find.byType(EvaluationBarWidgetForGames), findsNothing);
  });

  testWidgets('No Spoilers hides the live grid evaluation bar', (tester) async {
    final live = GamesTourModel(
      gameId: 'live-no-spoilers',
      source: GameSource.supabase,
      whitePlayer: _player('White'),
      blackPlayer: _player('Black'),
      whiteTimeDisplay: '1:20',
      blackTimeDisplay: '1:15',
      whiteClockCentiseconds: 8000,
      blackClockCentiseconds: 7500,
      gameStatus: GameStatus.ongoing,
      roundId: 'round-live',
      tourId: 'tour-live',
      fen: _hydratedFen,
      lastMove: 'd1f3',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineSettingsProviderNew.overrideWith(_FakeEngineSettings.new),
          boardSettingsProviderNew.overrideWith(_FakeBoardSettings.new),
          eventNoSpoilersProvider.overrideWith(
            (ref, tourId) => _FakeEventNoSpoilersController(
              ref: ref,
              tourId: tourId,
              loadedState: const EventNoSpoilersState(
                enabled: true,
                isLoading: false,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: SizedBox(
                  width: 360,
                  child: ChessBoardFromFENNew(
                    gamesTourModel: live,
                    onChanged: () {},
                    pinnedIds: const [],
                    onPinToggle: (_) {},
                    allowStockfishFallback: false,
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

    expect(find.byType(EvaluationBarWidgetForGames), findsNothing);
  });
}
