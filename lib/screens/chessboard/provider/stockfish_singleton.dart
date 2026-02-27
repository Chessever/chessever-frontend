import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:stockfish/stockfish.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';

/// Write a UCI command directly to the native Stockfish stdin buffer via FFI,
/// bypassing the Dart [Stockfish] wrapper's state check that throws when the
/// engine isn't in [StockfishState.ready].
void _rawStockfishStdin(String command) {
  try {
    final lib = Platform.isAndroid
        ? DynamicLibrary.open('libstockfish.so')
        : DynamicLibrary.process();
    final write = lib
        .lookup<NativeFunction<IntPtr Function(Pointer<Utf8>)>>(
            'stockfish_stdin_write')
        .asFunction<int Function(Pointer<Utf8>)>();
    final ptr = '$command\n'.toNativeUtf8();
    write(ptr);
    calloc.free(ptr);
  } catch (_) {}
}

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

  /// Monotonically increasing counter used to generate unique owner IDs.
  /// Prevents race conditions when the same game is opened rapidly —
  /// each provider instance gets a distinct ownerId even for the same game.
  static int _ownerGeneration = 0;

  /// Returns a unique owner ID incorporating the game identity and a generation
  /// counter. Call once per provider creation.
  static String generateOwnerId(String gameId, int index) {
    return '${gameId}_${index}_${_ownerGeneration++}';
  }

  Stockfish? _engine;
  _EvalJob? _currentJob;
  StreamSubscription? _currentSubscription;
  final Map<String, EnhancedCloudEval> _evaluationCache = {};
  final List<_EvalJob> _jobQueue = []; // Queue for pending evaluations
  final Map<String, _EvalJob> _pendingJobs = {}; // Keyed by cacheKey
  bool _isProcessing = false; // Flag to prevent concurrent processing
  int _queueGeneration = 0; // Incremented on cancelAll to signal stale loops
  bool _isInitializing =
      false; // Lock to prevent concurrent engine initialization
  bool _previousJobCompleted =
      true; // Track if last job ended via bestmove (engine idle)
  Completer<void>? _initCompleter; // Completer for waiting on initialization
  static const int _maxQueueSize = 60; // Soft cap to avoid backlog
  static const int _maxBackgroundBacklog =
      24; // Cap low-priority backlog to protect visible-board responsiveness

  // Global instance lock to prevent "Multiple instances not supported" on Android
  // Android's native Stockfish library requires strict single-instance management
  Completer<void>? _instanceLock;
  DateTime? _lastDisposeTime; // Track when engine was last disposed
  static const Duration _androidMinDisposalWait = Duration(milliseconds: 800);
  static const Duration _iosMinDisposalWait = Duration(milliseconds: 100);

  /// Get the minimum disposal wait time based on platform
  Duration get _minDisposalWait {
    try {
      return Platform.isAndroid ? _androidMinDisposalWait : _iosMinDisposalWait;
    } catch (_) {
      // Fallback for web or test environments
      return _iosMinDisposalWait;
    }
  }

  /// Check if we're on Android (needs stricter instance management)
  bool get _isAndroid {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
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
    String? ownerId, // Owner ID for per-provider job isolation
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
    // Cache key is FEN-based only - same position = same eval regardless of requester
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length > 1 ? fenParts[1] : 'w';
    final searchMode =
        searchDuration != null
            ? 'time_${searchDuration.inMilliseconds}'
            : 'depth_$depth';
    final cacheKey = '${fen}_${searchMode}_pv${multiPV}_$sideToMove';

    // Job key includes ownerId to isolate jobs per provider
    // This prevents different providers from sharing completers (which caused wrong evals)
    final jobKey = ownerId != null ? '${cacheKey}_$ownerId' : cacheKey;

    if (allowCache && _evaluationCache.containsKey(cacheKey)) {
      debugPrint('📦 CACHE HIT for $fen');
      return _evaluationCache[cacheKey]!;
    }

    // Deduplicate: only coalesce with jobs from the SAME owner
    // Different owners get separate jobs to ensure results go to the correct provider
    if (_currentJob?.key == jobKey) {
      debugPrint(
        '📋 QUEUE: Coalesced with CURRENT job for $fen (owner: $ownerId)',
      );
      return _currentJob!.completer.future;
    }
    final pending = _pendingJobs[jobKey];
    if (pending != null) {
      debugPrint(
        '📋 QUEUE: Coalesced with PENDING job for $fen (owner: $ownerId)',
      );
      return pending.completer.future;
    }

    // If this is the active board position, cancel any in-progress job for a
    // different FEN when it is safe to preempt:
    // - always preempt low-priority jobs (isCurrentPosition == false)
    // - preempt same-owner current jobs
    // - when ownerId is known, preempt ANY current job (including cross-owner)
    //   because only one position can be "current" at a time — the user is
    //   looking at one screen, so the previous current-position job is obsolete.
    //   Cross-owner cancellation loops are prevented by the fact that cancelled
    //   providers do NOT auto-retry (explorer drops stale callbacks, chess board
    //   checks visibility before re-evaluating).
    final canPreemptCurrent =
        _currentJob != null &&
        _currentJob!.fen != fen &&
        !_currentJob!.completer.isCompleted &&
        (!_currentJob!.isCurrentPosition ||
            (ownerId == null
                ? _currentJob!.ownerId == null
                : true));
    if (isCurrentPosition && canPreemptCurrent) {
      debugPrint(
        '🛑 QUEUE: Cancelling in-flight evaluation for ${_currentJob!.fen} → new position $fen',
      );
      await _cancelCurrentEvaluation();
    }

    // When a high-priority (isCurrentPosition) job arrives, aggressively
    // clean the queue:
    // 1. Drop same-owner duplicate current-position jobs for other FENs
    // 2. Drop ALL low-priority background jobs (game cards, etc.) — the user
    //    navigated to a new screen, so stale background evals are wasted work
    //    that would delay the visible analysis by minutes.
    if (isCurrentPosition && _jobQueue.isNotEmpty) {
      int droppedCount = 0;
      _jobQueue.removeWhere((job) {
        final sameOwner =
            ownerId == null
                ? job.ownerId == null
                : (job.ownerId == ownerId || job.ownerId == null);
        final isDuplicateHighPriority =
            job.isCurrentPosition && sameOwner && job.fen != fen;
        final isLowPriority = !job.isCurrentPosition;

        if (isDuplicateHighPriority || isLowPriority) {
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
          droppedCount++;
          return true;
        }
        return false;
      });
      if (droppedCount > 0) {
        debugPrint(
          '🗑️ QUEUE: Dropped $droppedCount pending jobs (priority cleanup)',
        );
      }
    }

    // Back-pressure for low-priority workloads (game cards/background lookups).
    // Android is slower at draining native evaluations, so prevent unbounded
    // fallback requests from starving on-screen board analysis.
    final backlogSize = _jobQueue.length + (_currentJob != null ? 1 : 0);
    if (!isCurrentPosition && backlogSize >= _maxBackgroundBacklog) {
      debugPrint(
        '🛑 QUEUE: Skipping low-priority eval for $fen (backlog: $backlogSize)',
      );
      return EnhancedCloudEval(
        fen: fen,
        knodes: 0,
        depth: 0,
        pvs: [Pv(moves: '', cp: 0, mate: 0)],
        isCancelled: true,
        requestedMultiPv: multiPV,
      );
    }

    // Create job and add to queue
    final completer = Completer<EnhancedCloudEval>();
    final job = _EvalJob(
      fen,
      depth,
      jobKey,
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
    _pendingJobs[jobKey] = job;
    debugPrint(
      '📋 QUEUE: Added job for $fen (queue size: ${_jobQueue.length}, priority: ${isCurrentPosition ? "HIGH" : "low"})',
    );

    // Enforce soft cap: drop oldest overflow jobs safely
    while (_jobQueue.length > _maxQueueSize) {
      // Prefer dropping low-priority jobs first.
      // Front of queue contains highest-priority/current-position jobs.
      final int lowPriorityIndex = _jobQueue.lastIndexWhere(
        (job) => !job.isCurrentPosition,
      );
      final dropped =
          lowPriorityIndex >= 0
              ? _jobQueue.removeAt(lowPriorityIndex)
              : _jobQueue.removeLast();
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
      debugPrint(
        '🗑️ QUEUE: Dropped overflow job for ${dropped.fen} (priority: ${dropped.isCurrentPosition ? "HIGH" : "low"})',
      );
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

      // Fire-and-forget stop — don't block waiting for readyok.
      // The next job's _softResetEngine() will synchronize via isready/readyok
      // before sending the next 'go' command.
      if (_engine != null && _engine!.state.value == StockfishState.ready) {
        try {
          _engine!.stdin = 'stop';
        } catch (e) {
          debugPrint('Error sending stop command to Stockfish: $e');
        }
      }

      // Mark engine as not yet confirmed idle — _softResetEngine handles sync.
      _previousJobCompleted = false;
      _currentJob = null;
    }
  }

  Future<void> cancelAllEvaluations() async {
    debugPrint('🛑 STOCKFISH: Cancelling all evaluations...');
    await _cancelCurrentEvaluation();
    if (_jobQueue.isNotEmpty) {
      final jobCount = _jobQueue.length;
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
      debugPrint('🛑 STOCKFISH: Cancelled $jobCount queued jobs');
    }
    // Bump generation so any running _processQueue loop will exit after its
    // current await point, preventing concurrent queue processors.
    _queueGeneration++;
    _isProcessing = false;
    _currentSubscription = null;
    try {
      if (_engine != null && _engine!.state.value == StockfishState.ready) {
        _engine!.stdin = 'stop';
      }
    } catch (_) {}
    debugPrint('✅ STOCKFISH: All evaluations cancelled');
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
    final myGeneration = _queueGeneration;
    debugPrint(
      '🏭 QUEUE PROCESSOR: Starting, ${_jobQueue.length} jobs in queue',
    );

    try {
      while (_jobQueue.isNotEmpty) {
        // If cancelAllEvaluations was called, this generation is stale — exit.
        if (_queueGeneration != myGeneration) {
          debugPrint(
            '🛑 QUEUE PROCESSOR: Generation changed, exiting stale loop',
          );
          return;
        }
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

      // Guard: engine must be non-null and ready after initialization.
      // After forceRecovery the engine may still be null if init timed out.
      if (_engine == null) {
        throw StateError(
          'Engine is null after _ensureEngineReady — init likely timed out',
        );
      }

      final List<Pv> pvs = [];
      int knodes = 0;
      int finalDepth = 0;
      bool evaluationComplete = false;
      int lastPvUpdateDepthReported = 0;
      String lastPvSnapshotSignature = '';
      DateTime?
      lastInfoReceived; // Track when we last received info from engine

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
              // Raw Stockfish info lines are from side-to-move perspective.
              final pv = Pv(
                moves: moves,
                cp: cp,
                isMate: false,
                whitePerspective: false,
              );
              pvs[multipvIndex - 1] = pv;
            } else if (mateMatch != null) {
              final mate = int.parse(mateMatch.group(1)!);
              final cp = mate.sign * 100000; // Convert mate to large cp value
              // Raw Stockfish info lines are from side-to-move perspective.
              final pv = Pv(
                moves: moves,
                cp: cp,
                isMate: true,
                mate: mate,
                whitePerspective: false,
              );
              pvs[multipvIndex - 1] = pv;
            }

            // Emit PV snapshot after parsing actual PV data.
            // CRITICAL: This must be inside the pvMatch block so that
            // non-PV info lines (currmove, stats) don't consume
            // lastPvUpdateDepthReported — which would prevent the real
            // PV lines at the same depth from being emitted.
            if (job.onPvUpdate != null) {
              final snapshot = pvs
                  .where((pv) => pv.moves.isNotEmpty)
                  .toList(growable: false);
              if (snapshot.isNotEmpty) {
                final snapshotSignature = snapshot
                    .map((pv) => '${pv.cp}|${pv.mate}|${pv.moves}')
                    .join('||');
                final depthAdvanced = finalDepth > lastPvUpdateDepthReported;
                final changedAtSameDepth =
                    finalDepth == lastPvUpdateDepthReported &&
                    snapshotSignature != lastPvSnapshotSignature;
                if (!depthAdvanced && !changedAtSameDepth) {
                  return;
                }
                try {
                  job.onPvUpdate!(snapshot, finalDepth);
                  lastPvUpdateDepthReported = finalDepth;
                  lastPvSnapshotSignature = snapshotSignature;
                } catch (_) {
                  // Ignore callback errors
                }
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
            _previousJobCompleted = true;
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

        // Initialize stall detection baseline BEFORE sending go command.
        // Without this, if the engine produces zero output (common on Android
        // after rapid cancel/restart), lastInfoReceived stays null and the
        // stall detector never fires — leaving the UI stuck.
        lastInfoReceived = DateTime.now();

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

      // Add a safety timeout to prevent indefinite hanging
      // Calculate timeout based on search parameters
      Duration safetyTimeout;
      if (isDynamicSearch) {
        // For dynamic search, add 1 second buffer to the search duration
        safetyTimeout = searchDuration + const Duration(seconds: 1);
      } else {
        // Deep searches with multiPV take exponentially longer per depth level.
        // depth 15: ~10s, depth 25: ~60s, depth 40: ~300s, depth 50+: ~600s
        final timeoutSeconds =
            depth <= 15 ? 15 : (depth <= 25 ? 60 : (depth <= 40 ? 300 : 600));
        safetyTimeout = Duration(seconds: timeoutSeconds);
      }

      // Also add a stall detection mechanism
      Timer? stallDetector;

      // At high depths with multiPV, a single depth level can take 5-10+ seconds
      // with no intermediate output. Scale the stall threshold accordingly.
      final stallThreshold = Duration(
        milliseconds: depth <= 20 ? 1200 : (depth <= 40 ? 3500 : 8000),
      );

      stallDetector = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (lastInfoReceived != null) {
          final timeSinceLastInfo = DateTime.now().difference(
            lastInfoReceived!,
          );
          if (timeSinceLastInfo > stallThreshold) {
            debugPrint(
              '⚠️ STOCKFISH STALL DETECTED: No response for ${timeSinceLastInfo.inSeconds}s',
            );
            stallDetector?.cancel();

            // Force completion with current best results
            if (!completer.isCompleted) {
              final filteredPvs = pvs
                  .where((pv) => pv.moves.isNotEmpty)
                  .toList(growable: false);
              final normalizedPvs = _normalizeToWhitePerspective(
                filteredPvs,
                fen,
              );
              final result = EnhancedCloudEval(
                fen: fen,
                knodes: knodes,
                depth: finalDepth > 0 ? finalDepth : 1,
                pvs:
                    normalizedPvs.isEmpty
                        ? [Pv(moves: '', cp: 0)]
                        : normalizedPvs,
                isCancelled: false,
                requestedMultiPv: job.multiPV,
              );
              completer.complete(result);
              debugPrint('⚠️ STOCKFISH: Forced completion due to stall');

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
            debugPrint(
              '⚠️ STOCKFISH TIMEOUT: Evaluation took too long (${safetyTimeout.inSeconds}s)',
            );
            stallDetector?.cancel();

            // Complete with whatever we have so far
            final filteredPvs = pvs
                .where((pv) => pv.moves.isNotEmpty)
                .toList(growable: false);
            final normalizedPvs = _normalizeToWhitePerspective(
              filteredPvs,
              fen,
            );
            final result = EnhancedCloudEval(
              fen: fen,
              knodes: knodes,
              depth: finalDepth > 0 ? finalDepth : 1,
              pvs:
                  normalizedPvs.isEmpty
                      ? [Pv(moves: '', cp: 0)]
                      : normalizedPvs,
              isCancelled: false,
              requestedMultiPv: job.multiPV,
            );

            // Try to stop the engine
            try {
              _engine?.stdin = 'stop';
            } catch (_) {}

            if (!completer.isCompleted) {
              completer.complete(result);
              final sub = _currentSubscription;
              _currentSubscription = null;
              if (sub != null) {
                unawaited(sub.cancel());
              }
            }
            return result;
          },
        );
      } finally {
        stallDetector.cancel();
      }
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
    Duration timeout = const Duration(
      seconds: 3,
    ), // Slightly longer timeout for Android
  }) async {
    if (_engine == null) {
      throw StateError('Stockfish engine is not initialized');
    }

    // Check for error or disposed state immediately
    final currentState = _engine!.state.value;
    if (currentState == StockfishState.error) {
      throw StateError('Stockfish engine is in error state');
    }
    if (currentState == StockfishState.disposed) {
      throw StateError('Stockfish engine was disposed');
    }

    if (currentState == StockfishState.ready) {
      await _configureEngineForAnalysis();
      return;
    }

    final completer = Completer<void>();
    late VoidCallback listener;
    late final Timer timer;

    listener = () {
      final state = _engine?.state.value;
      if (completer.isCompleted) return;

      if (state == StockfishState.ready) {
        completer.complete();
      } else if (state == StockfishState.error) {
        completer.completeError(StateError('Stockfish entered error state'));
      } else if (state == StockfishState.disposed) {
        completer.completeError(StateError('Stockfish was disposed'));
      }
    };

    _engine!.state.addListener(listener);

    // Use longer timeout on Android
    final effectiveTimeout =
        _isAndroid
            ? Duration(milliseconds: timeout.inMilliseconds + 1000)
            : timeout;

    timer = Timer(effectiveTimeout, () {
      if (!completer.isCompleted) {
        final state = _engine?.state.value;
        completer.completeError(
          TimeoutException(
            'Stockfish did not become ready within ${effectiveTimeout.inMilliseconds}ms (current state: $state)',
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
        _engine?.state.removeListener(listener);
      } catch (_) {}
    }
  }

  /// Acquires the instance lock, ensuring only one operation can create/dispose engine at a time.
  /// Returns a function to release the lock when done.
  Future<void Function()> _acquireInstanceLock() async {
    // Wait for any existing lock to be released
    while (_instanceLock != null && !_instanceLock!.isCompleted) {
      debugPrint('🔒 STOCKFISH: Waiting for instance lock...');
      try {
        await _instanceLock!.future.timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('⚠️ STOCKFISH: Instance lock wait timeout: $e');
        // Force release stale lock
        _instanceLock = null;
      }
    }

    // Acquire the lock
    _instanceLock = Completer<void>();
    debugPrint('🔒 STOCKFISH: Instance lock acquired');

    return () {
      if (_instanceLock != null && !_instanceLock!.isCompleted) {
        _instanceLock!.complete();
        debugPrint('🔓 STOCKFISH: Instance lock released');
      }
      _instanceLock = null;
    };
  }

  /// Safely disposes the current engine with proper cleanup timing.
  Future<void> _safeDisposeEngine() async {
    if (_engine == null) return;

    debugPrint(
      '🧹 STOCKFISH: Disposing engine (state: ${_engine!.state.value})',
    );

    // Cancel any active subscription first
    try {
      await _currentSubscription?.cancel();
    } catch (_) {}
    _currentSubscription = null;

    // Send stop command if engine is responsive
    if (_engine!.state.value == StockfishState.ready) {
      try {
        _engine!.stdin = 'stop';
        _engine!.stdin = 'quit';
        // Give engine time to process quit command
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        debugPrint('⚠️ STOCKFISH: Could not send quit: $e');
      }
    }

    // Dispose the engine
    try {
      _engine!.dispose();
    } catch (e) {
      debugPrint(
        '⚠️ STOCKFISH: Dispose error (expected on some platforms): $e',
      );
    }
    _engine = null;
    _lastDisposeTime = DateTime.now();

    // CRITICAL: Wait for native cleanup based on platform
    // Android's native Stockfish library is very strict about single instances
    final waitTime = _minDisposalWait;
    debugPrint(
      '⏳ STOCKFISH: Waiting ${waitTime.inMilliseconds}ms for native cleanup...',
    );
    await Future.delayed(waitTime);

    debugPrint('✅ STOCKFISH: Engine disposed and cleanup complete');
  }

  /// Creates a new engine instance with proper timing.
  Future<Stockfish> _createEngineInstance() async {
    // Ensure minimum time has passed since last disposal
    if (_lastDisposeTime != null) {
      final timeSinceDispose = DateTime.now().difference(_lastDisposeTime!);
      final minWait = _minDisposalWait;
      if (timeSinceDispose < minWait) {
        final remainingWait = minWait - timeSinceDispose;
        debugPrint(
          '⏳ STOCKFISH: Waiting ${remainingWait.inMilliseconds}ms before creating new instance...',
        );
        await Future.delayed(remainingWait);
      }
    }

    debugPrint('🆕 STOCKFISH: Creating new engine instance...');
    final engine = Stockfish();
    debugPrint('✅ STOCKFISH: New engine instance created');
    return engine;
  }

  Future<void> _ensureEngineReady() async {
    // If another call is already initializing, wait for it
    if (_isInitializing && _initCompleter != null) {
      debugPrint('🔒 STOCKFISH: Waiting for ongoing initialization...');
      try {
        await _initCompleter!.future.timeout(const Duration(seconds: 10));
        if (_engine != null && _engine!.state.value == StockfishState.ready) {
          return;
        }
      } catch (e) {
        debugPrint('⚠️ STOCKFISH: Init wait failed: $e');
      }
    }

    // Check if engine is already ready
    if (_engine != null && _engine!.state.value == StockfishState.ready) {
      await _configureEngineForAnalysis();
      return;
    }

    // Acquire initialization lock
    _isInitializing = true;
    _initCompleter = Completer<void>();

    // Acquire global instance lock for thread-safety
    final releaseLock = await _acquireInstanceLock();

    int attempt = 0;
    final maxAttempts = _isAndroid ? 5 : 3; // More retries on Android

    try {
      while (true) {
        attempt++;
        try {
          // Force reset if engine is in error state or disposed
          if (_engine == null ||
              _engine!.state.value == StockfishState.error ||
              _engine!.state.value == StockfishState.disposed) {
            debugPrint(
              '🔄 STOCKFISH: Reinitializing engine (state: ${_engine?.state.value}, attempt: $attempt/$maxAttempts)',
            );

            // Properly dispose old engine first with platform-specific timing
            if (_engine != null) {
              await _safeDisposeEngine();
            }

            // Create new engine instance with proper timing
            _engine = await _createEngineInstance();
          }

          await _waitUntilReady();
          _initCompleter?.complete();
          return;
        } catch (e, st) {
          debugPrint(
            '⚠️ STOCKFISH INIT: Engine not ready (attempt $attempt/$maxAttempts) – $e',
          );
          debugPrint('$st');

          final isMultipleInstanceError = e.toString().contains(
            'Multiple instances',
          );

          if (isMultipleInstanceError) {
            debugPrint(
              '🔄 STOCKFISH: Multiple instance error detected on Android',
            );
            // Force null without calling dispose (it's already in bad state)
            _engine = null;
            _lastDisposeTime = DateTime.now();

            // Aggressive backoff for Android multiple instance errors
            // Each retry waits longer: 800ms, 1200ms, 1600ms, 2000ms, 2400ms
            final waitMs =
                _isAndroid ? 800 + (attempt * 400) : 300 + (attempt * 200);
            debugPrint('⏳ STOCKFISH: Waiting ${waitMs}ms before retry...');
            await Future.delayed(Duration(milliseconds: waitMs));
          } else {
            // Other errors - use standard reset
            await _resetEngineAfterFailure();
            await Future.delayed(Duration(milliseconds: 200 * attempt));
          }

          // Give up after max attempts
          if (attempt >= maxAttempts) {
            debugPrint(
              '❌ STOCKFISH: Max attempts ($maxAttempts) reached, giving up',
            );
            _initCompleter?.completeError(e, st);
            rethrow;
          }
        }
      }
    } finally {
      _isInitializing = false;
      releaseLock();
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

    // Only proceed if engine is in a valid state
    final state = _engine!.state.value;
    if (state != StockfishState.ready && state != StockfishState.starting) {
      debugPrint('⚠️ STOCKFISH: Soft reset skipped, engine state: $state');
      return;
    }

    await _currentSubscription?.cancel();
    _currentSubscription = null;

    // If the previous job completed normally (bestmove received), engine is
    // already idle — no need to send stop. This avoids unnecessary overhead.
    if (!_previousJobCompleted) {
      try {
        _engine!.stdin = 'stop';
        // Use the UCI isready/readyok handshake on ALL platforms to guarantee
        // the engine is truly idle before the next 'go' command. A fixed delay
        // is unreliable during rapid navigation (stop/go/stop/go).
        await _waitForReadyOk();
      } catch (e) {
        debugPrint('⚠️ STOCKFISH STOP FAILED: $e');
        return;
      }
    }

    // Mark that a new job is starting (not yet completed)
    _previousJobCompleted = false;

    // NOTE: We intentionally do NOT send 'ucinewgame', 'Clear Hash', or
    // 'isready' here. Per UCI protocol, ucinewgame is only needed between
    // different games — not between positions in the same analysis session.
    // Keeping the hash table intact lets Stockfish reuse transposition data
    // from prior searches, which significantly speeds up deepening.
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
      final timeout =
          _isAndroid
              ? const Duration(milliseconds: 800)
              : const Duration(milliseconds: 500);
      await completer.future.timeout(timeout);
    } catch (e) {
      debugPrint('⚠️ STOCKFISH READY WAIT FAILED: $e');
    } finally {
      await sub.cancel();
    }
  }

  /// Cleanup for hot restart. Sends `stop` + `quit` directly via FFI
  /// (bypasses the Dart wrapper's state check) so the native engine exits
  /// and its isolate can be killed by the hot restart mechanism.
  void prepareForHotRestart() {
    _queueGeneration++;

    // Write directly to native stdin — works even if Dart-side engine state
    // is not `ready` (e.g. still starting, or already errored).
    _rawStockfishStdin('stop');
    _rawStockfishStdin('quit');

    if (_currentJob != null && !_currentJob!.completer.isCompleted) {
      _currentJob!.completer.complete(
        EnhancedCloudEval(
          fen: _currentJob!.fen,
          knodes: 0,
          depth: 0,
          pvs: [Pv(moves: '', cp: 0, mate: 0)],
          isCancelled: true,
          requestedMultiPv: _currentJob!.multiPV,
        ),
      );
    }
    _currentJob = null;
    _currentSubscription?.cancel();
    _currentSubscription = null;

    for (final job in _jobQueue) {
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
    _jobQueue.clear();
    _pendingJobs.clear();
    _isProcessing = false;
    _isInitializing = false;
    _initCompleter = null;
    _previousJobCompleted = true;

    if (_instanceLock != null && !_instanceLock!.isCompleted) {
      _instanceLock!.complete();
    }
    _instanceLock = null;

    // Don't call _engine!.dispose() (which also sends quit via the Dart
    // wrapper and can throw). The FFI quit above is sufficient.
    _engine = null;
    _lastDisposeTime = DateTime.now();
    _evaluationCache.clear();
    debugPrint('🧹 STOCKFISH: Hot restart cleanup done (FFI quit sent)');
  }

  void dispose() {
    // Complete current job synchronously — don't call async
    // _cancelCurrentEvaluation() since we're about to destroy the engine.
    if (_currentJob != null && !_currentJob!.completer.isCompleted) {
      _currentJob!.completer.complete(
        EnhancedCloudEval(
          fen: _currentJob!.fen,
          knodes: 0,
          depth: 0,
          pvs: [Pv(moves: '', cp: 0, mate: 0)],
          isCancelled: true,
          requestedMultiPv: _currentJob!.multiPV,
        ),
      );
    }
    _currentJob = null;
    // Don't await — engine is being destroyed, subscription will die with it.
    _currentSubscription?.cancel();
    _currentSubscription = null;

    // Complete all queued jobs as cancelled
    for (final job in _jobQueue) {
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
    _jobQueue.clear();
    _pendingJobs.clear();
    _isProcessing = false;
    _queueGeneration++;
    _isInitializing = false;
    _initCompleter = null;
    _previousJobCompleted = true;

    // Release any pending instance lock
    if (_instanceLock != null && !_instanceLock!.isCompleted) {
      _instanceLock!.complete();
    }
    _instanceLock = null;

    // Dispose engine synchronously for dispose() call
    if (_engine != null) {
      try {
        _engine!.stdin = 'quit';
      } catch (_) {}
      try {
        _engine!.dispose();
      } catch (_) {}
      _engine = null;
      _lastDisposeTime = DateTime.now();
    }
    _evaluationCache.clear();
    debugPrint('🧹 STOCKFISH: Singleton disposed');
  }

  /// Async dispose with proper cleanup timing - use when you need to reinitialize afterwards.
  Future<void> disposeAsync() async {
    await _cancelCurrentEvaluation();
    _jobQueue.clear();
    _pendingJobs.clear();
    _isProcessing = false;
    _isInitializing = false;
    _initCompleter = null;

    // Release any pending instance lock
    if (_instanceLock != null && !_instanceLock!.isCompleted) {
      _instanceLock!.complete();
    }
    _instanceLock = null;

    // Use safe disposal with proper timing
    if (_engine != null) {
      await _safeDisposeEngine();
    }

    _evaluationCache.clear();
    debugPrint('🧹 STOCKFISH: Singleton disposed async');
  }

  Future<void> _resetEngineAfterFailure() async {
    debugPrint('🔄 STOCKFISH: Resetting engine after failure...');

    // Cancel subscription first
    try {
      await _currentSubscription?.cancel();
    } catch (_) {}
    _currentSubscription = null;

    // Use safe disposal with platform-specific timing
    if (_engine != null) {
      await _safeDisposeEngine();
    } else {
      // Even if engine is null, record disposal time for proper timing
      _lastDisposeTime = DateTime.now();
    }

    debugPrint('✅ STOCKFISH: Engine reset complete');
  }

  /// Force recovery of the Stockfish engine when it's stuck or unresponsive.
  /// This will cancel all evaluations, dispose the current engine, and reinitialize.
  /// Use this when the engine is not responding and needs a hard reset.
  Future<void> forceRecovery() async {
    debugPrint('🔧 STOCKFISH: Force recovery initiated...');

    // Cancel everything first
    await cancelAllEvaluations();

    // Force dispose with proper timing
    if (_engine != null) {
      await _safeDisposeEngine();
    }

    // Clear initialization state
    _isInitializing = false;
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      _initCompleter!.completeError(StateError('Force recovery'));
    }
    _initCompleter = null;

    // Release instance lock if held
    if (_instanceLock != null && !_instanceLock!.isCompleted) {
      _instanceLock!.complete();
    }
    _instanceLock = null;

    // Extra wait time on Android to ensure native cleanup
    if (_isAndroid) {
      debugPrint('⏳ STOCKFISH: Extra recovery wait for Android...');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    debugPrint(
      '✅ STOCKFISH: Force recovery complete, engine will reinitialize on next request',
    );
  }

  /// Check if the engine is currently in a healthy state
  bool get isEngineHealthy {
    return _engine != null && _engine!.state.value == StockfishState.ready;
  }

  /// True when engine exists but is in a terminal/broken state.
  bool get requiresRecovery {
    final state = _engine?.state.value;
    return state == StockfishState.error || state == StockfishState.disposed;
  }

  /// Get the current engine state for debugging
  String get engineStateDebug {
    if (_engine == null) return 'null';
    return _engine!.state.value.toString();
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
    this.cacheKey,
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
  final String key; // Job key (includes ownerId) - for deduplication per owner
  final String cacheKey; // Cache key (FEN-based only) - for shared cache lookup
  final Completer<EnhancedCloudEval> completer;
  final Duration? searchDuration;
  final int? maxDepth;
  final int multiPV;
  final Function(int depth, int knodes)? onDepthUpdate;
  final Function(List<Pv> pvs, int depth)? onPvUpdate;
  final bool
  isCurrentPosition; // True if this is the user's currently viewed position
  final bool allowCache;
  final String? ownerId; // Owner ID for per-provider job isolation
}
