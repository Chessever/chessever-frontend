import 'dart:async';

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

const _fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

CloudEval _cloudEval(int cp) {
  return CloudEval(
    fen: _fen,
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gameCardEvalWithStockfishFallbackProvider.overrideWith(
          (ref, fen) async => _cloudEval(120),
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
                fen: _fen,
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

void main() {
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
