import 'dart:async';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:flutter/foundation.dart';
import 'package:stockfish/stockfish.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';

// Enhanced CloudEval class with cancellation support
class EnhancedCloudEval {
  final String fen;
  final int knodes;
  final int depth;
  final List<Pv> pvs;
  final bool isCancelled;
  final bool fromWhitePerspective; // Track perspective for correct evaluation
  final int? requestedMultiPv;

  const EnhancedCloudEval({
    required this.fen,
    required this.knodes,
    required this.depth,
    required this.pvs,
    this.isCancelled = false,
    this.fromWhitePerspective = true,
    this.requestedMultiPv,
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
    int depth = 15,
    Duration? searchDuration,
    int? maxDepth,
    int multiPV = 3,
    Function(int depth, int knodes)? onDepthUpdate,
    Function(List<Pv> pvs, int depth)? onPvUpdate,
    bool isCurrentPosition =
        false, // Priority flag for user's currently viewed position
    bool allowCache = true,
  }) async {
    // Validate depth range (only if using depth-based search)
    if (searchDuration == null && (depth < 1 || depth > 99)) {
      throw ArgumentError('Depth must be between 1 and 99, got: $depth');
    }

    // Validate FEN string
    if (fen.isEmpty || fen.split(' ').length < 4) {
      throw ArgumentError('Invalid FEN string: $fen');
    }

    // Create cache key including side to move for perspective-aware caching
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length > 1 ? fenParts[1] : 'w';
    final searchMode =
        searchDuration != null
            ? 'time_${searchDuration.inMilliseconds}'
            : 'depth_$depth';
    final cacheKey = '${fen}_${searchMode}_pv${multiPV}_$sideToMove';

    if (allowCache && _evaluationCache.containsKey(cacheKey)) {
      debugPrint('📦 CACHE HIT for $fen');
      return _evaluationCache[cacheKey]!;
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

    // If this is the active board position, cancel any in-progress job for a different FEN
    if (isCurrentPosition &&
        _currentJob != null &&
        _currentJob!.fen != fen &&
        !_currentJob!.completer.isCompleted) {
      debugPrint(
        '🛑 QUEUE: Cancelling in-flight evaluation for ${_currentJob!.fen} → new position $fen',
      );
      await _cancelCurrentEvaluation();
    }

    // Remove pending duplicate current-position jobs to avoid stale searches
    if (isCurrentPosition && _jobQueue.isNotEmpty) {
      _jobQueue.removeWhere((job) {
        final shouldDrop = job.isCurrentPosition && job.fen != fen;
        if (shouldDrop) {
          _pendingJobs.remove(job.key);
          if (!job.completer.isCompleted) {
            job.completer.complete(
              EnhancedCloudEval(
                fen: job.fen,
                knodes: 0,
                depth: 0,
                pvs: [Pv(moves: '', cp: 0, mate: 0)],
                isCancelled: true,
                requestedMultiPv: job.multiPV,
              ),
            );
          }
          debugPrint('🗑️ QUEUE: Dropped pending job for ${job.fen}');
        }
        return shouldDrop;
      });
    }

    // Create job and add to queue
    final completer = Completer<EnhancedCloudEval>();
    final job = _EvalJob(
      fen,
      depth,
      cacheKey,
      completer,
      searchDuration: searchDuration,
      maxDepth: maxDepth,
      multiPV: multiPV,
      onDepthUpdate: onDepthUpdate,
      onPvUpdate: onPvUpdate,
      isCurrentPosition: isCurrentPosition,
      allowCache: allowCache,
    );

    // PRIORITY: Insert high-priority jobs at the front, low-priority at the back
    if (isCurrentPosition) {
      _jobQueue.insert(0, job); // Current position gets highest priority
      debugPrint('🔥 PRIORITY: Current position job inserted at front');
    } else {
      _jobQueue.add(job); // Background jobs go to the back
    }
    _pendingJobs[cacheKey] = job;
    debugPrint(
      '📋 QUEUE: Added job for $fen (queue size: ${_jobQueue.length}, priority: ${isCurrentPosition ? "HIGH" : "low"})',
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
            requestedMultiPv: dropped.multiPV,
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

    // Cache the result if it's valid (has actual moves, not just empty PVs)
    // CRITICAL: Don't cache timeout results with empty/partial PVs
    if (job.allowCache &&
        !result.isCancelled &&
        result.pvs.isNotEmpty &&
        result.pvs.first.moves.isNotEmpty) {
      _evaluationCache[cacheKey] = result;
      debugPrint(
        '✅ CACHED: Stockfish eval for $fen (depth=${result.depth}, cp=${result.pvs.first.cp})',
      );
    } else if (result.pvs.isEmpty || result.pvs.first.moves.isEmpty) {
      debugPrint(
        '⚠️ NOT CACHED: Stockfish returned empty/partial result for $fen',
      );
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
          requestedMultiPv: _currentJob!.multiPV,
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

  Future<void> cancelAllEvaluations() async {
    await _cancelCurrentEvaluation();
    if (_jobQueue.isNotEmpty) {
      for (final job in _jobQueue) {
        _pendingJobs.remove(job.key);
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
    _isProcessing = false;
    _currentSubscription = null;
    try {
      _engine?.stdin = 'stop';
    } catch (_) {}
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _jobQueue.isEmpty) return;

    _isProcessing = true;
    debugPrint(
      '🏭 QUEUE PROCESSOR: Starting, ${_jobQueue.length} jobs in queue',
    );

    try {
      while (_jobQueue.isNotEmpty) {
        final job = _jobQueue.removeAt(0);
        _currentJob = job;
        debugPrint('⚙️ PROCESSING: ${job.fen} (${_jobQueue.length} remaining)');
        try {
          await _processCurrentJob();
        } catch (e, st) {
          debugPrint('❌ QUEUE PROCESSOR: Job failed for ${job.fen}: $e');
          debugPrint('$st');
          await _resetEngineAfterFailure();
        } finally {
          _pendingJobs.remove(job.key);
          _currentJob = null;
        }
      }
    } finally {
      _isProcessing = false;
      if (_jobQueue.isNotEmpty) {
        debugPrint(
          '⚠️ QUEUE PROCESSOR: Aborted with ${_jobQueue.length} pending jobs',
        );
      } else {
        debugPrint('✅ QUEUE PROCESSOR: All jobs complete');
      }
    }
  }

  Future<void> _processCurrentJob() async {
    if (_currentJob == null) return;

    final job = _currentJob!;
    final fen = job.fen;
    final depth = job.depth;
    final searchDuration = job.searchDuration;
    final maxDepth = job.maxDepth;
    final multiPV = job.multiPV;
    final onDepthUpdate = job.onDepthUpdate;
    final completer = job.completer;

    try {
      // Ensure engine is ready and reset for fresh search
      await _ensureEngineReady();
      await _softResetEngine();

      // Check if job was cancelled while waiting for engine
      if (_currentJob != job || completer.isCompleted) return;

      final List<Pv> pvs = [];
      int knodes = 0;
      int finalDepth = 0;
      bool evaluationComplete = false;
      int lastPvUpdateDepthReported = 0;

      final isDynamicSearch = searchDuration != null;
      debugPrint(
        '🔍 STOCKFISH: Analyzing $fen ${isDynamicSearch ? "(dynamic ${searchDuration.inSeconds}s)" : "(depth $depth)"}',
      );

      _currentSubscription = _engine!.stdout.listen((line) {
        // Check if this is still the current job
        if (_currentJob != job || completer.isCompleted) return;
        line = line.trim();
        // TEMPO-01-COMMENT
        // debugPrint('🟢 STOCKFISH STDOUT: $line');
        // Parse info lines for analysis data
        if (line.startsWith('info depth')) {
          final depthMatch = RegExp(r'depth (\d+)').firstMatch(line);
          final knodesMatch = RegExp(r'nodes (\d+)').firstMatch(line);

          if (depthMatch != null) {
            final currentDepth = int.parse(depthMatch.group(1)!);
            final int currentKnodes =
                knodesMatch != null
                    ? (int.parse(knodesMatch.group(1)!) / 1000).round()
                    : 0;

            finalDepth = currentDepth;

            if (onDepthUpdate != null) {
              onDepthUpdate(currentDepth, currentKnodes);
            }
          }

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

          // Emit PV snapshot updates once per increased depth
          if (job.onPvUpdate != null &&
              finalDepth > lastPvUpdateDepthReported) {
            final snapshot = pvs
                .where((pv) => pv.moves.isNotEmpty)
                .toList(growable: false);
            if (snapshot.isNotEmpty) {
              try {
                job.onPvUpdate!(snapshot, finalDepth);
                lastPvUpdateDepthReported = finalDepth;
              } catch (_) {
                // Ignore callback errors
              }
            }
          }
        }

        // When analysis is complete
        if (line.startsWith('bestmove') && !evaluationComplete) {
          evaluationComplete = true;
          final filteredPvs = pvs
              .where((pv) => pv.moves.isNotEmpty)
              .toList(growable: false);

          // CRITICAL: Check if depth is 0 (no info lines parsed)
          if (finalDepth == 0) {
            if (filteredPvs.isNotEmpty) {
              debugPrint(
                '⚠️ BESTMOVE without info depth - setting fallback depth',
              );
              // Fallback to at least the minimum report depth to avoid UI getting stuck
              final minimum = EngineSearchProgress.minReportDepth;
              finalDepth = depth < minimum ? minimum : depth;
            } else {
              debugPrint(
                '❌ CRITICAL: Stockfish returned NO depth info AND NO PVs for $fen',
              );
              debugPrint(
                '   Requested: ${isDynamicSearch ? "dynamic ${searchDuration.inSeconds}s" : "depth $depth"}',
              );
              debugPrint('   Last UCI line: $line');
              debugPrint(
                '   This might be an invalid position or engine error',
              );
            }
          }

          debugPrint(
            '♟️ STOCKFISH RAW PVs (@depth=$finalDepth): ${filteredPvs.map((pv) => pv.moves).join(' | ')}',
          );
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

          if (onDepthUpdate != null && finalDepth > 0) {
            onDepthUpdate(finalDepth, knodes);
          }

          final result = EnhancedCloudEval(
            fen: fen,
            knodes: knodes,
            depth: finalDepth,
            pvs: normalizedPvs.isEmpty ? [Pv(moves: '', cp: 0)] : normalizedPvs,
            isCancelled: false,
            requestedMultiPv: job.multiPV,
          );
          if (!completer.isCompleted) {
            completer.complete(result);
            unawaited(_currentSubscription?.cancel());
            _currentSubscription = null;
          }
        }
      });

      try {
        // PERFORMANCE FIX: Removed 'ucinewgame' - it clears hash before EVERY position
        // This was causing depth 0 bugs and killing performance
        // The working commit (a85edea1a0ded3f1772efb3baf1756c793c054b0) didn't use ucinewgame
        // Stockfish is smart enough to handle position changes without clearing hash

        _engine!.stdin = 'setoption name MultiPV value $multiPV';
        _engine!.stdin = 'position fen $fen';

        if (isDynamicSearch) {
          final moveTimeMs = searchDuration.inMilliseconds;
          debugPrint(
            '   → Sending: MultiPV $multiPV, movetime ${moveTimeMs}ms${maxDepth != null ? ", depth $maxDepth" : ""}',
          );
          if (maxDepth != null) {
            _engine!.stdin = 'go movetime $moveTimeMs depth $maxDepth';
          } else {
            _engine!.stdin = 'go movetime $moveTimeMs';
          }
        } else {
          debugPrint('   → Sending: MultiPV $multiPV, depth $depth');
          _engine!.stdin = 'go depth $depth';
        }
      } catch (e) {
        debugPrint('❌ ERROR sending commands to Stockfish: $e');
        if (!completer.isCompleted) {
          final errorResult = EnhancedCloudEval(
            fen: fen,
            knodes: 0,
            depth: 0,
            pvs: [Pv(moves: '', cp: 0)],
            isCancelled: false,
            requestedMultiPv: job.multiPV,
          );
          completer.complete(errorResult);
          _currentJob = null;
          _currentSubscription = null;
        }
        return;
      }

      // No extra timeout: rely exclusively on UCI go command to stop search

      // CRITICAL FIX: Wait for the completer to complete before returning
      // This ensures the queue processor doesn't move to the next job until this one is done
      await completer.future;
    } catch (e, st) {
      debugPrint('❌ STOCKFISH: Failed to process job for $fen: $e');
      debugPrint('$st');
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
      rethrow;
    }
  }

  List<Pv> _normalizeToWhitePerspective(List<Pv> pvs, String fen) {
    if (pvs.isEmpty) return pvs;

    final fenParts = fen.split(' ');
    final isBlackToMove = fenParts.length >= 2 && fenParts[1] == 'b';
    if (!isBlackToMove) {
      // White to move - no conversion needed
      debugPrint(
        '🔧 STOCKFISH NORMALIZE: White to move, NO conversion, cp=${pvs.first.cp}',
      );
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

    // Black to move - negate to convert to white's perspective
    debugPrint(
      '🔧 STOCKFISH NORMALIZE: Black to move, converting ${pvs.first.cp} -> ${-pvs.first.cp}',
    );
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

  Future<void> _waitUntilReady({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_engine == null) {
      throw StateError('Stockfish engine is not initialized');
    }

    if (_engine!.state.value == StockfishState.ready) {
      await _configureEngineForAnalysis();
      return;
    }

    final completer = Completer<void>();
    late VoidCallback listener;
    late final Timer timer;

    listener = () {
      if (_engine?.state.value == StockfishState.ready &&
          !completer.isCompleted) {
        completer.complete();
      }
    };

    _engine!.state.addListener(listener);

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException(
            'Stockfish did not become ready within ${timeout.inMilliseconds}ms',
          ),
        );
      }
    });

    try {
      await completer.future;
      await _configureEngineForAnalysis();
    } finally {
      timer.cancel();
      try {
        _engine!.state.removeListener(listener);
      } catch (_) {}
    }
  }

  Future<void> _ensureEngineReady() async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        if (_engine == null || _engine!.state.value == StockfishState.error) {
          try {
            _engine?.dispose();
          } catch (_) {}
          _engine = Stockfish();
        }
        await _waitUntilReady();
        return;
      } catch (e, st) {
        debugPrint(
          '⚠️ STOCKFISH INIT: Engine not ready (attempt $attempt) – $e',
        );
        debugPrint('$st');
        await _resetEngineAfterFailure();
        if (attempt >= 2) rethrow;
      }
    }
  }

  Future<void> _configureEngineForAnalysis() async {
    if (_engine == null) return;
    // CRITICAL: Configure Stockfish for analysis (not tablebase lookup)
    // Disable tablebase probing to force actual search with depth progression
    try {
      _engine!.stdin = 'setoption name SyzygyProbeLimit value 0';
      _engine!.stdin = 'setoption name UCI_AnalyseMode value true';
      debugPrint(
        '✅ Stockfish configured: Tablebases disabled for progressive search',
      );
    } catch (e) {
      debugPrint('⚠️ Could not configure Stockfish tablebases: $e');
    }
  }

  Future<void> _softResetEngine() async {
    if (_engine == null) return;
    await _currentSubscription?.cancel();
    _currentSubscription = null;
    try {
      _engine!.stdin = 'stop';
      await Future.delayed(const Duration(milliseconds: 20));
    } catch (e) {
      debugPrint('⚠️ STOCKFISH STOP FAILED: $e');
    }
    try {
      _engine!.stdin = 'ucinewgame';
    } catch (e) {
      debugPrint('⚠️ STOCKFISH ucinewgame FAILED: $e');
    }
    try {
      _engine!.stdin = 'setoption name Clear Hash';
    } catch (e) {
      debugPrint('⚠️ STOCKFISH Clear Hash FAILED: $e');
    }
    await _waitForReadyOk();
  }

  Future<void> _waitForReadyOk() async {
    if (_engine == null) return;
    final completer = Completer<void>();
    late StreamSubscription<String> sub;
    sub = _engine!.stdout.listen((line) {
      if (line.trim() == 'readyok' && !completer.isCompleted) {
        completer.complete();
      }
    });
    try {
      _engine!.stdin = 'isready';
      await completer.future.timeout(const Duration(seconds: 1));
    } catch (e) {
      debugPrint('⚠️ STOCKFISH READY WAIT FAILED: $e');
    } finally {
      await sub.cancel();
    }
  }

  void dispose() {
    _cancelCurrentEvaluation();
    _jobQueue.clear();
    _isProcessing = false;
    _engine?.dispose();
    _engine = null;
    _evaluationCache.clear();
  }

  Future<void> _resetEngineAfterFailure() async {
    try {
      await _currentSubscription?.cancel();
    } catch (_) {}
    _currentSubscription = null;
    if (_engine != null) {
      try {
        _engine!.dispose();
      } catch (_) {}
    }
    _engine = null;
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
  _EvalJob(
    this.fen,
    this.depth,
    this.key,
    this.completer, {
    this.searchDuration,
    this.maxDepth,
    this.multiPV = 3,
    this.onDepthUpdate,
    this.onPvUpdate,
    this.isCurrentPosition = false,
    this.allowCache = true,
  });

  final String fen;
  final int depth;
  final String key;
  final Completer<EnhancedCloudEval> completer;
  final Duration? searchDuration;
  final int? maxDepth;
  final int multiPV;
  final Function(int depth, int knodes)? onDepthUpdate;
  final Function(List<Pv> pvs, int depth)? onPvUpdate;
  final bool
  isCurrentPosition; // True if this is the user's currently viewed position
  final bool allowCache;
}
