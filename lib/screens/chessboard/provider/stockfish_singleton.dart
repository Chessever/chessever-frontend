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
  final List<_EvalJob> _jobQueue = []; // Queue for pending evaluations
  final Map<String, _EvalJob> _pendingJobs = {}; // Keyed by cacheKey
  bool _isProcessing = false; // Flag to prevent concurrent processing
  static const int _maxQueueSize = 60; // Soft cap to avoid backlog

  Future<EnhancedCloudEval> evaluatePosition(
    String fen, {
    int depth = 20,
    bool prioritize = false,
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
      debugPrint('📦 CACHE HIT for $fen');
      return _evaluationCache[cacheKey]!;
    }

    if (prioritize) {
      await _purgeQueue();
    }

    // Deduplicate: if same job is current or pending, attach to it
    if (_currentJob?.key == cacheKey) {
      debugPrint('📋 QUEUE: Coalesced with CURRENT job for $fen');
      return _currentJob!.completer.future;
    }
    final pending = _pendingJobs[cacheKey];
    if (pending != null) {
      debugPrint('📋 QUEUE: Coalesced with PENDING job for $fen');
      return pending.completer.future;
    }

    // Create job and add to queue
    final completer = Completer<EnhancedCloudEval>();
    final job = _EvalJob(fen, depth, cacheKey, completer);

    _jobQueue.add(job);
    _pendingJobs[cacheKey] = job;
    debugPrint(
      '📋 QUEUE: Added job for $fen (queue size: ${_jobQueue.length})',
    );

    // Enforce soft cap: drop oldest overflow jobs safely
    while (_jobQueue.length > _maxQueueSize) {
      final dropped = _jobQueue.removeAt(0);
      _pendingJobs.remove(dropped.key);
      if (!dropped.completer.isCompleted) {
        dropped.completer.complete(
          EnhancedCloudEval(
            fen: dropped.fen,
            knodes: 0,
            depth: 0,
            pvs: [Pv(moves: '', cp: 0, mate: 0)],
            isCancelled: true,
          ),
        );
      }
      debugPrint('🗑️ QUEUE: Dropped overflow job for ${dropped.fen}');
    }

    // Start processing queue if not already processing
    if (!_isProcessing) {
      _processQueue();
    }

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

      _pendingJobs.remove(_currentJob!.key);

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

  Future<void> _purgeQueue() async {
    await _cancelCurrentEvaluation();

    if (_jobQueue.isNotEmpty) {
      for (final job in _jobQueue) {
        if (!job.completer.isCompleted) {
          job.completer.complete(
            EnhancedCloudEval(
              fen: job.fen,
              knodes: 0,
              depth: 0,
              pvs: [Pv(moves: '', cp: 0, mate: 0)],
              isCancelled: true,
            ),
          );
        }
      }
      _jobQueue.clear();
    }

    _pendingJobs.clear();

    // Wait until any in-flight processor finishes to avoid race conditions
    if (_isProcessing) {
      while (_isProcessing) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _jobQueue.isEmpty) return;

    _isProcessing = true;
    debugPrint(
      '🏭 QUEUE PROCESSOR: Starting, ${_jobQueue.length} jobs in queue',
    );

    while (_jobQueue.isNotEmpty) {
      final job = _jobQueue.removeAt(0);
      _currentJob = job;
      debugPrint('⚙️ PROCESSING: ${job.fen} (${_jobQueue.length} remaining)');
      await _processCurrentJob();
      _pendingJobs.remove(job.key);
      _currentJob = null;
    }

    _isProcessing = false;
    debugPrint('✅ QUEUE PROCESSOR: All jobs complete');
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

    debugPrint('🔍 STOCKFISH: Analyzing $fen');
    _currentSubscription = _engine!.stdout.listen((line) {
      // Check if this is still the current job
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

        final normalizedPvs = _normalizeToWhitePerspective(filteredPvs, fen);

        debugPrint(
          '✅ STOCKFISH COMPLETE: depth=$finalDepth, pvs=${filteredPvs.length}, knodes=$knodes',
        );
        if (filteredPvs.isEmpty) {
          debugPrint('⚠️ WARNING: No PVs found for $fen');
        } else {
          debugPrint(
            '   Best move: ${filteredPvs[0].moves.split(' ').first}, cp=${filteredPvs[0].cp}',
          );
        }

        final result = EnhancedCloudEval(
          fen: fen,
          knodes: knodes,
          depth: finalDepth,
          pvs: normalizedPvs.isEmpty ? [Pv(moves: '', cp: 0)] : normalizedPvs,
          isCancelled: false,
        );
        if (!completer.isCompleted) {
          completer.complete(result);
          _currentSubscription = null;
        }
      }
    });

    try {
      debugPrint('   → Sending: MultiPV 3, depth $depth');
      _engine!.stdin = 'setoption name MultiPV value 3';
      _engine!.stdin = 'position fen $fen';
      _engine!.stdin = 'go depth $depth';
    } catch (e) {
      debugPrint('❌ ERROR sending commands to Stockfish: $e');
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
        final normalizedPvs = _normalizeToWhitePerspective(filteredPvs, fen);
        final fallbackResult = EnhancedCloudEval(
          fen: fen,
          knodes: knodes,
          depth: finalDepth,
          pvs: normalizedPvs.isEmpty ? [Pv(moves: '', cp: 0)] : normalizedPvs,
          isCancelled: false,
        );
        completer.complete(fallbackResult);
        _currentJob = null;
        _currentSubscription?.cancel();
        _currentSubscription = null;
      }
    });

    // CRITICAL FIX: Wait for the completer to complete before returning
    // This ensures the queue processor doesn't move to the next job until this one is done
    await completer.future;
  }

  List<Pv> _normalizeToWhitePerspective(List<Pv> pvs, String fen) {
    if (pvs.isEmpty) return pvs;

    final fenParts = fen.split(' ');
    final isBlackToMove = fenParts.length >= 2 && fenParts[1] == 'b';
    if (!isBlackToMove) {
      return pvs
          .map(
            (pv) => Pv(
              moves: pv.moves,
              cp: pv.cp,
              isMate: pv.isMate,
              mate: pv.mate,
              whitePerspective: true,
            ),
          )
          .toList(growable: false);
    }

    return pvs
        .map(
          (pv) => Pv(
            moves: pv.moves,
            cp: -pv.cp,
            isMate: pv.isMate,
            mate: pv.mate != null ? -pv.mate! : null,
            whitePerspective: true,
          ),
        )
        .toList(growable: false);
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
    _jobQueue.clear();
    _isProcessing = false;
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
  final String key;
  final Completer<EnhancedCloudEval> completer;
  _EvalJob(this.fen, this.depth, this.key, this.completer);
}
