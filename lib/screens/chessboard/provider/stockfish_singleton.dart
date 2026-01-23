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
  // PERF: Reduced from 60 to 18 - balance between queue responsiveness and background evals
  static const int _maxQueueSize = 18;
  static const int _maxCacheEntries = 80; // Cap cache size to avoid memory bloat

  void _touchCacheEntry(String key, EnhancedCloudEval value) {
    if (_evaluationCache.containsKey(key)) {
      _evaluationCache.remove(key);
    }
    _evaluationCache[key] = value;
    while (_evaluationCache.length > _maxCacheEntries) {
      _evaluationCache.remove(_evaluationCache.keys.first);
    }
  }

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
    String? ownerId, // Owner ID for per-provider cancellation
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

    final cached = allowCache ? _evaluationCache[cacheKey] : null;
    if (cached != null) {
      debugPrint('📦 CACHE HIT for $fen');
      _touchCacheEntry(cacheKey, cached);
      return cached;
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
      ownerId: ownerId,
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
      _touchCacheEntry(cacheKey, result);
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

      // Send stop command to engine - no delay needed as engine will stop asynchronously
      // and the next command will naturally override any pending calculation
      if (_engine != null && _engine!.state.value == StockfishState.ready) {
        try {
          _engine!.stdin = 'stop';
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
    _isSearching = false;
    _currentSubscription = null;
    try {
      _engine?.stdin = 'stop';
    } catch (_) {}
  }

  /// Cancel evaluations only for a specific owner (provider instance).
  /// This allows providers to cancel their own jobs without affecting others.
  Future<void> cancelEvaluationsForOwner(String ownerId) async {
    debugPrint('🛑 STOCKFISH: Cancelling evaluations for owner: $ownerId');

    // Cancel current job if it belongs to this owner
    if (_currentJob?.ownerId == ownerId) {
      debugPrint('🛑 STOCKFISH: Cancelling current job for owner: $ownerId');
      await _cancelCurrentEvaluation();
    }

    // Remove pending jobs for this owner
    final jobsToRemove = <_EvalJob>[];
    for (final job in _jobQueue) {
      if (job.ownerId == ownerId) {
        jobsToRemove.add(job);
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
      }
    }

    for (final job in jobsToRemove) {
      _jobQueue.remove(job);
    }

    if (jobsToRemove.isNotEmpty) {
      debugPrint(
        '🛑 STOCKFISH: Removed ${jobsToRemove.length} pending jobs for owner: $ownerId',
      );
    }
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
      DateTime? lastInfoReceived; // Track when we last received info from engine

      final isDynamicSearch = searchDuration != null;
      debugPrint(
        '🔍 STOCKFISH: Analyzing $fen ${isDynamicSearch ? "(dynamic ${searchDuration.inSeconds}s)" : "(depth $depth)"}',
      );

      _currentSubscription = _engine!.stdout.listen((line) {
        // Check if this is still the current job
        if (_currentJob != job || completer.isCompleted) return;
        line = line.trim();

        // Track that we received data from engine
        lastInfoReceived = DateTime.now();

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
          _isSearching = false; // Mark engine as no longer searching
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
            _currentSubscription?.cancel();
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
          _isSearching = true; // Mark engine as searching
          if (maxDepth != null) {
            _engine!.stdin = 'go movetime $moveTimeMs depth $maxDepth';
          } else {
            _engine!.stdin = 'go movetime $moveTimeMs';
          }
        } else {
          debugPrint('   → Sending: MultiPV $multiPV, depth $depth');
          _isSearching = true; // Mark engine as searching
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

      // Add a safety timeout to prevent indefinite hanging
      // Calculate timeout based on search parameters
      Duration safetyTimeout;
      if (isDynamicSearch) {
        // For dynamic search, add 2 seconds buffer to the search duration
        safetyTimeout = searchDuration + const Duration(seconds: 2);
      } else {
        // For fixed depth search, use a reasonable timeout based on depth
        // Deeper searches need more time, but keep it aggressive
        final timeoutSeconds = depth < 10 ? 5 : (depth < 20 ? 10 : 15);
        safetyTimeout = Duration(seconds: timeoutSeconds);
      }

      // Also add a stall detection mechanism
      Timer? stallDetector;

      // PERF: Check stall every 500ms instead of 1 second for faster detection
      stallDetector = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (lastInfoReceived != null) {
          final timeSinceLastInfo = DateTime.now().difference(lastInfoReceived!);
          // PERF: Reduced stall detection from 3 seconds to 1.5 seconds
          if (timeSinceLastInfo > const Duration(milliseconds: 1500)) {
            debugPrint('⚠️ STOCKFISH STALL DETECTED: No response for ${timeSinceLastInfo.inMilliseconds}ms');
            stallDetector?.cancel();

            // Force completion with current best results
            if (!completer.isCompleted) {
              final filteredPvs = pvs.where((pv) => pv.moves.isNotEmpty).toList(growable: false);
              final result = EnhancedCloudEval(
                fen: fen,
                knodes: knodes,
                depth: finalDepth > 0 ? finalDepth : 1,
                pvs: filteredPvs.isEmpty ? [Pv(moves: '', cp: 0)] : filteredPvs,
                isCancelled: false,
                requestedMultiPv: job.multiPV,
              );
              completer.complete(result);
              debugPrint('⚠️ STOCKFISH: Forced completion due to stall');

              // CRITICAL: Cancel subscription to prevent leak
              _currentSubscription?.cancel();
              _currentSubscription = null;

              // Try to reset the engine
              try {
                _engine?.stdin = 'stop';
              } catch (_) {}
            }
          }
        }
      });

      // Wait for the completer with timeout
      try {
        await completer.future.timeout(
          safetyTimeout,
          onTimeout: () {
            debugPrint('⚠️ STOCKFISH TIMEOUT: Evaluation took too long (${safetyTimeout.inSeconds}s)');
            stallDetector?.cancel();

            // CRITICAL: Cancel subscription to prevent leak
            _currentSubscription?.cancel();
            _currentSubscription = null;

            // Complete with whatever we have so far
            final filteredPvs = pvs.where((pv) => pv.moves.isNotEmpty).toList(growable: false);
            final result = EnhancedCloudEval(
              fen: fen,
              knodes: knodes,
              depth: finalDepth > 0 ? finalDepth : 1,
              pvs: filteredPvs.isEmpty ? [Pv(moves: '', cp: 0)] : filteredPvs,
              isCancelled: false,
              requestedMultiPv: job.multiPV,
            );

            // Try to stop the engine
            try {
              _engine?.stdin = 'stop';
            } catch (_) {}

            return result;
          },
        );
      } finally {
        stallDetector.cancel();
        // Ensure subscription is always cleaned up
        _currentSubscription?.cancel();
        _currentSubscription = null;
      }
    } catch (e, st) {
      debugPrint('❌ STOCKFISH: Failed to process job for $fen: $e');
      debugPrint('$st');
      // CRITICAL: Cancel subscription on exception to prevent leak
      _currentSubscription?.cancel();
      _currentSubscription = null;
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
    Duration timeout = const Duration(seconds: 2), // Keep it fast, fail quick if engine not responding
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
        // Force reset if engine is in error state or if we've been waiting too long
        if (_engine == null ||
            _engine!.state.value == StockfishState.error ||
            _engine!.state.value == StockfishState.disposed) {
          debugPrint('🔄 STOCKFISH: Reinitializing engine (state: ${_engine?.state.value})');
          try {
            _engine?.dispose();
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 100)); // Small delay before reinit
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
        // Allow more retries for initial load
        if (attempt >= 3) rethrow;
        await Future.delayed(Duration(milliseconds: 200 * attempt)); // Exponential backoff
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

  bool _isSearching = false; // Track if engine is currently searching

  Future<void> _softResetEngine() async {
    if (_engine == null) return;

    await _currentSubscription?.cancel();
    _currentSubscription = null;

    // UCI PROTOCOL: Must send 'stop' before new position if engine is searching
    // Otherwise behavior is undefined per UCI spec
    if (_isSearching) {
      try {
        _engine!.stdin = 'stop';
        _isSearching = false;
        // Brief yield to let stop process - no long wait needed
        await Future.delayed(const Duration(milliseconds: 10));
      } catch (e) {
        debugPrint('⚠️ STOCKFISH STOP FAILED: $e');
      }
    }
    // PERFORMANCE FIX: Removed 'ucinewgame' and 'Clear Hash' - they clear transposition
    // tables which kills performance. Stockfish handles position changes fine without
    // resetting, and preserving hash allows faster analysis of similar positions.
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
      // PERF: Reduced from 1 second to 200ms - engine should respond quickly
      await completer.future.timeout(const Duration(milliseconds: 200));
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
    _isSearching = false;
    // UCI PROTOCOL: Send 'quit' for clean shutdown before disposing
    try {
      _engine?.stdin = 'quit';
    } catch (_) {}
    _engine?.dispose();
    _engine = null;
    _evaluationCache.clear();
  }

  Future<void> _resetEngineAfterFailure() async {
    try {
      await _currentSubscription?.cancel();
    } catch (_) {}
    _currentSubscription = null;
    _isSearching = false;
    if (_engine != null) {
      try {
        _engine!.stdin = 'quit'; // UCI: clean shutdown
      } catch (_) {}
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
    this.ownerId,
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
  final String? ownerId; // Owner ID for per-provider cancellation
}
