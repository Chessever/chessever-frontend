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

  group('tobyTokenAtX', () {
    final extents = <({double left, double right})?>[
      (left: 0, right: 60),
      (left: 70, right: 130),
      null,
    ];
    test('picks the token under the tap', () {
      expect(tobyTokenAtX(extents, 30, slop: 8), 0);
      expect(tobyTokenAtX(extents, 100, slop: 8), 1);
    });
    test('picks the nearest token within the slop, in the gap too', () {
      expect(tobyTokenAtX(extents, 63, slop: 8), 0);
      expect(tobyTokenAtX(extents, 68, slop: 8), 1);
    });
    test('ignores taps far from any visible token', () {
      expect(tobyTokenAtX(extents, 200, slop: 8), isNull);
    });
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

  testWidgets('capsule centres each number in its share', (tester) async {
    final semantics = tester.ensureSemantics();
    ResponsiveHelper.initFromSize(const Size(390, 844));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: TobyWdlCapsule(
                wdl: TobyWdl(white: .32, draw: .38, black: .30),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      // The chances, then Toby's credit, which the capsule always carries.
      find.bySemanticsLabel('White 32, draw 38, Black 30. $kTobyAttribution'),
      findsOneWidget,
    );
    for (final label in ['32', '38', '30']) {
      final text = find.text(label);
      expect(text, findsOneWidget);
      final share = find
          .ancestor(of: text, matching: find.byType(Center))
          .first;
      final textCenter = tester.getCenter(text);
      final shareCenter = tester.getCenter(share);
      expect((textCenter.dx - shareCenter.dx).abs(), lessThan(0.5));
      expect((textCenter.dy - shareCenter.dy).abs(), lessThan(0.5));
    }
    semantics.dispose();
  });
}
