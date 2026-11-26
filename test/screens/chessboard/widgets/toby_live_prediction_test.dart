import 'package:chessever2/screens/chessboard/utils/engine_pv_palette.dart';
import 'package:chessever2/screens/chessboard/utils/pgn_comment_annotations.dart';
import 'package:chessever2/screens/chessboard/utils/toby_palette.dart';
import 'package:chessever2/screens/chessboard/widgets/toby_live_prediction.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/toby/toby_prediction.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TobyReading _reading(List<TobyCandidate> candidates, {bool isFinal = true}) =>
    TobyReading(
      isFinal: isFinal,
      sideToMove: Side.white,
      candidates: candidates,
      otherProbability: 0,
      otherMoveCount: 0,
      positionWdl: const TobyWdl(white: .28, draw: .57, black: .15),
    );

const _whiteToMove24 =
    'r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R w KQ - 0 24';
const _blackToMove24 =
    'r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R b KQ - 0 24';

void main() {
  group('tobyNumberedMove', () {
    test('numbers a White move with a dot', () {
      expect(tobyNumberedMove(_whiteToMove24, 'Nf6'), '24.Nf6');
    });
    test('numbers a Black move with an ellipsis (U+2026)', () {
      expect(tobyNumberedMove(_blackToMove24, 'Nf6'), '24…Nf6');
    });
    test('falls back to move 1 for a short or broken FEN', () {
      expect(tobyNumberedMove('8/8/8/8/8/8/8/8 w', 'Kd2'), '1.Kd2');
      expect(tobyNumberedMove('8/8/8/8/8/8/8/8 b - - 0 x', 'Kd2'), '1…Kd2');
    });
  });

  group('tobyPredictionTokens', () {
    test('keeps the three likeliest, most likely first, with chances', () {
      final reading = _reading(const [
        TobyCandidate(uci: 'c2c4', san: 'c4', probability: .07),
        TobyCandidate(uci: 'g1f3', san: 'Nf3', probability: .34),
        TobyCandidate(uci: 'e1g1', san: 'O-O', probability: .59),
        TobyCandidate(uci: 'a2a3', san: 'a3', probability: .004),
      ]);
      final tokens = tobyPredictionTokens(reading, _whiteToMove24);
      expect(tokens.map((t) => t.text), [
        '59% 24.O-O',
        '34% 24.Nf3',
        '7% 24.c4',
      ]);
      expect(tokens.map((t) => t.uci), ['e1g1', 'g1f3', 'c2c4']);
      expect(tokens.map((t) => t.san), ['O-O', 'Nf3', 'c4']);
      expect(tokens.map((t) => t.rank), [0, 1, 2]);
    });

    test('colours by rank: teal, coral, gold', () {
      final reading = _reading(const [
        TobyCandidate(uci: 'g1f3', san: 'Nf3', probability: .5),
        TobyCandidate(uci: 'c2c4', san: 'c4', probability: .3),
        TobyCandidate(uci: 'a2a3', san: 'a3', probability: .2),
      ]);
      final tokens = tobyPredictionTokens(reading, _whiteToMove24);
      expect(tokens.map((t) => t.hue), [kTobyTeal, kTobyCoral, kTobyGold]);
    });

    test('keeps payload order on equal chances and shows slivers as <1%', () {
      final reading = _reading(const [
        TobyCandidate(uci: 'g1f3', san: 'Nf3', probability: .004),
        TobyCandidate(uci: 'c2c4', san: '', probability: .004),
      ]);
      final tokens = tobyPredictionTokens(reading, _blackToMove24);
      expect(tokens.map((t) => t.text), ['<1% 24…Nf3', '<1% 24…c2c4']);
    });

    test('an empty reading has no tokens', () {
      expect(tobyPredictionTokens(_reading(const []), _whiteToMove24), isEmpty);
    });
  });

  test('the palette never reuses an engine, cyan or %cal colour', () {
    final taken = <int>{
      for (final color in enginePvVariantPalette)
        color.withValues(alpha: 1).toARGB32(),
      kPrimaryColor.toARGB32(),
      for (final code in ['G', 'Y', 'B', 'R', 'O'])
        pgnShapeColor(code).withValues(alpha: 1).toARGB32(),
    };
    expect(kTobyCandidatePalette.toSet(), hasLength(3));
    for (final hue in kTobyCandidatePalette) {
      expect(taken.contains(hue.toARGB32()), isFalse);
    }
  });

  group('tobyWdlSegmentWidths', () {
    const total = 180.0;
    double sum(List<double> w) => w.fold(0, (a, b) => a + b);

    test('is proportional when every share is wide enough', () {
      final widths = tobyWdlSegmentWidths(
        (white: 28, draw: 57, black: 15),
        total,
        minSegment: 6,
      );
      expect(widths[0], closeTo(50.4, 1e-9));
      expect(widths[1], closeTo(102.6, 1e-9));
      expect(widths[2], closeTo(27.0, 1e-9));
      expect(sum(widths), closeTo(total, 1e-9));
    });

    test('a 1% share keeps the minimum and the rest still add up', () {
      final widths = tobyWdlSegmentWidths(
        (white: 98, draw: 1, black: 1),
        total,
        minSegment: 6,
      );
      expect(widths[1], 6);
      expect(widths[2], 6);
      expect(widths[0], closeTo(168, 1e-9));
      expect(sum(widths), closeTo(total, 1e-9));
    });

    test('a zero share draws nothing', () {
      final widths = tobyWdlSegmentWidths(
        (white: 0, draw: 40, black: 60),
        total,
        minSegment: 6,
      );
      expect(widths[0], 0);
      expect(sum(widths), closeTo(total, 1e-9));
    });

    test('never overflows a tiny capsule', () {
      final widths = tobyWdlSegmentWidths(
        (white: 1, draw: 1, black: 98),
        12,
        minSegment: 6,
      );
      expect(sum(widths), closeTo(12, 1e-9));
      for (final w in widths) {
        expect(w, greaterThan(0));
      }
    });
  });

  test('tobyWdlSemantics reads the shares in order', () {
    expect(
      tobyWdlSemantics((white: 28, draw: 57, black: 15)),
      'White 28, draw 57, Black 15',
    );
  });

  group('tobyLivePredictionOpen', () {
    bool open({
      GameStatus status = GameStatus.ongoing,
      GameSource source = GameSource.supabase,
      bool tail = true,
      bool variation = false,
      bool preview = false,
      bool threats = false,
    }) => tobyLivePredictionOpen(
      status: status,
      source: source,
      isAtLiveTail: tail,
      isInAnalysisVariation: variation,
      isPvPreviewActive: preview,
      isThreatsMode: threats,
    );

    test('opens on a live broadcast game at its last move', () {
      expect(open(), isTrue);
    });
    test('stays shut otherwise', () {
      expect(open(status: GameStatus.whiteWins), isFalse);
      expect(open(status: GameStatus.draw), isFalse);
      expect(open(status: GameStatus.unknown), isFalse);
      expect(open(source: GameSource.savedAnalysis), isFalse);
      expect(open(source: GameSource.gamebase), isFalse);
      expect(open(tail: false), isFalse);
      expect(open(variation: true), isFalse);
      expect(open(preview: true), isFalse);
      expect(open(threats: true), isFalse);
    });
  });

  group('tobyArrowShape', () {
    final start = Chess.initial.fen;
    test('draws the tapped move on its own position', () {
      final arrow = tobyArrowShape((
        fen: start,
        uci: 'g1f3',
        color: kTobyCoral,
      ), start);
      expect(arrow, isNotNull);
      expect(arrow!.orig, Square.g1);
      expect(arrow.dest, Square.f3);
      expect(arrow.color, kTobyCoral.withValues(alpha: 0.85));
      expect(arrow.scale, 0.9);
    });
    test('draws nothing on another position or for an illegal move', () {
      const other =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
      expect(
        tobyArrowShape((fen: start, uci: 'g1f3', color: kTobyTeal), other),
        isNull,
      );
      expect(
        tobyArrowShape((fen: start, uci: 'e2e5', color: kTobyTeal), start),
        isNull,
      );
      expect(tobyArrowShape(null, start), isNull);
    });
  });

  group('TobyPredictsPanel', () {
    Future<void> pump(
      WidgetTester tester, {
      List<TobyPredictionToken>? tokens,
      bool thinking = false,
      String? selectedUci,
      ValueChanged<TobyPredictionToken>? onMoveTap,
    }) async {
      ResponsiveHelper.initFromSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 390,
                child: TobyPredictsPanel(
                  wdl: const TobyWdl(white: .17, draw: .76, black: .07),
                  tokens:
                      tokens ??
                      tobyPredictionTokens(
                        _reading(const [
                          TobyCandidate(
                            uci: 'c4d4',
                            san: 'Qxd4',
                            probability: .88,
                          ),
                          TobyCandidate(
                            uci: 'c4c2',
                            san: 'Qxc2',
                            probability: .11,
                          ),
                          TobyCandidate(
                            uci: 'c6c5',
                            san: 'c5',
                            probability: .004,
                          ),
                        ]),
                        _blackToMove24,
                      ),
                  thinking: thinking,
                  selectedUci: selectedUci,
                  onMoveTap: onMoveTap,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('names both rows and every outcome', (tester) async {
      await pump(tester);
      for (final text in ['Toby predicts', 'Result', 'Next move']) {
        expect(find.text(text), findsOneWidget);
      }
      for (final text in ['White 17%', 'Draw 76%', 'Black 7%']) {
        expect(find.text(text, findRichText: true), findsOneWidget);
      }
      for (final text in ['Qxd4  88%', 'Qxc2  11%', 'c5  <1%']) {
        expect(find.text(text, findRichText: true), findsOneWidget);
      }
    });

    testWidgets('moves read left to right from the legend\'s edge', (
      tester,
    ) async {
      await pump(tester);
      double left(String t) =>
          tester.getTopLeft(find.text(t, findRichText: true)).dx;
      expect(left('Qxd4  88%'), moreOrLessEquals(left('White 17%')));
      expect(left('Qxd4  88%'), lessThan(left('Qxc2  11%')));
      expect(left('Qxc2  11%'), lessThan(left('c5  <1%')));
      // The two row labels share one left edge.
      expect(
        tester.getTopLeft(find.text('Result')).dx,
        tester.getTopLeft(find.text('Next move')).dx,
      );
    });

    testWidgets('a move is a 44dp tap target that reports itself', (
      tester,
    ) async {
      TobyPredictionToken? tapped;
      await pump(tester, onMoveTap: (token) => tapped = token);
      final move = find.text('Qxc2  11%', findRichText: true);
      final target = find.ancestor(
        of: move,
        matching: find.byType(GestureDetector),
      );
      expect(tester.getSize(target.first).height, greaterThanOrEqualTo(44));
      await tester.tap(move);
      expect(tapped?.uci, 'c4c2');
    });

    testWidgets('says Toby is thinking while it reads a new position', (
      tester,
    ) async {
      await pump(tester, tokens: const [], thinking: true);
      expect(find.text('Toby is thinking…'), findsOneWidget);
      expect(find.text('White 17%', findRichText: true), findsOneWidget);
    });

    testWidgets('screen readers hear the chances and Toby\'s credit', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expect(
        find.bySemanticsLabel('Toby predicts. $kTobyAttribution'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Result chances: White 17, draw 76, Black 7'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('24…Qxd4, 88%'), findsOneWidget);
      semantics.dispose();
    });
  });
}
