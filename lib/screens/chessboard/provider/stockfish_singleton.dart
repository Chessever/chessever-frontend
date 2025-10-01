import 'dart:async';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:flutter/foundation.dart';
import 'package:stockfish/stockfish.dart';

// Enhanced CloudEval class with cancellation support
class EnhancedCloudEval {
  final String fen;
  final int knodes;
  final int depth;
  final List<Pv> pvs;
  final bool isCancelled;
  final bool fromWhitePerspective; // Track perspective for correct evaluation

  const EnhancedCloudEval({
    required this.fen,
    required this.knodes,
    required this.depth,
    required this.pvs,
    this.isCancelled = false,
    this.fromWhitePerspective = true,
  });
}

class StockfishSingleton {
  StockfishSingleton._();
  static final StockfishSingleton _i = StockfishSingleton._();
  factory StockfishSingleton() => _i;

  Stockfish? _engine;
  _EvalJob? _currentJob;
  StreamSubscription? _currentSubscription;
  final Map<String, EnhancedCloudEval> _evaluationCache = {};

  Future<EnhancedCloudEval> evaluatePosition(
    String fen, {
    int depth = 15,
  }) async {
    // Validate depth range
    if (depth < 1 || depth > 25) {
      throw ArgumentError('Depth must be between 1 and 25, got: $depth');
    }

    // Validate FEN string
    if (fen.isEmpty || fen.split(' ').length < 4) {
      throw ArgumentError('Invalid FEN string: $fen');
    }

    // Create cache key including side to move for perspective-aware caching
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length > 1 ? fenParts[1] : 'w';
    final cacheKey = '${fen}_${depth}_$sideToMove';

    if (_evaluationCache.containsKey(cacheKey)) {
      debugPrint('Returning cached evaluation for $fen');
      return _evaluationCache[cacheKey]!;
    }
    // Cancel any ongoing evaluation
    await _cancelCurrentEvaluation();

    final completer = Completer<EnhancedCloudEval>();
    _currentJob = _EvalJob(fen, depth, completer);

    // Start the new evaluation
    _processCurrentJob();

    final result = await completer.future;

    // Cache the result if it's valid
    if (!result.isCancelled && result.pvs.isNotEmpty) {
      _evaluationCache[cacheKey] = result;
    }

    return result;
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
          pvs: [Pv(moves: '', cp: 0, mate: 0)],
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
          debugPrint('Error sending stop command to Stockfish: $e');
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

    debugPrint('Stockfish output for fen $fen');
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

          var multipvIndex = 1;
          final multipvMatch = RegExp(r'multipv (\d+)').firstMatch(line);
          if (multipvMatch != null) {
            multipvIndex = int.parse(multipvMatch.group(1)!);
          }

          while (pvs.length < multipvIndex) {
            pvs.add(Pv(moves: '', cp: 0));
          }

          // Parse score (either cp or mate)
          final cpMatch = RegExp(r'score cp (-?\d+)').firstMatch(line);
          final mateMatch = RegExp(r'score mate (-?\d+)').firstMatch(line);

          if (cpMatch != null) {
            final cp = int.parse(cpMatch.group(1)!);
            final pv = Pv(moves: moves, cp: cp, isMate: false);
            pvs[multipvIndex - 1] = pv;
          } else if (mateMatch != null) {
            final mate = int.parse(mateMatch.group(1)!);
            final cp = mate.sign * 100000; // Convert mate to large cp value
            final pv = Pv(moves: moves, cp: cp, isMate: true, mate: mate);
            pvs[multipvIndex - 1] = pv;
          }
        }
      }

      // When analysis is complete
      if (line.startsWith('bestmove') && !evaluationComplete) {
        evaluationComplete = true;
        final filteredPvs = pvs
            .where((pv) => pv.moves.isNotEmpty)
            .toList(growable: false);
        final result = EnhancedCloudEval(
          fen: fen,
          knodes: knodes,
          depth: finalDepth,
          pvs: filteredPvs.isEmpty ? [Pv(moves: '', cp: 0)] : filteredPvs,
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
      _engine!.stdin = 'setoption name MultiPV value 3';
      _engine!.stdin = 'position fen $fen';
      _engine!.stdin = 'go depth $depth';
    } catch (e) {
      debugPrint('Error sending commands to Stockfish: $e');
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
        final filteredPvs = pvs
            .where((pv) => pv.moves.isNotEmpty)
            .toList(growable: false);
        final fallbackResult = EnhancedCloudEval(
          fen: fen,
          knodes: knodes,
          depth: finalDepth,
          pvs: filteredPvs.isEmpty ? [Pv(moves: '', cp: 0)] : filteredPvs,
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
    _evaluationCache.clear();
  }

  void clearCache() {
    debugPrint("🧹 CLEARING STOCKFISH EVALUATION CACHE");
    _evaluationCache.clear();
  }

  /// Force clear cache for debugging perspective issues
  void clearCacheForDebugging() {
    debugPrint("🧹 FORCE CLEARING ALL EVALUATION CACHES FOR DEBUGGING");
    _evaluationCache.clear();
  }
}

class _EvalJob {
  final String fen;
  final int depth;
  final Completer<EnhancedCloudEval> completer;
  _EvalJob(this.fen, this.depth, this.completer);
}
