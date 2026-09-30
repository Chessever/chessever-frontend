// Regression cover for the Miniatures Games tab layout shift.
//
// Archive lists (Miniatures, gamebase search) render finished games that have
// no clock and no last move. Two things used to go wrong there:
//   1. the card grew or shrank a frame or two after first paint, because the
//      row height was derived from whatever async data happened to have landed
//      — which reflowed the whole sliver under the user, and
//   2. the fixed-height footer strip rendered completely empty.
//
// GameCard's sections are fixed-height (60.h header + 24.h footer), so the row
// height must be identical on the first pumped frame and after everything has
// settled, and `footerDetail` must fill the otherwise-blank footer.
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

GamesTourModel _archiveGame() {
  PlayerCard player(String name) => PlayerCard(
    name: name,
    federation: '',
    title: '',
    rating: 2600,
    countryCode: '',
    team: null,
  );

  return GamesTourModel(
    gameId: 'mini-1',
    source: GameSource.gamebase,
    whitePlayer: player('Morphy'),
    blackPlayer: player('Duke of Brunswick'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: 'gamebase-miniatures',
    // Archive rows carry an event *name* here, never a broadcast tour id.
    tourId: 'Paris Opera',
    eco: 'C41',
    boardNr: 17,
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  String? footerDetail,
  GamesTourModel? game,
  bool showEngineGauge = true,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Keeps the real settings load (and its sqlite init timeout timer) out
        // of the test; the card only reads showEngineGauge from it.
        engineSettingsProviderNew.overrideWith(
          () => _FakeEngineSettings(showEngineGauge: showEngineGauge),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: GameCard(
                  matchComparison: MatchWithComparison(
                    game: game ?? _archiveGame(),
                    comparison: MatchComparison.sameOrder,
                  ),
                  pinnedIds: const [],
                  onPinToggle: (_) {},
                  onTap: () {},
                  footerDetail: footerDetail,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _FakeEngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  _FakeEngineSettings({required this.showEngineGauge});

  final bool showEngineGauge;

  @override
  Future<EngineSettings> build() async =>
      EngineSettings(showEngineGaugeInGrid: showEngineGauge);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Drains the card's async work without pumpAndSettle, which never returns
/// while background retry timers keep rescheduling.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  final savedGame = _archiveGame().copyWith(
    source: GameSource.savedAnalysis,
    fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
    lastMove: 'e7e5',
  );

  testWidgets('a stored unfinished PGN stays unfinished and never says LIVE', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      game: savedGame.copyWith(
        source: GameSource.boardEditor,
        gameStatus: GameStatus.ongoing,
      ),
      showEngineGauge: false,
    );
    await _settle(tester);
    expect(find.text('LIVE'), findsNothing);
    expect(find.text('*'), findsOneWidget);
    expect(find.text('--:--'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recorded PGN clocks remain static on an unfinished position', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      game: savedGame.copyWith(
        source: GameSource.boardEditor,
        gameStatus: GameStatus.ongoing,
        whiteTimeDisplay: '05:00',
        whiteClockSeconds: 300,
        whiteClockCentiseconds: 30000,
        lastMoveTime: DateTime.now(),
      ),
      showEngineGauge: false,
    );
    await _settle(tester);
    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('04:50'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a started saved game shows moves without missing-clock placeholders',
    (tester) async {
      await _pumpCard(tester, game: savedGame);
      await _settle(tester);
      expect(find.text('--:--'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a saved game displays recorded zero and hides an unknown side', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      game: savedGame.copyWith(whiteClockSeconds: 0, whiteTimeDisplay: '00:00'),
    );
    await _settle(tester);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('--:--'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archive card height does not change once async data settles', (
    tester,
  ) async {
    await _pumpCard(tester, footerDetail: 'Paris Opera  ·  C41  ·  17 moves');

    final firstFrame = tester.getSize(find.byType(GameCard));

    // Let every provider the card touches resolve. pumpAndSettle is not usable
    // here: the settings/sqlite providers schedule their own retry timers, so
    // the tree never reaches a quiescent state.
    await _settle(tester);
    final settled = tester.getSize(find.byType(GameCard));

    expect(settled.height, firstFrame.height);
  });

  testWidgets('footerDetail fills the footer strip archive games leave blank', (
    tester,
  ) async {
    await _pumpCard(tester);
    await _settle(tester);
    expect(find.text('Paris Opera  ·  C41  ·  17 moves'), findsNothing);

    await _pumpCard(tester, footerDetail: 'Paris Opera  ·  C41  ·  17 moves');
    await _settle(tester);
    expect(find.text('Paris Opera  ·  C41  ·  17 moves'), findsOneWidget);
  });
}
