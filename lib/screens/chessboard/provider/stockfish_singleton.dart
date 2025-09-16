import 'dart:async';
import 'dart:ui';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:stockfish/stockfish.dart';

// Enhanced CloudEval class with cancellation support
class EnhancedCloudEval {
  final String fen;
  final int knodes;
  final int depth;
  final List<Pv> pvs;
  final bool isCancelled;
  
  const EnhancedCloudEval({
    required this.fen,
    required this.knodes,
    required this.depth,
    required this.pvs,
    this.isCancelled = false,
  });
}

class StockfishSingleton {
  StockfishSingleton._();
  static final StockfishSingleton _i = StockfishSingleton._();
  factory StockfishSingleton() => _i;

  Stockfish? _engine;
  _EvalJob? _currentJob;
  StreamSubscription? _currentSubscription;

  Future<EnhancedCloudEval> evaluatePosition(String fen, {int depth = 15}) async {
    // Cancel any ongoing evaluation
    await _cancelCurrentEvaluation();

    final completer = Completer<EnhancedCloudEval>();
    _currentJob = _EvalJob(fen, depth, completer);

    // Start the new evaluation
    _processCurrentJob();
    
    return completer.future;
  }

  Future<void> _cancelCurrentEvaluation() async {
    if (_currentJob != null) {
      // Cancel the current subscription
      await _currentSubscription?.cancel();
      _currentSubscription = null;

      // Complete the current job with a cancellation result
      if (!_currentJob!.completer.isCompleted) {
        final cancelledResult = EnhancedCloudEval(
          fen: _currentJob!.fen,
          knodes: 0,
          depth: 0,
          pvs: [Pv(moves: '', cp: 0,mate: 0)],
          isCancelled: true,
        );
        _currentJob!.completer.complete(cancelledResult);
      }

      // Send stop command to engine if it's ready
      if (_engine != null && _engine!.state.value == StockfishState.ready) {
        try {
          _engine!.stdin = 'stop';
          // Give the engine a moment to process the stop command
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          // Ignore errors when stopping
          print('Error sending stop command to Stockfish: $e');
        }
      }

      _currentJob = null;
    }
  }

  Future<void> _processCurrentJob() async {
    if (_currentJob == null) return;

    final job = _currentJob!;
    final fen = job.fen;
    final depth = job.depth;
    final completer = job.completer;

    // Ensure engine is ready
    if (_engine == null || _engine!.state.value != StockfishState.ready) {
      _engine?.dispose();
      _engine = Stockfish();
      await _waitUntilReady();
    }

    // Check if job was cancelled while waiting for engine
    if (_currentJob != job || completer.isCompleted) return;

    final List<Pv> pvs = [];
    int knodes = 0;
    int finalDepth = 0;
    bool evaluationComplete = false;

      print('stock fish ouptput for fen $fen');
    _currentSubscription = _engine!.stdout.listen((line) {
      // Check if this is still the current job  8/5ppk/2p4p/2p5/8/P1BQ2P1/qP2r2P/2KR4 b - - 4 34
      if (_currentJob != job || completer.isCompleted) return;
      line = line.trim();
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
        final pvMatch = RegExp(r'\bpv (.+)').firstMatch(line);
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
            final pv = Pv(moves: moves, cp: cp, isMate: true,mate: mate);
            if (pvs.isEmpty) {
              pvs.add(pv);
            } else {
              pvs[0] = pv; // Update main line
            }
          }
        }
      }

      // When analysis is complete
      if (line.startsWith('bestmove') && !evaluationComplete) {
        evaluationComplete = true;
        final result = EnhancedCloudEval(
          fen: fen,
          knodes: knodes,
          depth: finalDepth,
          pvs: pvs.isEmpty ? [Pv(moves: '', cp: 0)] : pvs,
          isCancelled: false,
        );
        if (!completer.isCompleted) {
          completer.complete(result);
          _currentJob = null;
          _currentSubscription = null;
        }
      }
    });

    try {
      _engine!.stdin = 'position fen $fen';
      _engine!.stdin = 'go depth $depth';
    } catch (e) {
      print('Error sending commands to Stockfish: $e');
      if (!completer.isCompleted) {
        final errorResult = EnhancedCloudEval(
          fen: fen,
          knodes: 0,
          depth: 0,
          pvs: [Pv(moves: '', cp: 0)],
          isCancelled: false,
        );
        completer.complete(errorResult);
        _currentJob = null;
        _currentSubscription = null;
      }
      return;
    }

    // Set up timeout
    Timer(const Duration(seconds: 10), () {
      if (_currentJob == job && !completer.isCompleted && !evaluationComplete) {
        final fallbackResult = EnhancedCloudEval(
          fen: fen,
          knodes: knodes,
          depth: finalDepth,
          pvs: pvs.isEmpty ? [Pv(moves: '', cp: 0)] : pvs,
          isCancelled: false,
        );
        completer.complete(fallbackResult);
        _currentJob = null;
        _currentSubscription?.cancel();
        _currentSubscription = null;
      }
    });
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
    _cancelCurrentEvaluation();
    _engine?.dispose();
    _engine = null;
  }
}

class _EvalJob {
  final String fen;
  final int depth;
  final Completer<EnhancedCloudEval> completer;
  _EvalJob(this.fen, this.depth, this.completer);
}
