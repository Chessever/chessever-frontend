// Regression: team-event list cards (comparison.oppositeOrder) mirror the
// compact card so the anchored team stays on the left. The middle eval bar
// must mirror with it: white's share keeps its length and colour but grows
// from the right edge, where the white player now sits.
//
// The old reversed mode inverted the value (`1 - eval`) on top of the flipped
// anchor. Those two flips cancelled out, so the fill still tracked the same
// side as the unflipped card — a team event with White +4.0 rendered a 90 %
// black bar on the left player.
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

GamesTourModel _game() => GamesTourModel(
  gameId: 'g1',
  roundId: 'round-1',
  tourId: 'tour-1',
  whitePlayer: PlayerCard(
    name: 'White',
    federation: '',
    title: '',
    rating: 2000,
    countryCode: '',
    team: null,
  ),
  blackPlayer: PlayerCard(
    name: 'Black',
    federation: '',
    title: '',
    rating: 2000,
    countryCode: '',
    team: null,
  ),
  whiteTimeDisplay: '--:--',
  blackTimeDisplay: '--:--',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.ongoing,
  fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
);

CloudEval _cloudEval(int cp) => CloudEval(
  fen: '',
  knodes: 0,
  depth: 20,
  pvs: [Pv(moves: 'e2e4', cp: cp)],
  requestedMultiPv: 1,
);

class _BarHost extends StatelessWidget {
  const _BarHost({required this.reversed});

  final bool reversed;

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return Scaffold(
      body: Center(
        child:
            reversed
                ? ChessProgressBar.reversedMode(
                  gamesTourModel: _game(),
                  allowStockfishFallback: false,
                )
                : ChessProgressBar(
                  gamesTourModel: _game(),
                  allowStockfishFallback: false,
                ),
      ),
    );
  }
}

Future<({double fillWidth, Alignment alignment, double barWidth})> _pumpBar(
  WidgetTester tester, {
  required bool reversed,
  required int cp,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gameCardEvalCacheOnlyProvider.overrideWith(
          (ref, fen) async => _cloudEval(cp),
        ),
        gameCardEvalWithStockfishFallbackProvider.overrideWith(
          (ref, fen) async => _cloudEval(cp),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: _BarHost(reversed: reversed),
      ),
    ),
  );
  // Drain the eval future and the 500 ms fill animation.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final align = tester.widget<Align>(
    find
        .ancestor(
          of: find.byType(AnimatedContainer),
          matching: find.byType(Align),
        )
        .first,
  );
  return (
    fillWidth: tester.getSize(find.byType(AnimatedContainer)).width,
    alignment: align.alignment as Alignment,
    barWidth: tester.getSize(find.byType(ChessProgressBar)).width,
  );
}

void main() {
  testWidgets(
    'reversed bar mirrors white share to the right instead of inverting it',
    (tester) async {
      // cp +400 → white share 0.9. White sits on the right of a flipped card.
      final natural = await _pumpBar(tester, reversed: false, cp: 400);
      final reversed = await _pumpBar(tester, reversed: true, cp: 400);

      expect(natural.alignment, Alignment.centerLeft);
      expect(reversed.alignment, Alignment.centerRight);
      expect(
        reversed.fillWidth,
        closeTo(natural.fillWidth, 0.01),
        reason: 'mirrored bar keeps white\'s share, only its edge flips',
      );
      expect(
        reversed.fillWidth,
        closeTo(reversed.barWidth * 0.9, 0.01),
        reason:
            'White +4.0 must fill 90 % of the bar, not the inverted 10 %',
      );
    },
  );

  testWidgets('reversed bar gives a black-favouring eval a short white fill', (
    tester,
  ) async {
    // cp -400 → white share 0.1. The right (white) player leads a thin bar.
    final reversed = await _pumpBar(tester, reversed: true, cp: -400);

    expect(reversed.alignment, Alignment.centerRight);
    expect(reversed.fillWidth, closeTo(reversed.barWidth * 0.1, 0.01));
  });
}
