import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

const _fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
const _finalFen =
    'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';

CloudEval _cloudEval(int cp, {String fen = _fen}) {
  return CloudEval(
    fen: fen,
    knodes: 0,
    depth: 12,
    pvs: [Pv(moves: 'e7e5', cp: cp)],
    requestedMultiPv: 1,
  );
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: 'GM',
    rating: 2700,
    countryCode: 'USA',
    team: null,
  );
}

GamesTourModel _game() {
  return GamesTourModel(
    gameId: 'game-1',
    whitePlayer: _player('White'),
    blackPlayer: _player('Black'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'round-1',
    tourId: 'tour-1',
    fen: _fen,
    lastMove: 'e2e4',
  );
}

Future<void> _pumpEvalBar(
  WidgetTester tester, {
  required bool allowStockfishFallback,
  required Future<CloudEval> Function() cacheOnlyEval,
  String fen = _fen,
  Future<CloudEval> Function(String fen)? stockfishEval,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gameCardEvalWithStockfishFallbackProvider.overrideWith(
          (ref, fen) =>
              stockfishEval?.call(fen) ??
              Future.value(_cloudEval(120, fen: fen)),
        ),
        gameCardEvalCacheOnlyProvider.overrideWith(
          (ref, fen) => cacheOnlyEval(),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: EvaluationBarWidgetForGames(
                width: 24,
                height: 240,
                fen: fen,
                playerView: PlayerView.listView,
                allowStockfishFallback: allowStockfishFallback,
              ),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _pumpChessProgressBar(
  WidgetTester tester, {
  required bool allowStockfishFallback,
  required Future<CloudEval> Function(String fen) fallbackEval,
  required Future<CloudEval> Function(String fen) cacheOnlyEval,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gameCardEvalWithStockfishFallbackProvider.overrideWith(
          (ref, fen) => fallbackEval(fen),
        ),
        gameCardEvalCacheOnlyProvider.overrideWith(
          (ref, fen) => cacheOnlyEval(fen),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: ChessProgressBar(
                gamesTourModel: _game(),
                allowStockfishFallback: allowStockfishFallback,
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// Mirrors production `_normalizedEvalToRatio` so tests can assert real
/// fill geometry without reimplementing the bar paint path.
double _expectedWhiteRatio(double evalPawns) {
  const scale = 3.0;
  const minRatio = 0.02;
  const maxRatio = 0.98;
  final clamped = evalPawns.clamp(-20.0, 20.0);
  final logistic = 1.0 / (1.0 + math.exp(-clamped / scale));
  return logistic.clamp(minRatio, maxRatio);
}

/// Bottom segment is white fill when the bar is not flipped.
double _bottomSegmentHeight(WidgetTester tester) {
  final bar = find.byType(EvaluationBarWidgetForGames);
  final aligns = find.descendant(of: bar, matching: find.byType(Align));
  Align? bottomAlign;
  for (final element in aligns.evaluate()) {
    final align = element.widget as Align;
    if (align.alignment == Alignment.bottomCenter) {
      bottomAlign = align;
      break;
    }
  }
  expect(bottomAlign, isNotNull, reason: 'expected bottom white segment Align');
  final box =
      tester.renderObject(
            find.descendant(
              of: find.byWidget(bottomAlign!),
              matching: find.byType(Container),
            ).first,
          )
          as RenderBox;
  return box.size.height;
}

void main() {
  testWidgets(
    'does not retain a previous-position eval after the FEN changes',
    (tester) async {
      final pendingFinalEval = Completer<CloudEval>();

      await _pumpEvalBar(
        tester,
        allowStockfishFallback: true,
        cacheOnlyEval: () async => _cloudEval(120),
        stockfishEval: (fen) async => _cloudEval(20, fen: fen),
      );
      await tester.pump();

      expect(find.text('+0.2'), findsOneWidget);

      await _pumpEvalBar(
        tester,
        fen: _finalFen,
        allowStockfishFallback: true,
        cacheOnlyEval: () => pendingFinalEval.future,
        stockfishEval: (_) => pendingFinalEval.future,
      );
      await tester.pump();

      expect(find.text('+0.2'), findsNothing);
      expect(find.text('...'), findsOneWidget);

      pendingFinalEval.complete(_cloudEval(450, fen: _finalFen));
      await tester.pumpAndSettle();

      expect(find.text('+4.5'), findsOneWidget);
      expect(find.text('...'), findsNothing);
    },
  );

  testWidgets('retains previous eval while scroll cache-only eval is loading', (
    tester,
  ) async {
    final pendingCacheOnly = Completer<CloudEval>();

    await _pumpEvalBar(
      tester,
      allowStockfishFallback: true,
      cacheOnlyEval: () => pendingCacheOnly.future,
    );
    await tester.pump();

    expect(find.text('+1.2'), findsOneWidget);

    await _pumpEvalBar(
      tester,
      allowStockfishFallback: false,
      cacheOnlyEval: () => pendingCacheOnly.future,
    );
    await tester.pump();

    expect(find.text('+1.2'), findsOneWidget);
    expect(find.text('...'), findsNothing);
  });

  testWidgets(
    'game-card eval bar uses SingleMotionBuilder and retains fill ratio on FEN change',
    (tester) async {
      final pendingFinalEval = Completer<CloudEval>();
      const barHeight = 240.0;
      // Large first eval so retained geometry is clearly away from neutral 0.5.
      const firstCp = 450; // +4.5
      const secondCp = -300; // -3.0

      await _pumpEvalBar(
        tester,
        allowStockfishFallback: true,
        cacheOnlyEval: () async => _cloudEval(firstCp),
        stockfishEval: (fen) async => _cloudEval(firstCp, fen: fen),
      );
      // Settle motion to the first eval target.
      await tester.pumpAndSettle();

      expect(find.text('+4.5'), findsOneWidget);
      expect(find.byType(SingleMotionBuilder), findsWidgets);

      final ratioFirst = _expectedWhiteRatio(4.5);
      final heightAfterFirst = _bottomSegmentHeight(tester);
      expect(
        heightAfterFirst,
        moreOrLessEquals(ratioFirst * barHeight, epsilon: 1.0),
        reason: 'settled white fill should match +4.5 ratio',
      );

      // New FEN, eval still loading — score text must not stick, geometry must.
      await _pumpEvalBar(
        tester,
        fen: _finalFen,
        allowStockfishFallback: true,
        cacheOnlyEval: () => pendingFinalEval.future,
        stockfishEval: (_) => pendingFinalEval.future,
      );
      await tester.pump();

      expect(find.text('+4.5'), findsNothing);
      expect(find.text('...'), findsOneWidget);

      final heightWhileLoading = _bottomSegmentHeight(tester);
      final neutralHeight = 0.5 * barHeight;
      expect(
        heightWhileLoading,
        moreOrLessEquals(heightAfterFirst, epsilon: 1.0),
        reason: 'fill ratio must retain previous target while new FEN loads',
      );
      expect(
        (heightWhileLoading - neutralHeight).abs(),
        greaterThan(20.0),
        reason: 'must not snap to neutral 0.5 while awaiting new eval',
      );

      pendingFinalEval.complete(_cloudEval(secondCp, fen: _finalFen));
      // One frame so the target updates; motion should be mid-flight.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final heightMid = _bottomSegmentHeight(tester);
      final ratioSecond = _expectedWhiteRatio(-3.0);
      final finalExpected = ratioSecond * barHeight;
      // Mid-animation: between old and new (or already near new on fast motion).
      final minH = math.min(heightAfterFirst, finalExpected);
      final maxH = math.max(heightAfterFirst, finalExpected);
      expect(
        heightMid,
        inInclusiveRange(minH - 1.0, maxH + 1.0),
        reason: 'animated height stays on the path between old and new ratio',
      );

      await tester.pumpAndSettle();
      expect(find.text('-3.0'), findsOneWidget);
      final heightFinal = _bottomSegmentHeight(tester);
      expect(
        heightFinal,
        moreOrLessEquals(finalExpected, epsilon: 1.0),
        reason: 'settled fill matches -3.0 ratio',
      );
    },
  );

  testWidgets('compact game progress bar uses game-card fallback provider', (
    tester,
  ) async {
    var fallbackRead = false;
    var cacheOnlyRead = false;

    await _pumpChessProgressBar(
      tester,
      allowStockfishFallback: true,
      fallbackEval: (fen) async {
        fallbackRead = true;
        expect(fen, _fen);
        return _cloudEval(120);
      },
      cacheOnlyEval: (fen) async {
        cacheOnlyRead = true;
        return _cloudEval(-50);
      },
    );
    await tester.pump();

    expect(fallbackRead, isTrue);
    expect(cacheOnlyRead, isFalse);
  });

  testWidgets('compact game progress bar can stay cache-only while scrolling', (
    tester,
  ) async {
    var fallbackRead = false;
    var cacheOnlyRead = false;

    await _pumpChessProgressBar(
      tester,
      allowStockfishFallback: false,
      fallbackEval: (fen) async {
        fallbackRead = true;
        return _cloudEval(120);
      },
      cacheOnlyEval: (fen) async {
        cacheOnlyRead = true;
        expect(fen, _fen);
        return _cloudEval(-50);
      },
    );
    await tester.pump();

    expect(fallbackRead, isFalse);
    expect(cacheOnlyRead, isTrue);
  });
}
