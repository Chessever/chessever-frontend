import 'dart:async';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'gif_export_worker.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:country_flags/country_flags.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:motor/motor.dart';

/// Raw frame data for GIF encoding (avoids PNG encoding/decoding issues on iOS P3 displays)
class _RawFrame {
  final Uint8List rgba;
  final int width;
  final int height;
  _RawFrame(this.rgba, this.width, this.height);
}

class ShareGameCardOverlay extends StatefulWidget {
  final ChessboardSettings boardSettings;
  final String positionFen;
  final Move? lastMove;
  final String pgn;
  final List<String> moveSans; // The actual move list from analysis state
  final List<String> moveTimes; // Clock times for each move (for GIF animation)
  final String whitePlayerName;
  final String blackPlayerName;
  final String? whitePlayerCountry;
  final String? blackPlayerCountry;
  final String? whitePlayerElo;
  final String? blackPlayerElo;
  final String? whitePlayerTitle;
  final String? blackPlayerTitle;
  final String? whitePlayerClock;
  final String? blackPlayerClock;
  final String? tournamentName;
  final String? roundInfo;
  final int currentMoveIndex;
  final double? evaluation;
  final int mate;
  final bool isFlipped;
  final GameStatus gameStatus;
  final bool
  isAtGameEnd; // Whether viewing the actual final position of the game
  final VoidCallback onClose;
  final String? shareUrl;
  final String gameId; // CRITICAL: Include game ID for correct eval caching
  final String? startingFen; // null = standard initial position

  const ShareGameCardOverlay({
    super.key,
    required this.boardSettings,
    required this.positionFen,
    required this.lastMove,
    required this.pgn,
    required this.moveSans,
    this.moveTimes = const [], // Default to empty for backwards compatibility
    required this.whitePlayerName,
    required this.blackPlayerName,
    this.whitePlayerCountry,
    this.blackPlayerCountry,
    this.whitePlayerElo,
    this.blackPlayerElo,
    this.whitePlayerTitle,
    this.blackPlayerTitle,
    this.whitePlayerClock,
    this.blackPlayerClock,
    this.tournamentName,
    this.roundInfo,
    required this.currentMoveIndex,
    required this.evaluation,
    required this.mate,
    required this.isFlipped,
    required this.gameStatus,
    this.isAtGameEnd = false,
    required this.onClose,
    this.shareUrl,
    required this.gameId, // REQUIRED for correct eval caching
    this.startingFen, // null = standard initial position
  });

  @override
  State<ShareGameCardOverlay> createState() => _ShareGameCardOverlayState();
}

class _ShareGameCardOverlayState extends State<ShareGameCardOverlay> {
  static const double _maxGifRasterWidth = 720.0;

  final ScreenshotController _fullScreenshotController = ScreenshotController();
  final GlobalKey _gifFrameKey = GlobalKey(); // For raw pixel capture
  bool _isGenerating = false;
  bool _isGeneratingGif = false;
  double _gifProgress = 0.0;
  bool _showEvalBar = true;
  double _rotationX = 0.0;
  double _rotationY = 0.0;

  // GIF frame state
  String? _gifFrameFen;
  NormalMove? _gifFrameLastMove;
  String? _gifFrameWhiteClock;
  String? _gifFrameBlackClock;
  bool _gifFrameIsFinal = false; // Only show game ending effects on final frame
  bool _cancelled = false; // Set on dispose to abort in-flight GIF generation

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _captureShareMessage(
    String message, {
    required String stage,
    Map<String, dynamic>? extras,
  }) async {
    try {
      const shareUrlKey = 'shareUrl';
      final resolvedShareUrl =
          (extras?[shareUrlKey] as String?) ?? _effectiveShareUrl;
      await Sentry.captureMessage(
        message,
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('area', 'share_game');
          scope.setTag('stage', stage);
          scope.setContexts(
            'share_game',
            {
              'gameId': widget.gameId,
              'shareUrl': resolvedShareUrl,
              'hasShareUrl': resolvedShareUrl?.isNotEmpty == true,
              ...?extras,
            }.map((key, value) => MapEntry(key, value?.toString())),
          );
        },
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _captureShareException(
    Object error,
    StackTrace stackTrace, {
    required String stage,
    Map<String, dynamic>? extras,
  }) async {
    try {
      const shareUrlKey = 'shareUrl';
      final resolvedShareUrl =
          (extras?[shareUrlKey] as String?) ?? _effectiveShareUrl;
      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) {
          scope.setTag('area', 'share_game');
          scope.setTag('stage', stage);
          scope.setContexts(
            'share_game',
            {
              'gameId': widget.gameId,
              'shareUrl': resolvedShareUrl,
              'hasShareUrl': resolvedShareUrl?.isNotEmpty == true,
              ...?extras,
            }.map((key, value) => MapEntry(key, value?.toString())),
          );
        },
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  // Board settings with animations disabled for instant frame capture
  ChessboardSettings get _gifBoardSettings => ChessboardSettings(
    enableCoordinates: widget.boardSettings.enableCoordinates,
    colorScheme: widget.boardSettings.colorScheme,
    pieceAssets: widget.boardSettings.pieceAssets,
    borderRadius: widget.boardSettings.borderRadius,
    boxShadow: widget.boardSettings.boxShadow,
    // CRITICAL: Disable animations for instant static frame capture
    animationDuration: Duration.zero,
  );

  /// Calculate clock times at a given move index
  /// Returns (whiteClock, blackClock) tuple
  (String?, String?) _getClocksAtMoveIndex(int moveIndex) {
    if (widget.moveTimes.isEmpty) {
      return (null, null);
    }

    String? whiteClock;
    String? blackClock;

    // Find white's most recent clock (white moves are at even indices: 0, 2, 4...)
    for (int i = moveIndex; i >= 0; i--) {
      if (i % 2 == 0 && i < widget.moveTimes.length) {
        whiteClock = widget.moveTimes[i];
        break;
      }
    }

    // Find black's most recent clock (black moves are at odd indices: 1, 3, 5...)
    for (int i = moveIndex; i >= 0; i--) {
      if (i % 2 == 1 && i < widget.moveTimes.length) {
        blackClock = widget.moveTimes[i];
        break;
      }
    }

    return (whiteClock, blackClock);
  }

  /// Capture raw RGBA pixel data from the RepaintBoundary.
  /// Disposes the ui.Image immediately after extracting bytes.
  Future<_RawFrame?> _captureRawFrame(double pixelRatio) async {
    try {
      final boundary =
          _gifFrameKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('GIF: RepaintBoundary not found');
        return null;
      }

      final logicalWidth = boundary.size.width;
      final effectivePixelRatio =
          logicalWidth > 0
              ? math.max(
                0.1,
                math.min(pixelRatio, _maxGifRasterWidth / logicalWidth),
              )
              : pixelRatio;

      final image = await boundary.toImage(pixelRatio: effectivePixelRatio);
      try {
        final byteData = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (byteData == null) {
          debugPrint('GIF: toByteData returned null');
          return null;
        }

        return _RawFrame(
          byteData.buffer.asUint8List(),
          image.width,
          image.height,
        );
      } finally {
        image.dispose();
      }
    } catch (e) {
      debugPrint('GIF: Raw capture error: $e');
      return null;
    }
  }

  Future<Uint8List?> _captureCard() async {
    try {
      setState(() => _isGenerating = true);

      // Wait for the widget tree to stabilize and complete painting
      // This ensures the offscreen widget is fully rendered before capture
      await Future.delayed(const Duration(milliseconds: 100));

      // Wait for the current frame to finish
      await WidgetsBinding.instance.endOfFrame;

      // Wait one more frame to be absolutely sure painting is complete
      await Future.delayed(const Duration(milliseconds: 50));

      // Capture the full card (offscreen) with all moves
      final image = await _fullScreenshotController.capture(pixelRatio: 3.0);
      return image;
    } catch (e) {
      debugPrint('Error capturing screenshot: $e');
      return null;
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  String? get _effectiveShareUrl {
    final explicit = widget.shareUrl?.trim();
    if (explicit == null || explicit.isEmpty) return null;
    return explicit;
  }

  String get _shareSubject {
    final tournamentName = widget.tournamentName?.trim();
    final roundInfo = widget.roundInfo?.trim();

    if (tournamentName != null && tournamentName.isNotEmpty) {
      if (roundInfo != null && roundInfo.isNotEmpty) {
        return '$tournamentName • $roundInfo';
      }
      return tournamentName;
    }

    return 'Chessever Game';
  }

  Future<void> _shareFiles(List<XFile> files) {
    unawaited(
      _captureShareMessage(
        'share game files invoked',
        stage: 'share_files',
        extras: {
          'fileCount': files.length,
          'subject': _shareSubject,
          'shareUrl': _effectiveShareUrl,
        },
      ),
    );
    return Share.shareXFiles(
      files,
      subject: _shareSubject,
      text: _effectiveShareUrl,
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
    );
  }

  Future<void> _shareImage() async {
    unawaited(
      _captureShareMessage('share image started', stage: 'share_image_started'),
    );
    final imageBytes = await _captureCard();
    if (imageBytes == null) {
      _showMessage('Failed to generate image', isError: true);
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = io.File('${tempDir.path}/chessever_share.png');
      await file.writeAsBytes(imageBytes);

      await _shareFiles([XFile(file.path)]);
      unawaited(
        _captureShareMessage(
          'share image completed',
          stage: 'share_image_completed',
          extras: {
            'imageSize': imageBytes.length,
            'shareUrl': _effectiveShareUrl,
          },
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Error sharing: $e');
      unawaited(
        _captureShareException(
          e,
          stackTrace,
          stage: 'share_image',
          extras: {'imageSize': imageBytes.length},
        ),
      );
      _showMessage('Failed to share image', isError: true);
    }
  }

  Future<void> _shareGeneratedGif(Uint8List gifBytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = io.File('${tempDir.path}/chessever_game.gif');
    await file.writeAsBytes(gifBytes);

    await _shareFiles([XFile(file.path)]);
  }

  void _updateGifProgress(int captured, int accepted, int total) {
    final progress = (captured / total * 0.6 + accepted / total * 0.4).clamp(
      0.0,
      0.95,
    );
    // Only rebuild if progress moved by ≥2% to avoid rebuild storms
    if (mounted && (progress - _gifProgress).abs() >= 0.02) {
      setState(() => _gifProgress = progress);
    }
  }

  /// Computes the export window for GIF generation.
  ///
  /// Share GIF always uses the full game, independent of the currently selected
  /// board move. Returns `null` if no moves are available to animate.
  GifExportWindow? _computeExportWindow() {
    return computeGifExportWindow(
      moveSans: widget.moveSans,
      currentMoveIndex: widget.currentMoveIndex,
      startingFen: widget.startingFen,
    );
  }

  Future<void> _shareGif() async {
    if (_isGeneratingGif) return;
    _cancelled = false;

    final exportWindow = _computeExportWindow();
    if (exportWindow == null) {
      // No moves to animate — fall back to static image export
      await _shareImage();
      return;
    }

    final movesToAnimate = exportWindow.movesToAnimate;
    final globalMoveOffset = exportWindow.globalMoveOffset;
    final captureStartFen = exportWindow.captureStartFen;

    setState(() {
      _isGeneratingGif = true;
      _gifProgress = 0.0;
    });

    try {
      // Plan export profile using the full prefix up to the selected end move.
      final profile = planGifExport(
        moveCount: movesToAnimate.length,
        currentMoveIndex: movesToAnimate.length - 1,
      );
      final totalOutputFrames = 1 + profile.frameIndices.length;

      // Try to start a worker isolate for pipelined encoding
      Isolate? workerIsolate;
      SendPort? workerSendPort;
      ReceivePort? mainPort;
      bool useIsolate = true;

      Stream<dynamic>? mainStream;
      try {
        mainPort = ReceivePort();
        // Convert to broadcast stream so both the handshake and the pipeline
        // can listen sequentially. ReceivePort is single-subscription — a
        // second .listen() after cancel throws "Stream has already been
        // listened to".
        mainStream = mainPort.asBroadcastStream();
        workerIsolate = await Isolate.spawn(
          gifEncoderWorker,
          mainPort.sendPort,
        );

        // Wait for GifWorkerReady (single handshake with SendPort)
        final readyCompleter = Completer<SendPort>();
        final readySub = mainStream.listen((message) {
          if (message is GifWorkerReady && !readyCompleter.isCompleted) {
            readyCompleter.complete(message.workerSendPort);
          }
        });

        workerSendPort = await readyCompleter.future.timeout(
          const Duration(seconds: 5),
        );
        await readySub.cancel();
      } catch (e) {
        debugPrint('GIF: Isolate startup failed: $e, using fallback');
        useIsolate = false;
        mainPort?.close();
        workerIsolate?.kill();
        mainPort = null;
        workerIsolate = null;
        mainStream = null;
      }

      if (useIsolate) {
        await _shareGifPipelined(
          movesToAnimate: movesToAnimate,
          profile: profile,
          totalOutputFrames: totalOutputFrames,
          workerSendPort: workerSendPort!,
          mainStream: mainStream!,
          mainPort: mainPort!,
          workerIsolate: workerIsolate!,
          captureStartFen: captureStartFen,
          globalMoveOffset: globalMoveOffset,
        );
      } else {
        await _shareGifFallback(
          movesToAnimate: movesToAnimate,
          profile: profile,
          totalOutputFrames: totalOutputFrames,
          captureStartFen: captureStartFen,
          globalMoveOffset: globalMoveOffset,
        );
      }
    } catch (e, st) {
      debugPrint('GIF error: $e');
      debugPrint('GIF stack: $st');
      _showMessage('Failed to generate GIF', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingGif = false;
          _gifProgress = 0.0;
          _gifFrameFen = null;
          _gifFrameLastMove = null;
          _gifFrameWhiteClock = null;
          _gifFrameBlackClock = null;
          _gifFrameIsFinal = false;
        });
      }
    }
  }

  Future<void> _shareGifPipelined({
    required List<String> movesToAnimate,
    required GifExportProfile profile,
    required int totalOutputFrames,
    required SendPort workerSendPort,
    required Stream<dynamic> mainStream,
    required ReceivePort mainPort,
    required Isolate workerIsolate,
    String? captureStartFen,
    int globalMoveOffset = 0,
  }) async {
    int framesCaptured = 0;
    int framesAccepted = 0;
    int inFlight = 0;
    const maxInFlight = 4;
    bool workerFailed = false;
    Completer<void>? backpressureCompleter;
    final doneCompleter = Completer<Uint8List>();
    final includedMoves = profile.frameIndices.toSet();

    // Listen for worker responses on the broadcast stream
    final subscription = mainStream.listen((message) {
      if (message is GifWorkerFrameAccepted) {
        framesAccepted++;
        inFlight--;
        _updateGifProgress(framesCaptured, framesAccepted, totalOutputFrames);
        if (backpressureCompleter != null &&
            !backpressureCompleter!.isCompleted) {
          backpressureCompleter!.complete();
        }
      } else if (message is GifWorkerDone) {
        if (!doneCompleter.isCompleted) {
          doneCompleter.complete(message.gifBytes.materialize().asUint8List());
        }
      } else if (message is GifWorkerError) {
        debugPrint('GIF worker error: ${message.message}');
        workerFailed = true;
        inFlight--;
        // Unblock any backpressure wait so the capture loop can exit
        if (backpressureCompleter != null &&
            !backpressureCompleter!.isCompleted) {
          backpressureCompleter!.complete();
        }
        if (!doneCompleter.isCompleted) {
          doneCompleter.completeError(Exception(message.message));
        }
      }
    });

    try {
      // Helper: send a frame to the worker with backpressure.
      // Returns false if the worker has failed and sending should stop.
      Future<bool> sendFrame(
        Uint8List rgba,
        int width,
        int height,
        int durationCs,
        int outputIndex,
      ) async {
        while (inFlight >= maxInFlight && !workerFailed) {
          backpressureCompleter = Completer<void>();
          await backpressureCompleter!.future;
        }
        if (workerFailed) return false;
        final transferable = TransferableTypedData.fromList([rgba]);
        workerSendPort.send(
          GifWorkerFrameData(
            rgba: transferable,
            width: width,
            height: height,
            durationCs: durationCs,
            frameIndex: outputIndex,
          ),
        );
        inFlight++;
        framesCaptured++;
        _updateGifProgress(framesCaptured, framesAccepted, totalOutputFrames);
        return true;
      }

      // Capture initial position (output frame 0)
      Position position;
      if (captureStartFen != null) {
        try {
          position = Chess.fromSetup(Setup.parseFen(captureStartFen));
        } catch (e) {
          _showMessage('Invalid starting position for GIF', isError: true);
          return;
        }
      } else {
        position = Chess.initial;
      }
      if (!mounted) return;
      setState(() {
        _gifFrameFen = position.fen;
        _gifFrameLastMove = null;
        _gifFrameWhiteClock = null;
        _gifFrameBlackClock = null;
        _gifFrameIsFinal = false;
      });
      await WidgetsBinding.instance.endOfFrame;

      final initial = await _captureRawFrame(profile.pixelRatio);
      if (initial == null) {
        _showMessage('Failed to capture initial frame', isError: true);
        return;
      }
      final sent = await sendFrame(
        initial.rgba,
        initial.width,
        initial.height,
        profile.frameDurations[0],
        0,
      );
      if (!sent) return; // Worker failed during initial frame

      // Iterate ALL moves sequentially (SAN parsing is stateful).
      // Capture only at indices in the export profile.
      int outputIndex = 1; // next output frame index after initial

      for (int i = 0; i < movesToAnimate.length; i++) {
        if (workerFailed || _cancelled) return;

        final move = position.parseSan(movesToAnimate[i]);
        if (move == null) {
          // Abort: broken alignment would produce a corrupted GIF
          _showMessage('Failed to parse move ${i + 1}', isError: true);
          return;
        }
        position = position.play(move);

        if (!includedMoves.contains(i)) continue;

        // Extract from/to squares for last-move highlight
        NormalMove? lastMoveForDisplay;
        if (move is NormalMove) {
          lastMoveForDisplay = NormalMove(from: move.from, to: move.to);
        }

        final (whiteClock, blackClock) = _getClocksAtMoveIndex(
          i + globalMoveOffset,
        );
        final isGameEnd =
            widget.isAtGameEnd &&
            i + globalMoveOffset == widget.moveSans.length - 1;

        if (!mounted) return;
        setState(() {
          _gifFrameFen = position.fen;
          _gifFrameLastMove = lastMoveForDisplay;
          _gifFrameWhiteClock = whiteClock;
          _gifFrameBlackClock = blackClock;
          _gifFrameIsFinal = isGameEnd;
        });
        await WidgetsBinding.instance.endOfFrame;

        final frame = await _captureRawFrame(profile.pixelRatio);
        if (frame == null) {
          // Abort: broken alignment would produce a corrupted GIF
          _showMessage(
            'Failed to capture frame at move ${i + 1}',
            isError: true,
          );
          return;
        }
        final frameSent = await sendFrame(
          frame.rgba,
          frame.width,
          frame.height,
          profile.frameDurations[outputIndex],
          outputIndex,
        );
        if (!frameSent) return; // Worker failed
        outputIndex++;
      }

      // All frames sent, tell worker to finish
      workerSendPort.send(GifWorkerFinish());

      // Wait for the encoded result with timeout
      final gifBytes = await doneCompleter.future.timeout(
        const Duration(seconds: 30),
      );

      // Save and share
      if (mounted) setState(() => _gifProgress = 0.95);
      await _shareGeneratedGif(gifBytes);
    } finally {
      await subscription.cancel();
      mainPort.close();
      workerIsolate.kill(priority: Isolate.immediate);
    }
  }

  Future<void> _shareGifFallback({
    required List<String> movesToAnimate,
    required GifExportProfile profile,
    required int totalOutputFrames,
    String? captureStartFen,
    int globalMoveOffset = 0,
  }) async {
    final rawFrames = <_RawFrame>[];
    final durations = <int>[];
    final includedMoves = profile.frameIndices.toSet();

    // Capture initial position
    Position position;
    if (captureStartFen != null) {
      try {
        position = Chess.fromSetup(Setup.parseFen(captureStartFen));
      } catch (e) {
        _showMessage('Invalid starting position for GIF', isError: true);
        return;
      }
    } else {
      position = Chess.initial;
    }
    if (!mounted) return;
    setState(() {
      _gifFrameFen = position.fen;
      _gifFrameLastMove = null;
      _gifFrameWhiteClock = null;
      _gifFrameBlackClock = null;
      _gifFrameIsFinal = false;
    });
    await WidgetsBinding.instance.endOfFrame;

    final initial = await _captureRawFrame(profile.pixelRatio);
    if (initial == null) {
      _showMessage('Failed to capture initial frame', isError: true);
      return;
    }
    rawFrames.add(initial);
    durations.add(profile.frameDurations[0]);

    int durationIndex = 1;

    for (int i = 0; i < movesToAnimate.length; i++) {
      if (_cancelled) return;

      final move = position.parseSan(movesToAnimate[i]);
      if (move == null) {
        _showMessage('Failed to parse move ${i + 1}', isError: true);
        return;
      }
      position = position.play(move);

      if (!includedMoves.contains(i)) continue;

      NormalMove? lastMoveForDisplay;
      if (move is NormalMove) {
        lastMoveForDisplay = NormalMove(from: move.from, to: move.to);
      }

      final (whiteClock, blackClock) = _getClocksAtMoveIndex(
        i + globalMoveOffset,
      );
      final isGameEnd =
          widget.isAtGameEnd &&
          i + globalMoveOffset == widget.moveSans.length - 1;

      if (!mounted) return;
      setState(() {
        _gifFrameFen = position.fen;
        _gifFrameLastMove = lastMoveForDisplay;
        _gifFrameWhiteClock = whiteClock;
        _gifFrameBlackClock = blackClock;
        _gifFrameIsFinal = isGameEnd;
      });
      await WidgetsBinding.instance.endOfFrame;

      if (mounted) {
        _updateGifProgress(
          rawFrames.length,
          rawFrames.length - 1,
          totalOutputFrames,
        );
      }

      final frame = await _captureRawFrame(profile.pixelRatio);
      if (frame == null) {
        _showMessage('Failed to capture frame at move ${i + 1}', isError: true);
        return;
      }
      rawFrames.add(frame);
      durations.add(profile.frameDurations[durationIndex]);
      durationIndex++;
    }

    if (rawFrames.isEmpty) {
      _showMessage('No frames captured', isError: true);
      return;
    }

    if (mounted) setState(() => _gifProgress = 0.8);

    final gifBytes = encodeGifFallback(
      rgbaFrames: rawFrames.map((f) => f.rgba).toList(),
      widths: rawFrames.map((f) => f.width).toList(),
      heights: rawFrames.map((f) => f.height).toList(),
      durationsCs: durations,
    );

    if (gifBytes == null || gifBytes.isEmpty) {
      _showMessage('GIF encode returned empty data', isError: true);
      return;
    }

    if (mounted) setState(() => _gifProgress = 0.95);
    await _shareGeneratedGif(gifBytes);
  }

  Future<void> _copyPgn() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.pgn));
      HapticFeedback.lightImpact();
      _showMessage('PGN copied to clipboard!', isError: false);
    } catch (e) {
      debugPrint('Error copying PGN: $e');
      _showMessage('Failed to copy PGN', isError: true);
    }
  }

  Future<void> _copyShareUrl() async {
    final shareUrl = _effectiveShareUrl;
    if (shareUrl == null || shareUrl.isEmpty) return;

    try {
      await Clipboard.setData(ClipboardData(text: shareUrl));
      HapticFeedback.lightImpact();
      _showMessage('Copied to clipboard', isError: false);
    } catch (e) {
      debugPrint('Error copying share URL: $e');
      _showMessage('Failed to copy link', isError: true);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? kRedColor : kPrimaryColor,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEvalToggle() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20.br),
        border: Border.all(color: context.colors.surfaceRecessed),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 16.sp,
            color:
                _showEvalBar ? kPrimaryColor : context.colors.textPrimaryMuted,
          ),
          SizedBox(width: 8.w),
          Text(
            'Eval Bar',
            style: TextStyle(
              color:
                  _showEvalBar
                      ? context.colors.textPrimary
                      : context.colors.textPrimaryMuted,
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: 10.w),
          // Custom mini toggle
          GestureDetector(
            onTap: () => setState(() => _showEvalBar = !_showEvalBar),
            child: AnimatedContainer(
              duration: 200.ms,
              width: 40.w,
              height: 22.h,
              decoration: BoxDecoration(
                color:
                    _showEvalBar
                        ? kPrimaryColor
                        : context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(11.br),
                border: Border.all(
                  color: _showEvalBar ? kPrimaryColor : context.colors.divider,
                  width: 1,
                ),
              ),
              child: AnimatedAlign(
                duration: 200.ms,
                alignment:
                    _showEvalBar ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: EdgeInsets.all(2),
                  width: 18.h,
                  height: 18.h,
                  decoration: BoxDecoration(
                    color: context.colors.textPrimary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
    bool enabled = true,
    String? disabledMessage,
  }) {
    final effectiveOnTap =
        enabled
            ? onTap
            : () =>
                _showMessage(disabledMessage ?? 'Not available', isError: true);

    final content = Container(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      decoration: BoxDecoration(
        color: isPrimary ? kPrimaryColor : context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(8.br),
        border:
            isPrimary
                ? null
                : Border.all(color: context.colors.divider, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18.sp,
            color:
                isPrimary
                    ? context.colors.textPrimary
                    : context.colors.textPrimary,
          ),
          SizedBox(width: 8.w),
          Text(
            label,
            style: TextStyle(
              color:
                  isPrimary
                      ? context.colors.textPrimary
                      : context.colors.textPrimary,
              fontSize: 13.sp,
              fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    return Expanded(
      child: GestureDetector(
        onTap: effectiveOnTap,
        child: enabled ? content : Opacity(opacity: 0.4, child: content),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      width: 370.w,
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: context.colors.surfaceRecessed),
      ),
      child: Row(
        children: [
          _buildActionButton(
            icon: Icons.image_outlined,
            label: 'Share Image',
            onTap: _shareImage,
            isPrimary: true,
          ),
          SizedBox(width: 4.w),
          _buildActionButton(
            icon: Icons.gif_box_outlined,
            label: 'Share GIF',
            onTap: _shareGif,
          ),
          SizedBox(width: 4.w),
          _buildActionButton(
            icon: Icons.copy_outlined,
            label: 'Copy PGN',
            onTap: _copyPgn,
          ),
        ],
      ),
    );
  }

  Widget _buildGifProgress() {
    return Container(
      width: 370.w,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: context.colors.surfaceRecessed),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16.w,
                height: 16.h,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kPrimaryColor,
                ),
              ),
              SizedBox(width: 10.w),
              Text(
                'Generating GIF... ${(_gifProgress * 100).toInt()}%',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          // Linear progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4.br),
            child: LinearProgressIndicator(
              value: _gifProgress,
              backgroundColor: context.colors.surfaceRecessed,
              valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
              minHeight: 6.h,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareLinkBar() {
    final shareUrl = _effectiveShareUrl;
    if (shareUrl == null || shareUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 370.w,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: const Color(0xFF141A20),
        borderRadius: BorderRadius.circular(22.br),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shareUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Material(
            color: context.colors.textPrimary.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _copyShareUrl,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: EdgeInsets.all(8.sp),
                child: Icon(
                  Icons.copy_rounded,
                  size: 18.sp,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.transparent),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Visible preview card with 3D effect
                  GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _rotationY =
                                (details.localPosition.dx / 350.w - 0.5) * 0.15;
                            _rotationX =
                                -(details.localPosition.dy / 600.h - 0.5) *
                                0.15;
                          });
                        },
                        onPanEnd: (details) {
                          setState(() {
                            _rotationX = 0.0;
                            _rotationY = 0.0;
                          });
                        },
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          transform:
                              Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..rotateX(_rotationX)
                                ..rotateY(_rotationY),
                          transformAlignment: Alignment.center,
                          child: _ShareCard(
                            boardSettings: widget.boardSettings,
                            positionFen: widget.positionFen,
                            lastMove: widget.lastMove,
                            onClose: widget.onClose,
                            pgn: widget.pgn,
                            moveSans: widget.moveSans,
                            whitePlayerName: widget.whitePlayerName,
                            blackPlayerName: widget.blackPlayerName,
                            whitePlayerCountry: widget.whitePlayerCountry,
                            blackPlayerCountry: widget.blackPlayerCountry,
                            whitePlayerElo: widget.whitePlayerElo,
                            blackPlayerElo: widget.blackPlayerElo,
                            whitePlayerTitle: widget.whitePlayerTitle,
                            blackPlayerTitle: widget.blackPlayerTitle,
                            whitePlayerClock: widget.whitePlayerClock,
                            blackPlayerClock: widget.blackPlayerClock,
                            tournamentName: widget.tournamentName,
                            roundInfo: widget.roundInfo,
                            currentMoveIndex: widget.currentMoveIndex,
                            evaluation: widget.evaluation,
                            mate: widget.mate,
                            isFlipped: widget.isFlipped,
                            gameStatus: widget.gameStatus,
                            isAtGameEnd: widget.isAtGameEnd,
                            isPreview: true,
                            showEvalBar: _showEvalBar,
                            gameId: widget.gameId,
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .scale(begin: Offset(0.95, 0.95), duration: 300.ms),
                  SizedBox(height: 16.h),
                  // Eval bar toggle - modern pill style
                  _buildEvalToggle().animate().fadeIn(
                    delay: 150.ms,
                    duration: 300.ms,
                  ),
                  SizedBox(height: 16.h),
                  _buildShareLinkBar().animate().fadeIn(
                    delay: 180.ms,
                    duration: 300.ms,
                  ),
                  if ((_effectiveShareUrl ?? '').isNotEmpty)
                    SizedBox(height: 16.h),
                  // Action buttons or progress
                  if (_isGenerating)
                    CircularProgressIndicator(
                      color: kPrimaryColor,
                      strokeWidth: 2,
                    )
                  else if (_isGeneratingGif)
                    _buildGifProgress().animate().fadeIn(duration: 200.ms)
                  else
                    _buildActionButtons().animate().fadeIn(
                      delay: 200.ms,
                      duration: 300.ms,
                    ),
                ],
              ),
            ),
            // Offscreen full card for screenshot (with all moves)
            // Position off-screen instead of using Offstage to ensure proper rendering
            Positioned(
              left: -10000,
              top: -10000,
              child: Screenshot(
                controller: _fullScreenshotController,
                child: Container(
                  color: context.colors.background,
                  padding: EdgeInsets.all(16.w),
                  child: _ShareCard(
                    boardSettings: widget.boardSettings,
                    positionFen: widget.positionFen,
                    lastMove: widget.lastMove,
                    onClose: null,
                    pgn: widget.pgn,
                    moveSans: widget.moveSans,
                    whitePlayerName: widget.whitePlayerName,
                    blackPlayerName: widget.blackPlayerName,
                    whitePlayerCountry: widget.whitePlayerCountry,
                    blackPlayerCountry: widget.blackPlayerCountry,
                    whitePlayerElo: widget.whitePlayerElo,
                    blackPlayerElo: widget.blackPlayerElo,
                    whitePlayerTitle: widget.whitePlayerTitle,
                    blackPlayerTitle: widget.blackPlayerTitle,
                    whitePlayerClock: widget.whitePlayerClock,
                    blackPlayerClock: widget.blackPlayerClock,
                    tournamentName: widget.tournamentName,
                    roundInfo: widget.roundInfo,
                    currentMoveIndex: widget.currentMoveIndex,
                    evaluation: widget.evaluation,
                    mate: widget.mate,
                    isFlipped: widget.isFlipped,
                    gameStatus: widget.gameStatus,
                    isAtGameEnd: widget.isAtGameEnd,
                    isPreview: false,
                    showEvalBar: _showEvalBar,
                    gameId: widget.gameId,
                  ),
                ),
              ),
            ),
            // Offscreen GIF frame widget - uses RepaintBoundary with GlobalKey for raw RGBA capture
            // This avoids PNG encoding issues on iOS P3 displays
            // Uses board settings with animations DISABLED for instant static frame capture
            Positioned(
              left: -10000,
              top: -10000,
              child: RepaintBoundary(
                key: _gifFrameKey,
                child: _ShareCard(
                  boardSettings:
                      _gifBoardSettings, // Animation disabled settings
                  positionFen: _gifFrameFen ?? widget.positionFen,
                  lastMove: _gifFrameLastMove,
                  onClose: null,
                  pgn: widget.pgn,
                  moveSans: widget.moveSans,
                  whitePlayerName: widget.whitePlayerName,
                  blackPlayerName: widget.blackPlayerName,
                  whitePlayerCountry: widget.whitePlayerCountry,
                  blackPlayerCountry: widget.blackPlayerCountry,
                  whitePlayerElo: widget.whitePlayerElo,
                  blackPlayerElo: widget.blackPlayerElo,
                  whitePlayerTitle: widget.whitePlayerTitle,
                  blackPlayerTitle: widget.blackPlayerTitle,
                  whitePlayerClock:
                      _gifFrameWhiteClock, // Dynamic clock per frame
                  blackPlayerClock:
                      _gifFrameBlackClock, // Dynamic clock per frame
                  tournamentName: widget.tournamentName,
                  roundInfo: widget.roundInfo,
                  currentMoveIndex: widget.currentMoveIndex,
                  evaluation: null, // No eval in GIF
                  mate: 0,
                  isFlipped: widget.isFlipped,
                  // Only show game ending effects (fallen king, peace icons) on final frame
                  gameStatus:
                      _gifFrameIsFinal ? widget.gameStatus : GameStatus.ongoing,
                  isAtGameEnd: _gifFrameIsFinal,
                  isPreview: false,
                  showEvalBar: false, // No eval bar in GIF
                  reserveClockSpace: true,
                  gameId: widget.gameId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareCard extends ConsumerWidget {
  static const String _clockPlaceholder = '00:00:00';

  final ChessboardSettings boardSettings;
  final String positionFen;
  final Move? lastMove;
  final VoidCallback? onClose;
  final String pgn;
  final List<String> moveSans; // The actual move list from analysis state
  final String whitePlayerName;
  final String blackPlayerName;
  final String? whitePlayerCountry;
  final String? blackPlayerCountry;
  final String? whitePlayerElo;
  final String? blackPlayerElo;
  final String? whitePlayerTitle;
  final String? blackPlayerTitle;
  final String? whitePlayerClock;
  final String? blackPlayerClock;
  final String? tournamentName;
  final String? roundInfo;
  final int currentMoveIndex;
  final double? evaluation;
  final int mate;
  final bool isFlipped;
  final GameStatus gameStatus;
  final bool isAtGameEnd;
  final bool isPreview;
  final bool showEvalBar;
  final bool reserveClockSpace;
  final String gameId; // CRITICAL: Include game ID for correct eval caching

  const _ShareCard({
    required this.boardSettings,
    required this.positionFen,
    required this.lastMove,
    this.onClose,
    required this.pgn,
    required this.moveSans,
    required this.whitePlayerName,
    required this.blackPlayerName,
    this.whitePlayerCountry,
    this.blackPlayerCountry,
    this.whitePlayerElo,
    this.blackPlayerElo,
    this.whitePlayerTitle,
    this.blackPlayerTitle,
    this.whitePlayerClock,
    this.blackPlayerClock,
    this.tournamentName,
    this.roundInfo,
    required this.currentMoveIndex,
    required this.evaluation,
    required this.mate,
    required this.isFlipped,
    required this.gameStatus,
    this.isAtGameEnd = false,
    this.isPreview = false,
    this.showEvalBar = true,
    this.reserveClockSpace = false,
    required this.gameId, // REQUIRED for correct eval caching
  });

  Widget _buildEndScoreWidget({
    required BuildContext context,
    required bool isWhitePlayer,
  }) {
    // For finished games, display end scores similar to main chess board screen
    final scoreStyle = AppTypography.textXsBold.copyWith(
      color: context.colors.textPrimary,
      fontSize: 14.sp, // Bigger for better proportion
      fontWeight: FontWeight.w700,
      height: 1.0,
    );

    switch (gameStatus) {
      case GameStatus.whiteWins:
        return Text(
          isWhitePlayer ? '1' : '0',
          style: scoreStyle,
          textAlign: TextAlign.center,
        );
      case GameStatus.blackWins:
        return Text(
          isWhitePlayer ? '0' : '1',
          style: scoreStyle,
          textAlign: TextAlign.center,
        );
      case GameStatus.draw:
        return Text('½', style: scoreStyle, textAlign: TextAlign.center);
      case GameStatus.ongoing:
      case GameStatus.unknown:
        return SizedBox.shrink();
    }
  }

  /// Build player row matching PlayerFirstRowDetailWidget boardView style exactly
  Widget _buildPlayerRow({
    required BuildContext context,
    required String playerName,
    required String playerCountry,
    required String? playerElo,
    required String? playerTitle,
    required String? playerClock,
    required bool isWhitePlayer,
    required double sideBarWidth,
    required bool reserveClockSpace,
  }) {
    // Text styles matching PlayerFirstRowDetailWidget boardView
    final titleStyle = AppTypography.textXsMedium.copyWith(
      color: kLightYellowColor,
      fontWeight: FontWeight.w700,
      fontSize: 14.sp,
      height: 1.2,
    );

    final nameStyle = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimary,
      fontWeight: FontWeight.w600,
      fontSize: 14.sp,
      height: 1.2,
    );

    // Rating style - matches PlayerFirstRowDetailWidget (context.colors.textPrimaryMuted)
    final ratingStyle = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimaryMuted,
      fontWeight: FontWeight.w600,
      fontSize: 14.sp,
      height: 1.2,
    );

    final timeStyle = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Flag sizing matching boardView
    const flagHeight = 12.0;
    const flagWidth = 16.0;
    const elementSpacing = 8.0;

    // Parse name parts - format is "Surname, Given Names"
    final nameParts = playerName.split(',').map((e) => e.trim()).toList();
    final surname = nameParts.isNotEmpty ? nameParts[0] : '';
    final firstName = nameParts.length > 1 ? nameParts[1] : '';
    final rating = playerElo != null ? ' $playerElo' : '';
    final title = playerTitle ?? '';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          // Score area - matches eval bar width
          SizedBox(
            width: sideBarWidth.w,
            child: Center(
              child: _buildEndScoreWidget(
                context: context,
                isWhitePlayer: isWhitePlayer,
              ),
            ),
          ),
          SizedBox(width: elementSpacing.w),
          // Show a real country flag only when the country is known.
          if (playerCountry.isNotEmpty) ...[
            CountryFlag.fromCountryCode(
              playerCountry,
              theme: ImageTheme(height: flagHeight.h, width: flagWidth.w),
            ),
            SizedBox(width: elementSpacing.w),
          ] else
            SizedBox(width: elementSpacing.w),
          // Name + Rating with smart truncation (matching PlayerFirstRowDetailWidget)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textPainter = TextPainter(
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                );

                String displaySurname = surname;
                String displayFirstName =
                    firstName.isNotEmpty ? ', $firstName' : '';

                if (surname.isNotEmpty) {
                  // Strategy 1: Try full surname + full first name + rating
                  textPainter.text = TextSpan(
                    children: [
                      if (title.isNotEmpty)
                        TextSpan(text: '$title ', style: titleStyle),
                      TextSpan(text: surname, style: nameStyle),
                      if (firstName.isNotEmpty)
                        TextSpan(text: ', $firstName', style: nameStyle),
                      TextSpan(text: rating, style: ratingStyle),
                    ],
                  );
                  textPainter.layout();

                  if (textPainter.width > constraints.maxWidth &&
                      firstName.isNotEmpty) {
                    // Strategy 2: Keep full surname + abbreviate first name
                    final firstNameParts = firstName.split(' ');
                    final abbreviatedFirst = firstNameParts
                        .where((part) => part.isNotEmpty)
                        .map((part) => '${part[0]}.')
                        .join(' ');
                    displayFirstName = ', $abbreviatedFirst';

                    textPainter.text = TextSpan(
                      children: [
                        if (title.isNotEmpty)
                          TextSpan(text: '$title ', style: titleStyle),
                        TextSpan(text: surname, style: nameStyle),
                        TextSpan(text: displayFirstName, style: nameStyle),
                        TextSpan(text: rating, style: ratingStyle),
                      ],
                    );
                    textPainter.layout();

                    // Strategy 3: If still doesn't fit, drop first name entirely
                    if (textPainter.width > constraints.maxWidth) {
                      displayFirstName = '';
                    }
                  }
                }

                return RichText(
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.left,
                  text: TextSpan(
                    style: nameStyle,
                    children: [
                      if (title.isNotEmpty)
                        TextSpan(text: '$title ', style: titleStyle),
                      if (displaySurname.isNotEmpty)
                        TextSpan(text: displaySurname, style: nameStyle),
                      if (displayFirstName.isNotEmpty)
                        TextSpan(text: displayFirstName, style: nameStyle),
                      TextSpan(text: rating, style: ratingStyle),
                    ],
                  ),
                );
              },
            ),
          ),
          // Clock time on far right. GIF captures reserve this slot from the
          // initial frame so later clock updates cannot resize the card.
          if (playerClock != null || reserveClockSpace) ...[
            SizedBox(width: 8.w),
            Visibility(
              visible: playerClock != null,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: Text(playerClock ?? _clockPlaceholder, style: timeStyle),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the actual moveSans from analysis state instead of parsing PGN

    final whiteCountry =
        whitePlayerCountry != null
            ? ref
                .read(locationServiceProvider)
                .getValidCountryCode(whitePlayerCountry!)
            : '';
    final blackCountry =
        blackPlayerCountry != null
            ? ref
                .read(locationServiceProvider)
                .getValidCountryCode(blackPlayerCountry!)
            : '';
    final boardOrientation = isFlipped ? Side.black : Side.white;

    // Determine which player info to show at top and bottom based on isFlipped
    // When not flipped: black at top, white at bottom (normal view)
    // When flipped: white at top, black at bottom (reversed view)
    final topPlayerName = isFlipped ? whitePlayerName : blackPlayerName;
    final topPlayerCountry = isFlipped ? whiteCountry : blackCountry;
    final topPlayerElo = isFlipped ? whitePlayerElo : blackPlayerElo;
    final topPlayerTitle = isFlipped ? whitePlayerTitle : blackPlayerTitle;
    final topPlayerClock = isFlipped ? whitePlayerClock : blackPlayerClock;
    final topIsWhitePlayer = isFlipped;

    final bottomPlayerName = isFlipped ? blackPlayerName : whitePlayerName;
    final bottomPlayerCountry = isFlipped ? blackCountry : whiteCountry;
    final bottomPlayerElo = isFlipped ? blackPlayerElo : whitePlayerElo;
    final bottomPlayerTitle = isFlipped ? blackPlayerTitle : whitePlayerTitle;
    final bottomPlayerClock = isFlipped ? blackPlayerClock : whitePlayerClock;
    final bottomIsWhitePlayer = !isFlipped;

    // Always reserve space for eval bar to prevent layout shift
    const sideBarWidth = 20.0;

    final cardContent = Container(
      width: 370.w,
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: context.colors.divider, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 12.h),
          if (tournamentName != null) ...[
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Text(
                tournamentName!,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (roundInfo != null)
            Text(
              roundInfo!,
              style: TextStyle(
                color: context.colors.textPrimaryMuted,
                fontSize: 9.sp,
              ),
            ),
          SizedBox(height: 12.h),
          // Top player row - matching PlayerFirstRowDetailWidget exactly
          _buildPlayerRow(
            context: context,
            playerName: topPlayerName,
            playerCountry: topPlayerCountry,
            playerElo: topPlayerElo,
            playerTitle: topPlayerTitle,
            playerClock: topPlayerClock,
            isWhitePlayer: topIsWhitePlayer,
            sideBarWidth: sideBarWidth,
            reserveClockSpace: reserveClockSpace,
          ),
          SizedBox(height: 12.h),
          // Board with optional evaluation bar and game ending overlays
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Always reserve space for eval bar
                final reservedWidth = sideBarWidth.w;
                final availableWidth = constraints.maxWidth;
                final boardSize = math.max(1.0, availableWidth - reservedWidth);
                final fenParts = positionFen.split(' ');
                final overlayWhiteToMove =
                    fenParts.length > 1 ? fenParts[1] == 'w' : true;

                // Calculate game ending data for overlays — only at the actual final position
                final gameEndingData = _calculateShareGameEndingData(
                  positionFen,
                  gameStatus,
                );
                final showGameEndingEffect =
                    isAtGameEnd &&
                    gameStatus != GameStatus.ongoing &&
                    gameStatus != GameStatus.unknown;

                // Prepare FEN - remove loser's king if showing fallen king overlay
                String displayFen = positionFen;
                if (showGameEndingEffect &&
                    gameEndingData?.loserKingSquare != null) {
                  final loserSide = gameEndingData!.loserSide;
                  final kingChar = loserSide == Side.white ? 'K' : 'k';
                  displayFen = _removeKingFromShareFen(
                    positionFen,
                    gameEndingData.loserKingSquare!,
                    kingChar,
                  );
                }

                // Build chessboard with square highlights
                final chessboard = StaticChessboard(
                  size: boardSize,
                  fen: displayFen,
                  orientation: boardOrientation,
                  lastMove: lastMove,
                  settings: StaticChessboardSettings.fromBoardSettings(
                    boardSettings,
                  ),
                  squareHighlights:
                      showGameEndingEffect
                          ? (gameEndingData?.squareHighlights.unlock ??
                              const <Square, SquareHighlight>{})
                          : const <Square, SquareHighlight>{},
                );

                // Build board widget with overlays if game ended
                Widget boardWidget;
                final squareSize = boardSize / 8;

                if (showGameEndingEffect &&
                    gameEndingData?.loserKingSquare != null) {
                  // Game ended with a winner - show fallen king overlay
                  final loserSquare = gameEndingData!.loserKingSquare!;
                  final loserSide = gameEndingData.loserSide!;

                  // Calculate square position on board
                  final file = loserSquare.file;
                  final rank = loserSquare.rank;

                  // Adjust for board orientation
                  final effectiveFile = isFlipped ? 7 - file : file;
                  final effectiveRank = isFlipped ? rank : 7 - rank;

                  // Get piece image from board settings
                  final pieceKind =
                      loserSide == Side.white
                          ? PieceKind.whiteKing
                          : PieceKind.blackKing;
                  final pieceImage = boardSettings.pieceAssets[pieceKind];

                  boardWidget = Stack(
                    children: [
                      chessboard,
                      // Fallen king overlay - animate for preview, static for capture
                      if (pieceImage != null)
                        _ShareFallenKingOverlay(
                          left: effectiveFile * squareSize,
                          top: effectiveRank * squareSize,
                          squareSize: squareSize,
                          pieceImage: pieceImage,
                          animate: isPreview,
                        ),
                    ],
                  );
                } else if (showGameEndingEffect &&
                    gameStatus == GameStatus.draw) {
                  // Game ended in draw - show peace icons on both kings
                  final position = Chess.fromSetup(Setup.parseFen(positionFen));
                  final board = position.board;
                  final whiteKingSquare = board.kingOf(Side.white);
                  final blackKingSquare = board.kingOf(Side.black);

                  if (whiteKingSquare != null && blackKingSquare != null) {
                    boardWidget = Stack(
                      children: [
                        chessboard,
                        // Peace icon on white king
                        _SharePeaceIcon(
                          square: whiteKingSquare,
                          squareSize: squareSize,
                          isFlipped: isFlipped,
                          delayMs: 0,
                          animate: isPreview,
                        ),
                        // Peace icon on black king (slight delay for stagger in preview)
                        _SharePeaceIcon(
                          square: blackKingSquare,
                          squareSize: squareSize,
                          isFlipped: isFlipped,
                          delayMs: isPreview ? 100 : 0,
                          animate: isPreview,
                        ),
                      ],
                    );
                  } else {
                    boardWidget = chessboard;
                  }
                } else {
                  boardWidget = chessboard;
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Always render eval bar container, use opacity for visibility
                    SizedBox(
                      width: reservedWidth,
                      height: boardSize,
                      child: AnimatedOpacity(
                        opacity: showEvalBar ? 1.0 : 0.0,
                        duration: Duration(milliseconds: 200),
                        child: EvaluationBarWidget(
                          width: reservedWidth,
                          height: boardSize,
                          evaluation: evaluation,
                          mate: mate != 0 ? mate : null,
                          isEvaluating: evaluation == null && mate == 0,
                          isFlipped: isFlipped,
                          isWhiteToMove: overlayWhiteToMove,
                          positionKey: positionFen,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: boardSize,
                      height: boardSize,
                      child: boardWidget,
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 12.h),
          // Bottom player row - matching PlayerFirstRowDetailWidget exactly
          _buildPlayerRow(
            context: context,
            playerName: bottomPlayerName,
            playerCountry: bottomPlayerCountry,
            playerElo: bottomPlayerElo,
            playerTitle: bottomPlayerTitle,
            playerClock: bottomPlayerClock,
            isWhitePlayer: bottomIsWhitePlayer,
            sideBarWidth: sideBarWidth,
            reserveClockSpace: reserveClockSpace,
          ),
          SizedBox(
            height: 20.h,
          ), // Extra padding to prevent bottom border cutoff in GIF
        ],
      ),
    );

    if (!isPreview || onClose == null) {
      return cardContent;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        cardContent,
        Positioned(
          top: 8.w,
          right: 8.w,
          child: GestureDetector(
            onTap: onClose,
            child: Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 16.sp,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Data class for game ending visual effects in share card
class _ShareGameEndingData {
  final IMap<Square, SquareHighlight> squareHighlights;
  final Square? loserKingSquare;
  final Side? loserSide;

  const _ShareGameEndingData({
    required this.squareHighlights,
    required this.loserKingSquare,
    required this.loserSide,
  });
}

/// Calculate game ending visual data for share card
_ShareGameEndingData? _calculateShareGameEndingData(
  String fen,
  GameStatus gameStatus,
) {
  // Parse position to find king squares
  final position = Chess.fromSetup(Setup.parseFen(fen));
  final board = position.board;
  final whiteKingSquare = board.kingOf(Side.white);
  final blackKingSquare = board.kingOf(Side.black);

  if (whiteKingSquare == null || blackKingSquare == null) {
    return null;
  }

  // Convert dartchess Square to chessground Square
  final whiteKingCgSquare = Square.fromName(whiteKingSquare.name);
  final blackKingCgSquare = Square.fromName(blackKingSquare.name);

  if (gameStatus == GameStatus.draw) {
    // Draw: mint green background for both kings
    return _ShareGameEndingData(
      squareHighlights: IMap({
        whiteKingCgSquare: const SquareHighlight(
          details: HighlightDetails(
            solidColor: Color(0xCCADE1CD), // Mint green with alpha
          ),
        ),
        blackKingCgSquare: const SquareHighlight(
          details: HighlightDetails(
            solidColor: Color(0xCCADE1CD), // Mint green with alpha
          ),
        ),
      }),
      loserKingSquare: null,
      loserSide: null,
    );
  } else if (gameStatus == GameStatus.whiteWins) {
    // White wins: black king is the loser
    return _ShareGameEndingData(
      squareHighlights: IMap({
        blackKingCgSquare: const SquareHighlight(
          details: HighlightDetails(
            solidColor: Color(0xCCF53236), // Red with alpha
          ),
        ),
      }),
      loserKingSquare: blackKingSquare,
      loserSide: Side.black,
    );
  } else if (gameStatus == GameStatus.blackWins) {
    // Black wins: white king is the loser
    return _ShareGameEndingData(
      squareHighlights: IMap({
        whiteKingCgSquare: const SquareHighlight(
          details: HighlightDetails(
            solidColor: Color(0xCCF53236), // Red with alpha
          ),
        ),
      }),
      loserKingSquare: whiteKingSquare,
      loserSide: Side.white,
    );
  }

  return null;
}

/// Remove a king from FEN string to hide it when showing fallen king overlay
String _removeKingFromShareFen(String fen, Square square, String kingChar) {
  final parts = fen.split(' ');
  if (parts.isEmpty) return fen;

  final ranks = parts[0].split('/');
  final rankIndex = 7 - square.rank; // FEN ranks are 8-1 (top to bottom)
  if (rankIndex < 0 || rankIndex >= ranks.length) return fen;

  // Expand the rank to individual characters
  final rank = ranks[rankIndex];
  final expanded = StringBuffer();
  for (final char in rank.split('')) {
    final digit = int.tryParse(char);
    if (digit != null) {
      expanded.write('1' * digit); // Replace numbers with 1s
    } else {
      expanded.write(char);
    }
  }

  // Remove the king at the file position
  final fileIndex = square.file;
  final chars = expanded.toString().split('');
  if (fileIndex >= 0 &&
      fileIndex < chars.length &&
      chars[fileIndex] == kingChar) {
    chars[fileIndex] = '1';
  }

  // Compress back: consecutive 1s become a single number
  final compressed = StringBuffer();
  int emptyCount = 0;
  for (final char in chars) {
    if (char == '1') {
      emptyCount++;
    } else {
      if (emptyCount > 0) {
        compressed.write(emptyCount);
        emptyCount = 0;
      }
      compressed.write(char);
    }
  }
  if (emptyCount > 0) {
    compressed.write(emptyCount);
  }

  ranks[rankIndex] = compressed.toString();
  parts[0] = ranks.join('/');
  return parts.join(' ');
}

/// Fallen king overlay for share card - shows king tilted 45 degrees
/// Uses motor springs for smooth animation when displayed
class _ShareFallenKingOverlay extends StatefulWidget {
  final double left;
  final double top;
  final double squareSize;
  final ImageProvider pieceImage;
  final bool animate;

  const _ShareFallenKingOverlay({
    required this.left,
    required this.top,
    required this.squareSize,
    required this.pieceImage,
    this.animate = true,
  });

  @override
  State<_ShareFallenKingOverlay> createState() =>
      _ShareFallenKingOverlayState();
}

class _ShareFallenKingOverlayState extends State<_ShareFallenKingOverlay> {
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      // Trigger animation after first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _animate = true);
        }
      });
    } else {
      // Start already animated for static captures
      _animate = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left,
      top: widget.top,
      child: SizedBox(
        width: widget.squareSize,
        height: widget.squareSize,
        child: Center(
          child:
              widget.animate
                  ? SingleMotionBuilder(
                    motion: const CupertinoMotion.bouncy(),
                    value:
                        _animate
                            ? -math.pi / 4
                            : 0.0, // -45 degrees when animated
                    builder: (context, rotation, child) {
                      return Transform.rotate(
                        angle: rotation,
                        alignment: Alignment.center,
                        child: child,
                      );
                    },
                    child: Image(image: widget.pieceImage, fit: BoxFit.contain),
                  )
                  : Transform.rotate(
                    angle: -math.pi / 4, // -45 degrees (static)
                    alignment: Alignment.center,
                    child: Image(image: widget.pieceImage, fit: BoxFit.contain),
                  ),
        ),
      ),
    );
  }
}

/// Peace icon overlay for draw games in share card
/// Shows dove emoji in top-right corner of king's square
class _SharePeaceIcon extends StatefulWidget {
  final Square square;
  final double squareSize;
  final bool isFlipped;
  final int delayMs;
  final bool animate;

  const _SharePeaceIcon({
    required this.square,
    required this.squareSize,
    required this.isFlipped,
    this.delayMs = 0,
    this.animate = true,
  });

  @override
  State<_SharePeaceIcon> createState() => _SharePeaceIconState();
}

class _SharePeaceIconState extends State<_SharePeaceIcon> {
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      // Trigger animation after delay for stagger effect
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) {
          setState(() => _animate = true);
        }
      });
    } else {
      // Start already animated for static captures
      _animate = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.square.file;
    final rank = widget.square.rank;

    // Adjust for board orientation
    final effectiveFile = widget.isFlipped ? 7 - file : file;
    final effectiveRank = widget.isFlipped ? rank : 7 - rank;

    // Smaller icon size for subtle appearance
    final containerSize = widget.squareSize * 0.28;

    return Positioned(
      // Position at top-right corner of the king's square
      left:
          effectiveFile * widget.squareSize +
          widget.squareSize -
          containerSize -
          1,
      top: effectiveRank * widget.squareSize + 1,
      child:
          widget.animate
              ? SingleMotionBuilder(
                motion: const CupertinoMotion.bouncy(),
                value: _animate ? 1.0 : 0.0,
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    alignment: Alignment.topRight,
                    child: child,
                  );
                },
                child: _buildIcon(containerSize),
              )
              : _buildIcon(containerSize),
    );
  }

  Widget _buildIcon(double containerSize) {
    return Container(
      width: containerSize,
      height: containerSize,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
          child: Text('🕊️', style: TextStyle(fontSize: containerSize * 0.6)),
        ),
      ),
    );
  }
}
