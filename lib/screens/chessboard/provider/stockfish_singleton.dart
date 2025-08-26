import 'dart:async';
import 'dart:collection';
import 'dart:ui';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:stockfish/stockfish.dart';

class StockfishSingleton {
  StockfishSingleton._();
  static final StockfishSingleton _i = StockfishSingleton._();
  factory StockfishSingleton() => _i;

  Stockfish? _engine;
  final Queue<_EvalJob> _queue = Queue<_EvalJob>();
  bool _isWorking = false;

  Future<CloudEval> evaluatePosition(String fen, {int depth = 15}) async {
    final completer = Completer<CloudEval>();
    _queue.add(_EvalJob(fen, depth, completer));
    _processQueue();
    return completer.future;
  }

  Future<void> _processQueue() async {
    if (_isWorking || _queue.isEmpty) return;
    _isWorking = true;

    // Ensure engine is ready
    if (_engine == null || _engine!.state.value != StockfishState.ready) {
      _engine?.dispose();
      _engine = Stockfish();
      await _waitUntilReady();
    }

    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      final fen = job.fen;
      final depth = job.depth;
      final completer = job.completer;

      final List<Pv> pvs = [];
      int knodes = 0;
      int finalDepth = 0;

      final sub = _engine!.stdout.listen((line) {
        // Parse info lines for analysis data
        if (line.startsWith('info depth')) {
          final depthMatch = RegExp(r'depth (\d+)').firstMatch(line);
          if (depthMatch != null) {
            finalDepth = int.parse(depthMatch.group(1)!);
          }

          final knodesMatch = RegExp(r'nodes (\d+)').firstMatch(line);
          if (knodesMatch != null) {
            knodes = (int.parse(knodesMatch.group(1)!) / 1000).round();
          }

          // Parse score and moves for the principal variation
          final pvMatch = RegExp(r'pv (.+)').firstMatch(line);
          if (pvMatch != null) {
            final moves = pvMatch.group(1)!.trim();

            // Parse score (either cp or mate)
            final cpMatch = RegExp(r'score cp (-?\d+)').firstMatch(line);
            final mateMatch = RegExp(r'score mate (-?\d+)').firstMatch(line);

            if (cpMatch != null) {
              final cp = int.parse(cpMatch.group(1)!);
              final pv = Pv(moves: moves, cp: cp, isMate: false);
              // Replace or add the main PV (depth-based)
              if (pvs.isEmpty) {
                pvs.add(pv);
              } else {
                pvs[0] = pv; // Update main line
              }
            } else if (mateMatch != null) {
              final mate = int.parse(mateMatch.group(1)!);
              final cp = mate.sign * 100000; // Convert mate to large cp value
              final pv = Pv(moves: moves, cp: cp, isMate: true);
              if (pvs.isEmpty) {
                pvs.add(pv);
              } else {
                pvs[0] = pv; // Update main line
              }
            }
          }
        }

        // When analysis is complete
        if (line.startsWith('bestmove')) {
          final result = CloudEval(
            fen: fen,
            knodes: knodes,
            depth: finalDepth,
            pvs: pvs.isEmpty ? [Pv(moves: '', cp: 0)] : pvs,
          );
          if (!completer.isCompleted) completer.complete(result);
        }
      });

      _engine!.stdin = 'position fen $fen';
      _engine!.stdin = 'go depth $depth';

      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          final fallbackResult = CloudEval(
            fen: fen,
            knodes: knodes,
            depth: finalDepth,
            pvs: pvs.isEmpty ? [Pv(moves: '', cp: 0)] : pvs,
          );
          if (!completer.isCompleted) completer.complete(fallbackResult);
          return fallbackResult;
        },
      );

      sub.cancel();
    }

    _isWorking = false;
  }

  Future<void> _waitUntilReady() async {
    if (_engine!.state.value == StockfishState.ready) return;
    final completer = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (_engine!.state.value == StockfishState.ready) {
        _engine!.state.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      }
    };
    _engine!.state.addListener(listener);
    await completer.future;
  }

  void dispose() {
    _engine?.dispose();
    _engine = null;
  }
}

class _EvalJob {
  final String fen;
  final int depth;
  final Completer<CloudEval> completer;
  _EvalJob(this.fen, this.depth, this.completer);
}
