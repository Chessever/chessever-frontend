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

  group('TobyPredictsLine', () {
    List<TobyPredictionToken> tokens() => tobyPredictionTokens(
      _reading(const [
        TobyCandidate(uci: 'c4d4', san: 'Qxd4', probability: .88),
        TobyCandidate(uci: 'c4c2', san: 'Qxc2', probability: .11),
        TobyCandidate(uci: 'c6c5', san: 'c5', probability: .004),
      ]),
      _blackToMove24,
    );

    Future<void> pump(
      WidgetTester tester, {
      List<TobyPredictionToken>? moves,
      ValueChanged<TobyPredictionToken>? onMoveTap,
      // The test font draws every glyph a full em wide.
      double width = 900,
    }) async {
      ResponsiveHelper.initFromSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: TobyPredictsLine(
                wdl: const TobyWdl(white: .17, draw: .76, black: .07),
                tokens: moves ?? tokens(),
                onMoveTap: onMoveTap,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('reads "Toby Predicts: A or B or C" on one line', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Toby Predicts:'), findsOneWidget);
      // No "or" and no glyph between the moves: space alone.
      expect(find.text(' or'), findsNothing);
      final first = tester.getCenter(
        find.text('24…Qxd4 88%', findRichText: true),
      );
      for (final move in ['24…Qxc2 11%', '24…c5 <1%']) {
        expect(
          tester.getCenter(find.text(move, findRichText: true)).dy,
          first.dy,
        );
      }
      expect(find.text('Next move'), findsNothing);
    });

    testWidgets('puts the result chances under the moves', (tester) async {
      await pump(tester);
      for (final share in ['White 17%', 'Draw 76%', 'Black 7%']) {
        final chance = find.text(share, findRichText: true);
        expect(chance, findsOneWidget);
        expect(
          tester.getTopLeft(chance).dy,
          greaterThan(
            tester
                .getBottomLeft(find.text('24…Qxd4 88%', findRichText: true))
                .dy,
          ),
        );
      }
      expect(
        tester.getTopLeft(find.text('White 17%', findRichText: true)).dx,
        moreOrLessEquals(tester.getTopLeft(find.text('Toby Predicts:')).dx),
      );
    });

    testWidgets('holds one height: thinking, ready, out, long names', (
      tester,
    ) async {
      ResponsiveHelper.initFromSize(const Size(390, 844));
      Future<double> height(TobyPredictsLine line) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 358, child: line),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(TobyPredictsLine)).height;
      }

      const wdl = TobyWdl(white: .17, draw: .76, black: .07);
      final ready = await height(TobyPredictsLine(wdl: wdl, tokens: tokens()));
      expect(await height(const TobyPredictsLine(tokens: [])), ready);
      expect(
        await height(
          const TobyPredictsLine(wdl: wdl, tokens: [], waiting: false),
        ),
        ready,
      );
      expect(
        await height(
          TobyPredictsLine(
            white: (name: 'Vachier-Lagrave'),
            black: (name: 'Nepomniachtchi'),
            wdl: wdl,
            tokens: tokens(),
          ),
        ),
        ready,
      );
    });

    test('names a side by surname, else its colour', () {
      expect(tobySideName('Carlsen, Magnus', 'White'), 'Carlsen');
      expect(tobySideName('Gukesh D', 'White'), 'Gukesh D');
      expect(tobySideName('  ', 'Black'), 'Black');
      expect(tobySideName(null, 'Black'), 'Black');
    });

    testWidgets('a tapped move reports itself', (tester) async {
      TobyPredictionToken? tapped;
      await pump(tester, onMoveTap: (token) => tapped = token);
      await tester.tap(find.text('24…Qxc2 11%', findRichText: true));
      expect(tapped?.uci, 'c4c2');
    });

    testWidgets('says thinking while Toby reads a new position', (
      tester,
    ) async {
      await pump(tester, moves: const []);
      expect(find.text(' thinking…'), findsOneWidget);
    });

    testWidgets('"Toby Predicts:" is dashed and carries the credit', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      final label = tester.widget<Text>(find.text('Toby Predicts:'));
      expect(label.style?.decorationStyle, TextDecorationStyle.dashed);
      expect(
        find.bySemanticsLabel('Toby Predicts. $kTobyAttribution'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  test('the explanation names every outcome and the credit', () {
    final text = tobyChanceExplanation((white: 17, draw: 76, black: 7));
    expect(text, contains('White wins 17%'));
    expect(text, contains('draw 76%'));
    expect(text, contains('Black wins 7%'));
    expect(text, contains(kTobyAttribution));
    expect(tobyChanceExplanation(null), kTobyAttribution);
  });
}
