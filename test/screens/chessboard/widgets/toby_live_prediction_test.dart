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

TobyReading _reading(
  List<TobyCandidate> candidates, {
  bool isFinal = true,
  Side sideToMove = Side.white,
}) => TobyReading(
  isFinal: isFinal,
  sideToMove: sideToMove,
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

  group('tobyLivePredictionOpen', () {
    bool open({
      GameSource source = GameSource.supabase,
      bool preview = false,
      bool threats = false,
    }) => tobyLivePredictionOpen(
      source: source,
      isPvPreviewActive: preview,
      isThreatsMode: threats,
    );

    test('opens on any position of a broadcast game, live or finished', () {
      expect(open(), isTrue);
    });
    test('stays shut off broadcasts, under a preview and in threats', () {
      expect(open(source: GameSource.savedAnalysis), isFalse);
      expect(open(source: GameSource.gamebase), isFalse);
      expect(open(preview: true), isFalse);
      expect(open(threats: true), isFalse);
    });
  });

  group('tobyOverWdl', () {
    test('checkmate: the side that mated wins', () {
      // Fool's mate, White to move and mated.
      expect(
        tobyOverWdl(
          'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3',
        )?.percentages,
        (white: 0, draw: 0, black: 100),
      );
    });
    test('stalemate is a draw', () {
      expect(tobyOverWdl('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1')?.percentages, (
        white: 0,
        draw: 100,
        black: 0,
      ));
    });
    test('a playable position is not over', () {
      expect(tobyOverWdl(Chess.initial.fen), isNull);
    });
  });

  group('Toby vertical evaluation bar', () {
    final gauge = find.byType(TobyOutcomeBar);

    Future<void> pumpGauge(
      WidgetTester tester, {
      double width = 34,
      double textScale = 1,
      bool whiteFirst = false,
      TobyWdl? outcome = const TobyWdl(white: .75, draw: .23, black: .02),
    }) async {
      ResponsiveHelper.initFromSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: SizedBox(
                  width: width,
                  height: 200,
                  child: TobyOutcomeBar(
                    axis: Axis.vertical,
                    outcome: outcome,
                    whiteFirst: whiteFirst,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'prints fitting outcomes with a slate draw fill and light ink',
      (tester) async {
        await pumpGauge(tester);
        expect(find.text('75'), findsOneWidget);
        expect(find.text('23'), findsOneWidget);
        expect(find.text('2'), findsNothing);
        final segments = tester.widgetList<ColoredBox>(
          find.descendant(of: gauge, matching: find.byType(ColoredBox)),
        );
        final colors = segments.map((box) => box.color).toList();
        expect(colors, const [
          Color(0xFF151619),
          Color(0xFF4C5D77),
          Color(0xFFE9E9E9),
        ]);
        expect(tester.widget<Text>(find.text('23')).style?.color, Colors.white);
        expect(
          tester.getCenter(find.text('23')).dy,
          lessThan(tester.getCenter(find.text('75')).dy),
        );
        await pumpGauge(tester, whiteFirst: true);
        expect(
          tester.getCenter(find.text('23')).dy,
          greaterThan(tester.getCenter(find.text('75')).dy),
        );
        expect(tester.getSize(gauge), const Size(34, 200));
      },
    );

    testWidgets('hides labels at large text scale without widening the rail', (
      tester,
    ) async {
      await pumpGauge(tester, width: 20, textScale: 3);
      expect(find.text('75'), findsNothing);
      expect(find.text('23'), findsNothing);
      expect(tester.getSize(gauge), const Size(20, 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap reveals all outcomes including the unlabeled sliver', (
      tester,
    ) async {
      await pumpGauge(tester);
      await tester.tap(gauge);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          RegExp(
            r'White wins 75%.*Draw 23%.*Black wins 2%',
            caseSensitive: false,
          ),
        ),
        findsOneWidget,
      );
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
    List<TobyPredictionToken> tokens({Side mover = Side.black}) =>
        tobyPredictionTokens(
          _reading(const [
            TobyCandidate(
              uci: 'c4d4',
              san: 'Qxd4',
              probability: .88,
              wdl: TobyWdl(white: .25, draw: .69, black: .06),
            ),
            TobyCandidate(
              uci: 'c4c2',
              san: 'Qxc2',
              probability: .11,
              wdl: TobyWdl(white: .35, draw: .59, black: .06),
            ),
            TobyCandidate(uci: 'c6c5', san: 'c5', probability: .004),
          ], sideToMove: mover),
          mover == Side.black ? _blackToMove24 : _whiteToMove24,
        );

    Future<void> pump(
      WidgetTester tester, {
      List<TobyPredictionToken>? moves,
      ValueChanged<TobyPredictionToken>? onMoveTap,
      VoidCallback? onSettingsTap,
      double textScale = 1,
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
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: TobyPredictsLine(
                  wdl: const TobyWdl(white: .17, draw: .76, black: .07),
                  tokens: moves ?? tokens(),
                  onMoveTap: onMoveTap,
                  onSettingsTap: onSettingsTap,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows three aligned move and likelihood rows on a phone', (
      tester,
    ) async {
      await pump(tester, width: 320);
      expect(find.text('Toby'), findsOneWidget);
      expect(find.text('Toby Predicts:'), findsNothing);
      final moves = ['24…Qxd4', '24…Qxc2', '24…c5'];
      final chances = ['88%', '11%', '<1%'];
      var previousY = 0.0;
      for (var i = 0; i < moves.length; i++) {
        final move = tester.getTopLeft(find.text(moves[i]));
        final chance = tester.getTopLeft(find.text(chances[i]));
        expect(move.dy, greaterThan(previousY));
        expect(move.dy, closeTo(chance.dy, 3));
        expect(move.dx, lessThan(chance.dx));
        previousY = move.dy;
      }
      expect(find.text('Next move'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'only tapped candidate reveals its outcome and expected score',
      (tester) async {
        await pump(tester, width: 320);
        const first =
            'White wins 25% · Draw 69% · Black wins 6%\n'
            'Black expected score 40.5%';
        const second =
            'White wins 35% · Draw 59% · Black wins 6%\n'
            'Black expected score 35.5%';
        expect(find.text(first), findsNothing);
        expect(find.text(second), findsNothing);
        final firstBar = find.byTooltip(first);
        final secondBar = find.byTooltip(second);
        expect(firstBar, findsOneWidget);
        expect(secondBar, findsOneWidget);
        final semantics = tester.ensureSemantics();
        expect(
          find.bySemanticsLabel(RegExp(r'^Outcomes for 24…c5')),
          findsNothing,
        );
        expect(find.text('—'), findsOneWidget);
        semantics.dispose();
        final sizes = tester.widgetList<Expanded>(
          find.descendant(of: firstBar, matching: find.byType(Expanded)),
        );
        expect(sizes.map((widget) => widget.flex), [2500, 6900, 600]);
        expect(
          tester.getCenter(firstBar).dy,
          closeTo(tester.getCenter(find.text('24…Qxd4')).dy, 2),
        );
        await tester.tap(firstBar);
        await tester.pumpAndSettle();
        expect(find.text(first, findRichText: true), findsOneWidget);
        expect(find.text(second), findsNothing);
        expect(find.text('White 17%', findRichText: true), findsNothing);
      },
    );

    testWidgets('holds one height through loading and unavailable states', (
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
    });

    testWidgets('fits large text in a narrow phone panel', (tester) async {
      await pump(tester, width: 240, textScale: 2, onSettingsTap: () {});
      expect(find.text('24…Qxd4'), findsOneWidget);
      expect(find.byTooltip('Engine settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('gear invokes the engine settings action', (tester) async {
      var opened = 0;
      await pump(tester, onSettingsTap: () => opened++);
      final gear = find.byTooltip('Engine settings');
      expect(tester.getSize(gear), const Size(44, 44));
      await tester.tap(gear);
      expect(opened, 1);
    });

    testWidgets('reports the expected score from the side to move', (
      tester,
    ) async {
      await pump(tester, moves: tokens(mover: Side.white));
      expect(
        find.byTooltip(
          'White wins 25% · Draw 69% · Black wins 6%\n'
          'White expected score 59.5%',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a tapped move reports itself', (tester) async {
      TobyPredictionToken? tapped;
      await pump(tester, onMoveTap: (token) => tapped = token);
      await tester.tap(find.text('24…Qxc2'));
      expect(tapped?.uci, 'c4c2');
    });

    testWidgets('says game over where the game ended', (tester) async {
      ResponsiveHelper.initFromSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: TobyPredictsLine(
              wdl: TobyWdl(white: 1, draw: 0, black: 0),
              tokens: [],
              note: 'Game over',
            ),
          ),
        ),
      );
      expect(find.text('Game over'), findsOneWidget);
      expect(find.text('White 100%', findRichText: true), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'^Game result\. White wins 100%')),
        findsOneWidget,
      );
    });

    testWidgets('says thinking while Toby reads a new position', (
      tester,
    ) async {
      await pump(tester, moves: const []);
      expect(find.text('Thinking…'), findsOneWidget);
    });

    testWidgets('the Toby title opens its credit without adding inline copy', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expect(find.textContaining(kTobyAttribution), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^About Toby\.')), findsOneWidget);
      await tester.tap(find.text('Toby'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(kTobyAttribution, findRichText: true),
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
